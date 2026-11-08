// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
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
    this.auto = false,
  });

  final String workoutId;
  final Duration duration;
  final double volume;
  final int setCount;
  final int exerciseCount;

  /// 本次打破的纪录：动作 id → 纪录类型
  final Map<String, Set<PrKind>> prs;

  /// 是不是长时间没有操作、由应用自动结束的
  final bool auto;
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
  Future<Workout> startWorkout({String? name, String? templateId, String? planId, String? programId}) async {
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
      sourceProgramId: Value(programId),
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
    // 分区顺序：热身 → 正式训练 → 放松（同一分区内按加入顺序）
    const order = ['warmup', 'main', 'cooldown'];
    int rank(String s) => order.contains(s) ? order.indexOf(s) : 1;
    final sorted = [...exercises]..sort((a, b) {
        final r = rank(a.section).compareTo(rank(b.section));
        return r != 0 ? r : a.position.compareTo(b.position);
      });
    return WorkoutView(
      w,
      [for (final e in sorted) ExerciseBlock(e, sets.where((s) => s.workoutExerciseId == e.id).toList())],
    );
  }

  /// 训练中给动作换分区（热身 / 正式 / 放松）。
  Future<void> setSection(String workoutExerciseId, String section) async {
    await (_db.update(_db.workoutExercises)..where((e) => e.id.equals(workoutExerciseId))).write(
        WorkoutExercisesCompanion(section: Value(section), updatedAt: Value(_now()), dirty: const Value(true)));
  }

  /// 训练中把动作在「按次数 / 按时间」之间切换后，给还没完成的组补上对应的目标量。
  Future<void> retargetSets(String workoutExerciseId, {required bool timed, int? seconds, int? reps}) async {
    final t = _now();
    final sets = await (_db.select(_db.workoutSets)
          ..where((s) => s.workoutExerciseId.equals(workoutExerciseId) & s.deletedAt.isNull() & s.completed.equals(false)))
        .get();
    for (final s in sets) {
      await (_db.update(_db.workoutSets)..where((x) => x.id.equals(s.id))).write(WorkoutSetsCompanion(
        durationSec: timed ? Value(s.durationSec ?? seconds ?? 30) : const Value.absent(),
        reps: timed ? const Value.absent() : Value(s.reps ?? reps ?? 10),
        updatedAt: Value(t),
        dirty: const Value(true),
      ));
    }
  }

  // ---------------------------------------------------------------- 动作与组

  /// 往训练里加一个动作，默认带 [defaultSets] 组，并预填“上次这个动作”的重量与次数。
  ///
  /// [exactSets] 为 true 时（来自模板）组数以 [defaultSets] 为准，只借用上次的重量；
  /// 没有上次记录时用 [defaultReps] 预填次数。
  /// [warmupSets] 个热身组排在正式组前面；[defaultDurationSec] 给按时间的动作预填每组秒数；
  /// [note] 是这个动作的要点，会显示在训练页。
  /// [tracking] 是该动作当前生效的记录方式（已含用户的次数 / 时间偏好）：按时间的只预填秒数，按次数的只预填次数；
  /// 计划里写的目标与它不一致时，改用 [fallbackReps] / [fallbackSeconds]（动作自带的建议量）。
  /// [section] 是分区：warmup 热身 / main 正式训练 / cooldown 放松。
  Future<String> addExercise(
    String workoutId,
    String exerciseId, {
    int defaultSets = 3,
    bool exactSets = false,
    int? defaultReps,
    int? restSec,
    int warmupSets = 0,
    int? defaultDurationSec,
    double? defaultWeightKg,
    String? note,
    TrackingType? tracking,
    int? fallbackReps,
    int? fallbackSeconds,
    String section = 'main',
    bool explicitDose = false,
  }) async {
    final t = _now();
    final timed = tracking == TrackingType.duration;
    final repsTracked = tracking != null && !timed;
    if (timed) defaultDurationSec ??= fallbackSeconds ?? 30;
    if (repsTracked) defaultReps ??= fallbackReps;
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
            note: Value(note),
            section: Value(section),
          ));
      final n = exactSets || last.isEmpty ? defaultSets + warmupSets : last.length;
      for (var i = 0; i < n; i++) {
        final prev = i < last.length ? last[i] : null;
        // 来自计划的动作：热身组固定排在最前；其余组不继承上次的「热身」类型
        final kind = warmupSets > 0 && exactSets
            ? (i < warmupSets ? 'warmup' : (prev?.kind == 'warmup' ? 'normal' : prev?.kind ?? 'normal'))
            : (prev?.kind ?? 'normal');
        await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
              id: _uuid.v4(),
              createdAt: t,
              updatedAt: t,
              userId: _userId(),
              workoutExerciseId: weId,
              setIndex: i,
              kind: Value(kind),
              // 指定了负重（详情页添加动作 / 模板里设了）就用它；热身组仍沿用上次的重量
              weightKg: Value(kind == 'warmup' ? prev?.weightKg : (defaultWeightKg ?? prev?.weightKg)),
              // 详情页里手动设的次数 / 秒数以设的为准，不再被上次的记录盖掉
              reps: Value(timed ? null : (explicitDose ? (defaultReps ?? prev?.reps) : (prev?.reps ?? defaultReps))),
              durationSec: Value(repsTracked
                  ? null
                  : (explicitDose ? (defaultDurationSec ?? prev?.durationSec) : (prev?.durationSec ?? defaultDurationSec))),
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
  ///
  /// 训练的动作、组分别在 workout_exercises / workout_sets 里，同步时它们是在训练主记录之后才拉回来的，
  /// 所以三张表任何一张变化都要重新读取，否则重新登录后首页会停在「0 kg · 0 组」。
  Stream<List<WorkoutView>> watchCompleted({String? fromDate, String? toDate}) {
    Future<List<WorkoutView>> load() async {
      final rows = await (_db.select(_db.workouts)
            ..where((w) {
              var cond = w.endedAt.isNotNull() & w.deletedAt.isNull() & w.userId.equals(_userId());
              if (fromDate != null) cond = cond & w.localDate.isBiggerOrEqualValue(fromDate);
              if (toDate != null) cond = cond & w.localDate.isSmallerOrEqualValue(toDate);
              return cond;
            })
            ..orderBy([(w) => OrderingTerm.desc(w.startedAt)]))
          .get();
      final views = <WorkoutView>[];
      for (final r in rows) {
        final v = await loadWorkout(r.id);
        if (v != null) views.add(v);
      }
      return views;
    }

    late final StreamController<List<WorkoutView>> controller;
    StreamSubscription<Set<TableUpdate>>? sub;
    var seq = 0;

    Future<void> emit() async {
      final mine = ++seq;
      try {
        final views = await load();
        // 丢弃过期结果：同步时更新很密集，只保留最后一次查询
        if (!controller.isClosed && mine == seq) controller.add(views);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<List<WorkoutView>>(
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

  // ---------------------------------------------------------------- 结束 / 放弃

  /// 结束训练。未完成的组被丢弃；一个组都没完成则整次训练作废并返回 null。
  ///
  /// [endedAt] 用于自动结束：长时间没操作时，把结束时刻记在「最后一次操作」那一刻，
  /// 多出来的空闲时间不计入时长。不传则为现在。
  Future<WorkoutSummary?> finishWorkout(String workoutId, {DateTime? endedAt, bool auto = false}) async {
    final t = _now();
    final view = await loadWorkout(workoutId);
    if (view == null) return null;
    var end = endedAt ?? t;
    if (end.isAfter(t)) end = t;
    if (end.isBefore(view.workout.startedAt)) end = view.workout.startedAt;

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
          WorkoutsCompanion(endedAt: Value(end), updatedAt: Value(t), dirty: const Value(true)));
    });

    final done = (await loadWorkout(workoutId))!;
    return WorkoutSummary(
      workoutId: workoutId,
      duration: end.difference(done.workout.startedAt),
      volume: done.volume,
      setCount: done.setCount,
      exerciseCount: done.exercises.length,
      prs: prs,
      auto: auto,
    );
  }

  /// 同一天内继续一次已经结束的训练：之前的动作、组数全部保留，计时接着走。
  ///
  /// 中间停掉的时间不计入时长：把开始时刻往后挪到「现在 − 已练时长」，
  /// 这样「现在 − 开始时刻」正好等于已练时长，也不需要改云端表结构。
  /// 只有今天开始的训练能继续；已经有进行中的训练时返回 null。
  Future<Workout?> resumeWorkout(String workoutId) async {
    if (await activeWorkout() != null) return null;
    final w = await (_db.select(_db.workouts)
          ..where((t) =>
              t.id.equals(workoutId) &
              t.deletedAt.isNull() &
              t.endedAt.isNotNull() &
              t.userId.equals(_userId())))
        .getSingleOrNull();
    final t = _now();
    if (w == null || w.localDate != dateKey(t)) return null;
    final worked = w.endedAt!.difference(w.startedAt);
    await (_db.update(_db.workouts)..where((x) => x.id.equals(workoutId))).write(WorkoutsCompanion(
      startedAt: Value(t.subtract(worked.isNegative ? Duration.zero : worked)),
      endedAt: const Value(null),
      updatedAt: Value(t),
      dirty: const Value(true),
    ));
    return (_db.select(_db.workouts)..where((x) => x.id.equals(workoutId))).getSingle();
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
