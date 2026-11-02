// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/workout/workout_math.dart';

/// 一个动作及其所有组。
class ExerciseBlock {
  const ExerciseBlock(this.exercise, this.sets);
  final WorkoutExercise exercise;
  final List<WorkoutSet> sets;
}

/// 一次训练的完整视图。
class WorkoutView {
  const WorkoutView(this.workout, this.exercises);
  final Workout workout;
  final List<ExerciseBlock> exercises;

  Iterable<SetEntry> get entries => exercises.expand((b) => b.sets).map(
        (s) => SetEntry(
            weightKg: s.weightKg, reps: s.reps, kind: s.kind, completed: s.completed),
      );

  double get volume => volumeOf(entries);
  int get setCount => workingSetCount(entries);
}

/// 训练结束时的总结。
class WorkoutSummary {
  const WorkoutSummary({
    required this.workoutId,
    required this.duration,
    required this.volume,
    required this.setCount,
    required this.exerciseCount,
    required this.prs,
  });

  final String workoutId;
  final Duration duration;
  final double volume;
  final int setCount;
  final int exerciseCount;

  /// 本次打破的纪录：动作 id → 纪录类型
  final Map<String, Set<PrKind>> prs;
}

class WorkoutRepository {
  WorkoutRepository(
    this._db, {
    required String Function() userId,
    DateTime Function()? now,
  })  : _userId = userId,
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final String Function() _userId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  static String dateKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------- 开始 / 恢复

  /// 当前进行中的训练（没有结束时间）。App 被杀掉后重新打开仍能恢复。
  Future<Workout?> activeWorkout() => (_db.select(_db.workouts)
        ..where((w) => w.endedAt.isNull() & w.deletedAt.isNull() & w.userId.equals(_userId()))
        ..orderBy([(w) => OrderingTerm.desc(w.startedAt)])
        ..limit(1))
      .getSingleOrNull();

  /// 开始一次训练；若已有进行中的训练则直接返回它。
  Future<Workout> startWorkout({String? name, String? templateId, String? planId}) async {
    final existing = await activeWorkout();
    if (existing != null) return existing;
    final t = _now();
    final row = WorkoutsCompanion.insert(
      id: _uuid.v4(),
      createdAt: t,
      updatedAt: t,
      userId: _userId(),
      startedAt: t,
      localDate: dateKey(t),
      name: Value(name),
      sourceTemplateId: Value(templateId),
      planId: Value(planId),
    );
    await _db.into(_db.workouts).insert(row);
    return (_db.select(_db.workouts)..where((w) => w.id.equals(row.id.value))).getSingle();
  }

