import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../providers/service_providers.dart';
import '../services/attachments/attachment_crypto.dart';
import '../services/attachments/attachment_service.dart';
import '../services/attachments/attachment_types.dart';
import 'undo_snackbar.dart';

/// Local attachment list for one to-do or event.
///
/// The row metadata syncs; bytes stay in the encrypted device-local store. This
/// widget is intentionally only shown for saved items, because an attachment
/// needs a real parent id. A new item shows a short hint instead.
class AttachmentStrip extends ConsumerStatefulWidget {
  const AttachmentStrip({
    super.key,
    this.todoId,
    this.eventId,
    this.enabled = true,
    this.showHintWhenNew = true,
    this.onDownload,
    this.onKeep,
  }) : assert(
         todoId == null || eventId == null,
         'Attach to at most one parent',
       );

  final String? todoId;
  final String? eventId;
  final bool enabled;
  final bool showHintWhenNew;

  /// Phone-only actions for a blob the desktop holds but this device does not.
  final Future<bool> Function(Attachment attachment)? onDownload;
  final Future<void> Function(Attachment attachment, bool pinned)? onKeep;

  @override
  ConsumerState<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends ConsumerState<AttachmentStrip> {
  bool _busy = false;
  bool _dragging = false;
  int _downloadGeneration = 0;

  bool get _isNew => widget.todoId == null && widget.eventId == null;

  Future<void> _download(Attachment attachment) async {
    final download = widget.onDownload;
    if (download == null) return;
    final ok = await download(attachment);
    if (!mounted) return;
    if (ok) {
      setState(() => _downloadGeneration++);
    } else {
      _message('Could not download this attachment. Try syncing again.');
    }
  }

  Future<void> _keep(Attachment attachment) async {
    final keep = widget.onKeep;
    if (keep == null) return;
    await keep(attachment, true);
    if (mounted) _message('Kept on this device.');
  }

  Future<void> _pickFiles(AttachmentService service) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      for (final picked in result.files) {
        final path = picked.path;
        if (path == null) continue;
        try {
          await service.importFile(
            file: File(path),
            todoId: widget.todoId,
            eventId: widget.eventId,
            displayName: picked.name,
          );
        } on AttachmentImportException catch (error) {
          _message(error.message);
        } on FileSystemException {
          _message('The selected file could not be read.');
        }
      }
      if (await service.isOverSoftQuota() && mounted) {
        _message(
          'Attachments now use more than 1 GB on this device. '
          'Consider removing old files.',
        );
      }
    } catch (_) {
      _message('Attachments are unavailable right now.');
      // Do not log the picker error: it can contain a file name or path.
      debugPrint('Attachment picker failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importPaths(
    AttachmentService service,
    List<DropItem> files,
  ) async {
    if (_busy || files.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final dropped in files) {
        try {
          await service.importFile(
            file: File(dropped.path),
            todoId: widget.todoId,
            eventId: widget.eventId,
            displayName: p.basename(dropped.path),
          );
        } on AttachmentImportException catch (error) {
          _message(error.message);
        } on FileSystemException {
          _message('The dropped file could not be read.');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AttachmentService service, Attachment attachment) async {
    await service.remove(attachment.id);
    if (!mounted) return;
    UndoSnackbar.show(
      context,
      message: 'Attachment removed',
      service: ref.read(undoServiceProvider),
    );
  }

  Future<void> _view(AttachmentService service, Attachment attachment) async {
    try {
      if (attachment.kind == 'image') {
        final bytes = await service.readBytes(attachment);
        if (!mounted) return;
        await _showImage(attachment, bytes);
        return;
      }
      if (Platform.isWindows && widget.enabled) {
        final file = await service.open(attachment);
        await Process.run('rundll32', [
          'url.dll,FileProtocolHandler',
          file.path,
        ]);
        return;
      }
      if (Platform.isAndroid) {
        final file = await service.open(attachment);
        await _shareOnAndroid(file, attachment);
        return;
      }
      if (!mounted) return;
      await _showFileDetails(attachment);
    } on AttachmentBlobCorruptException {
      _message('This attachment is missing or failed its integrity check.');
    } on FileSystemException {
      _message('This attachment could not be opened.');
    }
  }

  /// Hands the decrypted per-session copy to Android through the FileProvider
  /// channel. The sealed blob in `attachments/ab/` is never exposed.
  Future<void> _shareOnAndroid(File file, Attachment attachment) async {
    try {
      await const MethodChannel('locus_planner/share').invokeMethod('share', {
        'path': file.path,
        'mimeType': attachment.mimeType,
      });
    } on MissingPluginException {
      if (mounted) await _showFileDetails(attachment);
    } on PlatformException {
      _message('This file could not be opened.');
    }
  }

  Future<void> _showImage(Attachment attachment, Uint8List bytes) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(
                attachment.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFileDetails(Attachment attachment) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(attachment.displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(attachment.mimeType),
            const SizedBox(height: 6),
            Text(_formatBytes(attachment.sizeBytes)),
            const SizedBox(height: 12),
            const Text(
              'This file is stored encrypted on this device. Open it from a '
              'desktop build, or use the desktop app to export a copy.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _isNew) {
      if (!widget.showHintWhenNew) return const SizedBox.shrink();
      return Text(
        widget.enabled
            ? 'Save this item first, then edit it to add attachments.'
            : 'Attachments are unavailable for this item.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final async = ref.watch(attachmentServiceProvider);
    final content = async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, _) => Row(
        children: [
          const Icon(Icons.lock_outline, size: 18),
          const SizedBox(width: 8),
          const Expanded(child: Text('Attachments are unavailable.')),
          TextButton(
            onPressed: () => ref.invalidate(attachmentServiceProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (service) {
        final stream = widget.todoId != null
            ? service.watchForTodo(widget.todoId!)
            : service.watchForEvent(widget.eventId!);
        return StreamBuilder<List<Attachment>>(
          stream: stream,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <Attachment>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Attachments${items.isEmpty ? '' : ' (${items.length})'}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _busy ? null : () => _pickFiles(service),
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (items.isEmpty)
                  Text(
                    'Up to 20 files, 25 MB each. Stored encrypted on this '
                    'device; metadata syncs with the item.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final attachment in items)
                        FutureBuilder<bool>(
                          key: ValueKey(
                            '${attachment.id}-$_downloadGeneration',
                          ),
                          future: service.hasBlob(attachment.sha256),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const SizedBox(
                                width: 88,
                                height: 88,
                                child: Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (snapshot.data == false) {
                              return _MissingAttachmentTile(
                                attachment: attachment,
                                onDownload: widget.onDownload == null
                                    ? null
                                    : () => _download(attachment),
                                onKeep: widget.onKeep == null
                                    ? null
                                    : () => _keep(attachment),
                              );
                            }
                            return _AttachmentTile(
                              attachment: attachment,
                              thumbnail: attachment.kind == 'image'
                                  ? service.thumbnail(attachment)
                                  : null,
                              onTap: () => _view(service, attachment),
                              onDelete: () => _delete(service, attachment),
                            );
                          },
                        ),
                    ],
                  ),
              ],
            );
          },
        );
      },
    );

    if (!Platform.isWindows || !widget.enabled) return content;
    return DropTarget(
      onDragEntered: (_) {
        if (mounted) setState(() => _dragging = true);
      },
      onDragExited: (_) {
        if (mounted) setState(() => _dragging = false);
      },
      onDragDone: (detail) async {
        if (mounted) setState(() => _dragging = false);
        final service = async.valueOrNull;
        if (service != null) await _importPaths(service, detail.files);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            width: 2,
            color: _dragging
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
        child: content,
      ),
    );
  }
}

/// A tile for metadata that arrived without its bytes. The phone can fetch it
/// from the paired desktop or pin it for later.
class _MissingAttachmentTile extends StatelessWidget {
  const _MissingAttachmentTile({
    required this.attachment,
    required this.onDownload,
    required this.onKeep,
  });

  final Attachment attachment;
  final VoidCallback? onDownload;
  final VoidCallback? onKeep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Attachment ${attachment.displayName}, not downloaded',
      child: Container(
        width: 108,
        height: 88,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              attachment.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onDownload != null)
                  IconButton(
                    tooltip: 'Download',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: onDownload,
                    icon: const Icon(Icons.cloud_download_outlined),
                  ),
                if (onKeep != null)
                  IconButton(
                    tooltip: 'Keep on this device',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: onKeep,
                    icon: const Icon(Icons.push_pin_outlined),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.thumbnail,
    required this.onTap,
    required this.onDelete,
  });

  final Attachment attachment;
  final Future<Uint8List?>? thumbnail;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = attachment.kind == 'image' && thumbnail != null
        ? FutureBuilder<Uint8List?>(
            future: thumbnail,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return const Center(
                  child: Icon(Icons.image_outlined, size: 28),
                );
              }
              return Image.memory(
                bytes,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            },
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.insert_drive_file_outlined, size: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  attachment.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      label:
          'Attachment ${attachment.displayName}, '
          '${_formatBytes(attachment.sizeBytes)}',
      child: Tooltip(
        message:
            '${attachment.displayName}\n${_formatBytes(attachment.sizeBytes)}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: content,
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: IconButton(
                    tooltip: 'Remove attachment',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
