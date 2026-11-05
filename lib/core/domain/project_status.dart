/// The fixed project workflow vocabulary.
///
/// Status keys are deliberately closed: every device and every backup agrees
/// on the five canonical keys, while the display name, colour and order are
/// stored per project. Keeping the keys fixed avoids a custom status created
/// offline on one device becoming an unknown column on another.
class ProjectStatusSpec {
  const ProjectStatusSpec({
    required this.key,
    required this.label,
    required this.colorToken,
    required this.position,
    required this.isDone,
  });

  final String key;
  final String label;
  final String colorToken;
  final int position;
  final bool isDone;
}

abstract final class ProjectStatusCatalog {
  static const backlog = ProjectStatusSpec(
    key: 'backlog',
    label: 'Backlog',
    colorToken: 'grey',
    position: 0,
    isDone: false,
  );
  static const todo = ProjectStatusSpec(
    key: 'todo',
    label: 'To do',
    colorToken: 'blue',
    position: 1,
    isDone: false,
  );
  static const inProgress = ProjectStatusSpec(
    key: 'in_progress',
    label: 'In Progress',
    colorToken: 'amber',
    position: 2,
    isDone: false,
  );
  static const waiting = ProjectStatusSpec(
    key: 'waiting',
    label: 'Waiting',
    colorToken: 'purple',
    position: 3,
    isDone: false,
  );
  static const done = ProjectStatusSpec(
    key: 'done',
    label: 'Done',
    colorToken: 'green',
    position: 4,
    isDone: true,
  );

  static const all = <ProjectStatusSpec>[
    backlog,
    todo,
    inProgress,
    waiting,
    done,
  ];

  static final keys = {for (final status in all) status.key};

  /// Bounded theme palette. Arbitrary colour strings from backups or sync are
  /// never passed to the UI.
  static const colorTokens = <String>{
    'grey',
    'blue',
    'amber',
    'purple',
    'green',
    'red',
    'teal',
  };

  static ProjectStatusSpec byKey(String key) {
    for (final status in all) {
      if (status.key == key) return status;
    }
    return todo;
  }

  static bool contains(String? key) => key != null && keys.contains(key);

  static bool isDoneKey(String? key) => byKey(key ?? todo.key).isDone;

  /// Normalises an untrusted key to a known one without inventing a status.
  static String normalize(String? key) => contains(key) ? key! : todo.key;
}
