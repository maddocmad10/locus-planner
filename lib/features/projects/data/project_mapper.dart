import '../../../core/db/app_database.dart';
import '../../../core/domain/project_model.dart';

ProjectModel projectModelFromDrift(Project project) =>
    ProjectModel.fromDrift(project);
