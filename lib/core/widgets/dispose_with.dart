import 'package:flutter/widgets.dart';

/// Disposes [disposables] (text controllers, focus nodes...) when this widget
/// leaves the tree.
///
/// Dialogs need this instead of `showDialog(...).whenComplete(dispose)`: that
/// future completes the moment the dialog is popped, while its closing animation
/// is still running and its `TextField`s are still attached to the controllers.
/// A widget's `dispose` runs only after its whole subtree has been removed, and
/// children are disposed before their parent, so the controllers outlive every
/// widget that uses them.
class DisposeWith extends StatefulWidget {
  const DisposeWith({
    required this.disposables,
    required this.child,
    super.key,
  });

  final List<ChangeNotifier> disposables;
  final Widget child;

  @override
  State<DisposeWith> createState() => _DisposeWithState();
}

class _DisposeWithState extends State<DisposeWith> {
  @override
  void dispose() {
    for (final disposable in widget.disposables) {
      disposable.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
