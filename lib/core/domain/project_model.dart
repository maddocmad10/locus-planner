import '../db/app_database.dart';

/// Domain-facing representation of a project, independent of Drift's UI API.
class ProjectModel {
  const ProjectModel({
    required this.id,
    required this.name,
    required this.description,
    required this.createdAt,
    required this.targetDate,
    required this.targetProgress,
  });

  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime? targetDate;
  final int targetProgress;

  bool get isCompleted => targetProgress >= 100;

  bool get isOverdue =>
      !isCompleted && targetDate != null && targetDate!.isBefore(DateTime.now());

  ProjectModel copyWith({
    String? id,
    String? name,
    String? description,
    bool clearDescription = false,
    DateTime? createdAt,
    DateTime? targetDate,
    bool clearTargetDate = false,
    int? targetProgress,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: clearDescription ? null : (description ?? this.description),
      createdAt: createdAt ?? this.createdAt,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      targetProgress: targetProgress ?? this.targetProgress,
    );
  }

  factory ProjectModel.fromDrift(Project project) => ProjectModel(
        id: project.id,
        name: project.name,
        description: project.description,
        createdAt: project.createdAt,
        targetDate: project.targetDate,
        targetProgress: project.targetProgress,
      );
}
