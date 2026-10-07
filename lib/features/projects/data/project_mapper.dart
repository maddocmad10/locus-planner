import '../../../core/db/app_database.dart';
import '../../../core/domain/project_model.dart';

/// Converts the persistence-layer project row into the domain model.
ProjectModel projectModelFromDrift(Project project) => ProjectModel(
      id: project.id,
      name: project.name,
      description: project.description,
      createdAt: project.createdAt,
      targetDate: project.targetDate,
      targetProgress: project.targetProgress,
    );
