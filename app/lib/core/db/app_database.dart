import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// 所有可同步表共有的列，与 Supabase 里的表结构一一对应。
/// `dirty` 为 true 表示本地有改动还没推到云端（同步引擎在 M6 接入）。
mixin SyncColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class Workouts extends Table with SyncColumns {
  TextColumn get userId => text()();
  TextColumn get name => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// 开始时间的本地日期 yyyy-MM-dd，日历与统计按它归属
  TextColumn get localDate => text()();
  TextColumn get note => text().nullable()();
  TextColumn get sourceTemplateId => text().nullable()();
  TextColumn get planId => text().nullable()();
}

class WorkoutExercises extends Table with SyncColumns {
  TextColumn get userId => text()();
  TextColumn get workoutId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get position => integer()();
  TextColumn get note => text().nullable()();
  IntColumn get restSec => integer().nullable()();
}

class WorkoutSets extends Table with SyncColumns {
  TextColumn get userId => text()();
  TextColumn get workoutExerciseId => text()();
  IntColumn get setIndex => integer()();

  /// normal / warmup / drop / failure
  TextColumn get kind => text().withDefault(const Constant('normal'))();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();
  IntColumn get durationSec => integer().nullable()();
  RealColumn get rpe => real().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

class Templates extends Table with SyncColumns {
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get note => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

class TemplateExercises extends Table with SyncColumns {
  TextColumn get userId => text()();
  TextColumn get templateId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get position => integer()();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get repsMin => integer().nullable()();
  IntColumn get repsMax => integer().nullable()();
  IntColumn get restSec => integer().nullable()();
  TextColumn get note => text().nullable()();
}

/// 计划：N 天一个循环，每天绑定一个模板或休息。
class Plans extends Table with SyncColumns {
  TextColumn get userId => text()();
  TextColumn get name => text()();
  IntColumn get cycleDays => integer()();

  /// 第 1 天对应的本地日期 yyyy-MM-dd
  TextColumn get startDate => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
}

class PlanDays extends Table with SyncColumns {
  TextColumn get userId => text()();
  TextColumn get planId => text()();
  IntColumn get dayIndex => integer()();

  /// 为空表示休息日
  TextColumn get templateId => text().nullable()();
  TextColumn get label => text().nullable()();
}

/// 体重记录：每天最多一条。
class BodyMetrics extends Table with SyncColumns {
  TextColumn get userId => text()();

  /// yyyy-MM-dd
  TextColumn get date => text()();
  RealColumn get weightKg => real().nullable()();
}

/// 同步游标等本机私有的键值，不上传。
class SyncStates extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [
  Workouts,
  WorkoutExercises,
  WorkoutSets,
  Templates,
  TemplateExercises,
  Plans,
  PlanDays,
  BodyMetrics,
  SyncStates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'my_fitness'));

  /// 测试用：传入内存数据库。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
              'CREATE INDEX IF NOT EXISTS workouts_date_idx ON workouts (user_id, local_date)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS workout_exercises_workout_idx ON workout_exercises (workout_id, position)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS workout_exercises_exercise_idx ON workout_exercises (exercise_id)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS workout_sets_we_idx ON workout_sets (workout_exercise_id, set_index)');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(templates);
            await m.createTable(templateExercises);
            await m.createTable(plans);
            await m.createTable(planDays);
          }
          if (from < 3) {
            await m.createTable(bodyMetrics);
          }
          if (from < 4) {
            await m.createTable(syncStates);
          }
        },
      );
}