  /// 进行中训练的实时视图：任何相关表变化都会重新推送。
  Stream<WorkoutView?> watchActive() {
    late final StreamController<WorkoutView?> controller;
    StreamSubscription<Set<TableUpdate>>? sub;
    var seq = 0;

    Future<void> emit() async {
      final mine = ++seq;
      try {
        final view = await _loadActive();
        // 丢弃过期结果：更新很密集时，只保留最后一次查询
        if (!controller.isClosed && mine == seq) controller.add(view);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<WorkoutView?>(
      onListen: () {
        emit();
        sub = _db
            .tableUpdates(TableUpdateQuery.onAllTables(
                [_db.workouts, _db.workoutExercises, _db.workoutSets]))
            .listen((_) => emit());
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  Future<WorkoutView?> _loadActive() async {
    final w = await activeWorkout();
    return w == null ? null : loadWorkout(w.id);
  }

  Future<WorkoutView?> loadWorkout(String workoutId) async {
    final w = await (_db.select(_db.workouts)
          ..where((t) => t.id.equals(workoutId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (w == null) return null;
    final exercises = await (_db.select(_db.workoutExercises)
          ..where((t) => t.workoutId.equals(workoutId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final ids = exercises.map((e) => e.id).toList();
    final sets = ids.isEmpty
        ? <WorkoutSet>[]
        : await (_db.select(_db.workoutSets)
              ..where((t) => t.workoutExerciseId.isIn(ids) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.setIndex)]))
            .get();
    return WorkoutView(
      w,
      [for (final e in exercises) ExerciseBlock(e, sets.where((s) => s.workoutExerciseId == e.id).toList())],
    );
  }

  // ---------------------------------------------------------------- 动作与组

  /// 往训练里加一个动作，默认带 [defaultSets] 组，并预填“上次这个动作”的重量与次数。
  ///
  /// [exactSets] 为 true 时（来自模板）组数以 [defaultSets] 为准，只借用上次的重量；
  /// 没有上次记录时用 [defaultReps] 预填次数。
  Future<String> addExercise(
    String workoutId,
    String exerciseId, {
    int defaultSets = 3,
    bool exactSets = false,
    int? defaultReps,
    int? restSec,
  }) async {
    final t = _now();
    final count = await (_db.selectOnly(_db.workoutExercises)
          ..addColumns([_db.workoutExercises.id.count()])
          ..where(_db.workoutExercises.workoutId.equals(workoutId) &
              _db.workoutExercises.deletedAt.isNull()))
        .map((r) => r.read(_db.workoutExercises.id.count()) ?? 0)
        .getSingle();
    final last = await lastPerformance(exerciseId, excludeWorkoutId: workoutId);
    final weId = _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.workoutExercises).insert(WorkoutExercisesCompanion.insert(
            id: weId,
            createdAt: t,
            updatedAt: t,
            userId: _userId(),
            workoutId: workoutId,
            exerciseId: exerciseId,
            position: count,
            restSec: Value(restSec),
          ));
      final n = exactSets || last.isEmpty ? defaultSets : last.length;
      for (var i = 0; i < n; i++) {
        final prev = i < last.length ? last[i] : null;
        await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
              id: _uuid.v4(),
              createdAt: t,
              updatedAt: t,
              userId: _userId(),
              workoutExerciseId: weId,
              setIndex: i,
              kind: Value(prev?.kind ?? 'normal'),
              weightKg: Value(prev?.weightKg),
              reps: Value(prev?.reps ?? defaultReps),
              durationSec: Value(prev?.durationSec),
            ));
      }
    });
    return weId;
  }

  Future<void> removeExercise(String workoutExerciseId) async {
    final t = _now();
    await _db.transaction(() async {
      await (_db.update(_db.workoutSets)
            ..where((s) => s.workoutExerciseId.equals(workoutExerciseId) & s.deletedAt.isNull()))
          .write(WorkoutSetsCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
      await (_db.update(_db.workoutExercises)..where((e) => e.id.equals(workoutExerciseId))).write(
          WorkoutExercisesCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
    });
  }

  /// 加一组，默认复制上一组的重量和次数（热身组不复制类型）。
  Future<String> addSet(String workoutExerciseId) async {
    final sets = await (_db.select(_db.workoutSets)
          ..where((s) => s.workoutExerciseId.equals(workoutExerciseId) & s.deletedAt.isNull())
          ..orderBy([(s) => OrderingTerm.asc(s.setIndex)]))
        .get();
    final prev = sets.isEmpty ? null : sets.last;
    final t = _now();
    final id = _uuid.v4();
    await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
          id: id,
          createdAt: t,
          updatedAt: t,
          userId: _userId(),
          workoutExerciseId: workoutExerciseId,
          setIndex: sets.isEmpty ? 0 : sets.last.setIndex + 1,
          weightKg: Value(prev?.weightKg),
          reps: Value(prev?.reps),
          durationSec: Value(prev?.durationSec),
        ));
    return id;
  }

  Future<void> updateSet(
    String setId, {
    double? weightKg,
    int? reps,
    int? durationSec,
    String? kind,
    bool clearWeight = false,
    bool clearReps = false,
  }) async {
    await (_db.update(_db.workoutSets)..where((s) => s.id.equals(setId))).write(
      WorkoutSetsCompanion(
        weightKg: clearWeight ? const Value(null) : (weightKg == null ? const Value.absent() : Value(weightKg)),
        reps: clearReps ? const Value(null) : (reps == null ? const Value.absent() : Value(reps)),
        durationSec: durationSec == null ? const Value.absent() : Value(durationSec),
        kind: kind == null ? const Value.absent() : Value(kind),
        updatedAt: Value(_now()),
        dirty: const Value(true),
      ),
    );
  }

  /// 勾选/取消完成。完成时记录完成时间。
  Future<void> setCompleted(String setId, bool completed) async {
    final t = _now();
    await (_db.update(_db.workoutSets)..where((s) => s.id.equals(setId))).write(
      WorkoutSetsCompanion(
        completed: Value(completed),
        completedAt: Value(completed ? t : null),
        updatedAt: Value(t),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> removeSet(String setId) async {
    final t = _now();
    await (_db.update(_db.workoutSets)..where((s) => s.id.equals(setId))).write(
        WorkoutSetsCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
  }

  // ---------------------------------------------------------------- 历史

  /// 某个动作的全部已完成组（只看已结束的训练）。
  Future<List<({WorkoutSet set, Workout workout})>> _completedHistory(
    String exerciseId, {
    String? excludeWorkoutId,
  }) async {
    final q = _db.select(_db.workoutSets).join([
      innerJoin(_db.workoutExercises, _db.workoutExercises.id.equalsExp(_db.workoutSets.workoutExerciseId)),
      innerJoin(_db.workouts, _db.workouts.id.equalsExp(_db.workoutExercises.workoutId)),
    ])
      ..where(_db.workoutExercises.exerciseId.equals(exerciseId) &
          _db.workoutSets.completed.equals(true) &
          _db.workoutSets.deletedAt.isNull() &
          _db.workoutExercises.deletedAt.isNull() &
          _db.workouts.deletedAt.isNull() &
          _db.workouts.endedAt.isNotNull() &
          _db.workouts.userId.equals(_userId()) &
          (excludeWorkoutId == null ? const Constant(true) : _db.workouts.id.equals(excludeWorkoutId).not()));
    final rows = await q.get();
    return [
      for (final r in rows) (set: r.readTable(_db.workoutSets), workout: r.readTable(_db.workouts)),
    ];
  }

  /// “上次这个动作”练了什么：最近一次结束的训练里该动作的已完成组，按组序。
  Future<List<WorkoutSet>> lastPerformance(String exerciseId, {String? excludeWorkoutId}) async {
    final all = await _completedHistory(exerciseId, excludeWorkoutId: excludeWorkoutId);
    if (all.isEmpty) return const [];
    final latest = all.map((e) => e.workout).reduce((a, b) => a.startedAt.isAfter(b.startedAt) ? a : b);
    return all.where((e) => e.workout.id == latest.id).map((e) => e.set).toList()
      ..sort((a, b) => a.setIndex.compareTo(b.setIndex));
  }

  /// 该动作的历史最佳（不含 [excludeWorkoutId] 这次训练）。
  Future<ExerciseBest> bestBefore(String exerciseId, {String? excludeWorkoutId}) async {
    final all = await _completedHistory(exerciseId, excludeWorkoutId: excludeWorkoutId);
    return ExerciseBest.of(all.map((e) => SetEntry(
        weightKg: e.set.weightKg, reps: e.set.reps, kind: e.set.kind, completed: true)));
  }

  // ---------------------------------------------------------------- 历史

  /// 已结束的训练（含所有组），按开始时间倒序；[fromDate]/[toDate] 为 yyyy-MM-dd，含两端。
  Stream<List<WorkoutView>> watchCompleted({String? fromDate, String? toDate}) {
    final q = _db.select(_db.workouts)
      ..where((w) {
        var cond = w.endedAt.isNotNull() & w.deletedAt.isNull() & w.userId.equals(_userId());
        if (fromDate != null) cond = cond & w.localDate.isBiggerOrEqualValue(fromDate);
        if (toDate != null) cond = cond & w.localDate.isSmallerOrEqualValue(toDate);
        return cond;
      })
      ..orderBy([(w) => OrderingTerm.desc(w.startedAt)]);
    return q.watch().asyncMap((rows) async {
      final views = <WorkoutView>[];
      for (final r in rows) {
        final v = await loadWorkout(r.id);
        if (v != null) views.add(v);
      }
      return views;
    });
  }

  // ---------------------------------------------------------------- 结束 / 放弃

  /// 结束训练。未完成的组被丢弃；一个组都没完成则整次训练作废并返回 null。
  Future<WorkoutSummary?> finishWorkout(String workoutId) async {
    final t = _now();
    final view = await loadWorkout(workoutId);
    if (view == null) return null;

    // 先算 PR（要在丢弃前、用结束前的历史）
    final prs = <String, Set<PrKind>>{};
    for (final block in view.exercises) {
      final best = await bestBefore(block.exercise.exerciseId, excludeWorkoutId: workoutId);
      for (final s in block.sets) {
        final hit = detectPr(
          best,
          SetEntry(weightKg: s.weightKg, reps: s.reps, kind: s.kind, completed: s.completed),
        );
        if (hit.isNotEmpty) prs.putIfAbsent(block.exercise.exerciseId, () => {}).addAll(hit);
      }
    }

    final hasCompleted = view.exercises.any((b) => b.sets.any((s) => s.completed));
    if (!hasCompleted) {
      await discardWorkout(workoutId);
      return null;
    }

    await _db.transaction(() async {
      for (final b in view.exercises) {
        final keep = b.sets.where((s) => s.completed).toList();
        for (final s in b.sets.where((s) => !s.completed)) {
          await removeSet(s.id);
        }
        if (keep.isEmpty) await removeExercise(b.exercise.id);
      }
      await (_db.update(_db.workouts)..where((w) => w.id.equals(workoutId))).write(
          WorkoutsCompanion(endedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
    });

    final done = (await loadWorkout(workoutId))!;
    return WorkoutSummary(
      workoutId: workoutId,
      duration: t.difference(done.workout.startedAt),
      volume: done.volume,
      setCount: done.setCount,
      exerciseCount: done.exercises.length,
      prs: prs,
    );
  }

  /// 放弃（删除）一次训练。
  Future<void> discardWorkout(String workoutId) async {
    final t = _now();
    final view = await loadWorkout(workoutId);
    await _db.transaction(() async {
      for (final b in view?.exercises ?? const <ExerciseBlock>[]) {
        await removeExercise(b.exercise.id);
      }
      await (_db.update(_db.workouts)..where((w) => w.id.equals(workoutId))).write(
          WorkoutsCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
    });
  }
}
