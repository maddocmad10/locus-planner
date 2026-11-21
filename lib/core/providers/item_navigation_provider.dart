import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The kind of planner item an external entry point wants to open.
enum ItemKind { task, event }

class ItemTarget {
  const ItemTarget({required this.kind, required this.id});

  final ItemKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ItemTarget && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// One activation. The sequence makes a repeat request for the same item
/// observable, so tapping the same notification twice still opens it twice.
class ItemRequest {
  const ItemRequest({required this.target, required this.sequence});

  final ItemTarget target;
  final int sequence;
}

/// Parses the existing `locus://open?kind=task|event&id=...` link.
///
/// Unknown kinds, missing ids and other hosts return null; the caller keeps
/// its existing fallback behaviour.
ItemTarget? itemTargetFromUri(Uri uri) {
  if (uri.scheme != 'locus' || uri.host != 'open') return null;
  final id = uri.queryParameters['id'];
  if (id == null || id.isEmpty) return null;
  final kind = switch (uri.queryParameters['kind']) {
    'task' || 'todo' => ItemKind.task,
    'event' => ItemKind.event,
    _ => null,
  };
  if (kind == null) return null;
  return ItemTarget(kind: kind, id: id);
}

/// Entry point for cold starts, tray activation, single-instance forwarding
/// and Android notification taps. Nothing is opened until the shell has
/// consumed the request, which lets the app-lock gate defer navigation.
class ItemActivationNotifier extends Notifier<ItemRequest?> {
  int _sequence = 0;

  @override
  ItemRequest? build() => null;

  void activate(ItemTarget target) {
    state = ItemRequest(target: target, sequence: ++_sequence);
  }

  void activateUri(Uri uri) {
    final target = itemTargetFromUri(uri);
    if (target != null) activate(target);
  }
}

final itemActivationProvider =
    NotifierProvider<ItemActivationNotifier, ItemRequest?>(
      ItemActivationNotifier.new,
    );

/// Delivered requests that an always-alive page can act on. The shell only
/// publishes after the lock is open.
class ItemOpenNotifier extends Notifier<ItemRequest?> {
  int _sequence = 0;

  @override
  ItemRequest? build() => null;

  void publish(ItemTarget target) {
    state = ItemRequest(target: target, sequence: ++_sequence);
  }

  void consume(int sequence) {
    if (state?.sequence == sequence) state = null;
  }
}

final itemOpenRequestProvider =
    NotifierProvider<ItemOpenNotifier, ItemRequest?>(ItemOpenNotifier.new);
