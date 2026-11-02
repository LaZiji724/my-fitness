// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

class TemplateView {
  const TemplateView(this.template, this.exercises);
  final Template template;
  final List<TemplateExercise> exercises;
}

class PlanView {
  const PlanView(this.plan, this.days);
  final Plan plan;

  /// 长度恒等于 plan.cycleDays；没有绑定模板的天为 null（休息日）。
  final List<PlanDay?> days;

  PlanDay? dayAt(int index) => index >= 0 && index < days.length ? days[index] : null;
}

/// 模板与计划的本地存取。所有删除都是软删除，方便以后同步。
class PlanRepository {
  PlanRepository(
    this._db, {
    required String Function() userId,
    DateTime Function()? now,
  })  : _userId = userId,
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final String Function() _userId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  // ------------------------------------------------------------------ 模板

  Stream<List<TemplateView>> watchTemplates() {
    final changes = _db.tableUpdates(TableUpdateQuery.onAllTables([_db.templates, _db.templateExercises]));
    return _reloading(changes, () => _loadTemplates());
  }

  Future<List<TemplateView>> _loadTemplates() async {
    final ts = await (_db.select(_db.templates)
          ..where((t) => t.deletedAt.isNull() & t.userId.equals(_userId()))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder), (t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    if (ts.isEmpty) return const [];
    final es = await (_db.select(_db.templateExercises)
          ..where((e) => e.templateId.isIn(ts.map((t) => t.id)) & e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.asc(e.position)]))
        .get();
    return [for (final t in ts) TemplateView(t, es.where((e) => e.templateId == t.id).toList())];
  }

  Stream<TemplateView?> watchTemplate(String id) =>
      watchTemplates().map((all) => all.where((t) => t.template.id == id).firstOrNull);

  Future<List<TemplateView>> listTemplates() => _loadTemplates();

  Future<TemplateView?> getTemplate(String id) async =>
      (await _loadTemplates()).where((t) => t.template.id == id).firstOrNull;

  Future<String> createTemplate(String name) async {
    final t = _now();
    final id = _uuid.v4();
    await _db.into(_db.templates).insert(TemplatesCompanion.insert(
          id: id,
          createdAt: t,
          updatedAt: t,
          userId: _userId(),
          name: name.trim().isEmpty ? '未命名模板' : name.trim(),
        ));
    return id;
  }

  Future<void> renameTemplate(String id, String name) async {
    final t = _now();
    await (_db.update(_db.templates)..where((x) => x.id.equals(id))).write(TemplatesCompanion(
      name: Value(name.trim().isEmpty ? '未命名模板' : name.trim()),
      updatedAt: Value(t),
      dirty: const Value(true),
    ));
  }

  Future<void> deleteTemplate(String id) async {
    final t = _now();
    await _db.transaction(() async {
      await (_db.update(_db.templateExercises)
            ..where((e) => e.templateId.equals(id) & e.deletedAt.isNull()))
          .write(TemplateExercisesCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
      await (_db.update(_db.templates)..where((x) => x.id.equals(id))).write(
          TemplatesCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
      // 计划里引用它的天变成休息日
      await (_db.update(_db.planDays)..where((d) => d.templateId.equals(id) & d.deletedAt.isNull()))
          .write(PlanDaysCompanion(templateId: const Value(null), updatedAt: Value(t), dirty: const Value(true)));
    });
  }

  Future<void> addTemplateExercise(String templateId, String exerciseId) async {
    final t = _now();
    final existing = await (_db.select(_db.templateExercises)
          ..where((e) => e.templateId.equals(templateId) & e.deletedAt.isNull()))
        .get();
    await _db.into(_db.templateExercises).insert(TemplateExercisesCompanion.insert(
          id: _uuid.v4(),
          createdAt: t,
          updatedAt: t,
          userId: _userId(),
          templateId: templateId,
          exerciseId: exerciseId,
          position: existing.length,
          repsMin: const Value(8),
          repsMax: const Value(12),
        ));
    await _touchTemplate(templateId, t);
  }

  Future<void> updateTemplateExercise(
    String id, {
    int? targetSets,
    int? repsMin,
    int? repsMax,
    int? restSec,
  }) async {
    final t = _now();
    await (_db.update(_db.templateExercises)..where((e) => e.id.equals(id))).write(
      TemplateExercisesCompanion(
        targetSets: targetSets == null ? const Value.absent() : Value(targetSets.clamp(1, 50)),
        repsMin: repsMin == null ? const Value.absent() : Value(repsMin.clamp(1, 999)),
        repsMax: repsMax == null ? const Value.absent() : Value(repsMax.clamp(1, 999)),
        restSec: restSec == null ? const Value.absent() : Value(restSec.clamp(0, 3600)),
        updatedAt: Value(t),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> removeTemplateExercise(String id) async {
    final t = _now();
    await (_db.update(_db.templateExercises)..where((e) => e.id.equals(id))).write(
        TemplateExercisesCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
  }

  Future<void> _touchTemplate(String id, DateTime t) =>
      (_db.update(_db.templates)..where((x) => x.id.equals(id)))
          .write(TemplatesCompanion(updatedAt: Value(t), dirty: const Value(true)));

  /// 把一次已完成的训练存成模板：每个动作的组数取完成的正式组数。
  Future<String> templateFromWorkout(WorkoutView view, String name) async {
    final id = await createTemplate(name);
    final t = _now();
    var pos = 0;
    for (final b in view.exercises) {
      final working = b.sets.where((s) => s.completed && s.kind != 'warmup').toList();
      if (working.isEmpty) continue;
      final reps = working.map((s) => s.reps ?? 0).where((r) => r > 0).toList()..sort();
      await _db.into(_db.templateExercises).insert(TemplateExercisesCompanion.insert(
            id: _uuid.v4(),
            createdAt: t,
            updatedAt: t,
            userId: _userId(),
            templateId: id,
            exerciseId: b.exercise.exerciseId,
            position: pos++,
            targetSets: Value(working.length.clamp(1, 50)),
            repsMin: Value(reps.isEmpty ? null : reps.first),
            repsMax: Value(reps.isEmpty ? null : reps.last),
            restSec: Value(b.exercise.restSec),
          ));
    }
    return id;
  }

  /// 按模板开始一次训练：组数与休息时间来自模板，重量借用上次的记录。
  Future<Workout> startFromTemplate(
    WorkoutRepository workouts,
    String templateId, {
    String? planId,
  }) async {
    final tv = await getTemplate(templateId);
    if (tv == null) throw StateError('模板不存在');
    final existing = await workouts.activeWorkout();
    if (existing != null) return existing;
    final w = await workouts.startWorkout(name: tv.template.name, templateId: templateId, planId: planId);
    for (final e in tv.exercises) {
      await workouts.addExercise(
        w.id,
        e.exerciseId,
        defaultSets: e.targetSets,
        exactSets: true,
        defaultReps: e.repsMin,
        restSec: e.restSec,
      );
    }
    return w;
  }

  // ------------------------------------------------------------------ 计划

  Future<List<PlanView>> _loadPlans() async {
    final ps = await (_db.select(_db.plans)
          ..where((p) => p.deletedAt.isNull() & p.userId.equals(_userId()))
          ..orderBy([(p) => OrderingTerm.desc(p.isActive), (p) => OrderingTerm.desc(p.createdAt)]))
        .get();
    if (ps.isEmpty) return const [];
    final ds = await (_db.select(_db.planDays)
          ..where((d) => d.planId.isIn(ps.map((p) => p.id)) & d.deletedAt.isNull()))
        .get();
    return [
      for (final p in ps)
        PlanView(p, [
          for (var i = 0; i < p.cycleDays; i++)
            ds.where((d) => d.planId == p.id && d.dayIndex == i).firstOrNull,
        ]),
    ];
  }

  Stream<List<PlanView>> watchPlans() {
    final changes = _db.tableUpdates(TableUpdateQuery.onAllTables([_db.plans, _db.planDays]));
    return _reloading(changes, _loadPlans);
  }

  Future<PlanView?> getPlan(String id) async =>
      (await _loadPlans()).where((p) => p.plan.id == id).firstOrNull;

  Future<String> createPlan(String name, int cycleDays, {DateTime? startDate}) async {
    final t = _now();
    final id = _uuid.v4();
    final hasActive = (await _loadPlans()).any((p) => p.plan.isActive);
    await _db.into(_db.plans).insert(PlansCompanion.insert(
          id: id,
          createdAt: t,
          updatedAt: t,
          userId: _userId(),
          name: name.trim().isEmpty ? '未命名计划' : name.trim(),
          cycleDays: cycleDays.clamp(1, 28),
          startDate: WorkoutRepository.dateKey(startDate ?? t),
          isActive: Value(!hasActive),
        ));
    return id;
  }

  Future<void> renamePlan(String id, String name) async {
    final t = _now();
    await (_db.update(_db.plans)..where((p) => p.id.equals(id))).write(PlansCompanion(
      name: Value(name.trim().isEmpty ? '未命名计划' : name.trim()),
      updatedAt: Value(t),
      dirty: const Value(true),
    ));
  }

  /// 改循环天数；缩短时超出的天被丢弃。
  Future<void> setCycleDays(String id, int cycleDays) async {
    final t = _now();
    final n = cycleDays.clamp(1, 28);
    await _db.transaction(() async {
      await (_db.update(_db.plans)..where((p) => p.id.equals(id)))
          .write(PlansCompanion(cycleDays: Value(n), updatedAt: Value(t), dirty: const Value(true)));
      await (_db.update(_db.planDays)
            ..where((d) => d.planId.equals(id) & d.dayIndex.isBiggerOrEqualValue(n) & d.deletedAt.isNull()))
          .write(PlanDaysCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
    });
  }

  /// 设置计划第 [dayIndex] 天的模板；[templateId] 为 null 表示休息。
  Future<void> setPlanDay(String planId, int dayIndex, String? templateId) async {
    final t = _now();
    final existing = await (_db.select(_db.planDays)
          ..where((d) => d.planId.equals(planId) & d.dayIndex.equals(dayIndex) & d.deletedAt.isNull()))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.update(_db.planDays)..where((d) => d.id.equals(existing.id))).write(PlanDaysCompanion(
        templateId: Value(templateId),
        updatedAt: Value(t),
        dirty: const Value(true),
      ));
    } else {
      await _db.into(_db.planDays).insert(PlanDaysCompanion.insert(
            id: _uuid.v4(),
            createdAt: t,
            updatedAt: t,
            userId: _userId(),
            planId: planId,
            dayIndex: dayIndex,
            templateId: Value(templateId),
          ));
    }
  }

  /// 设为当前计划，并从今天开始作为第 1 天。同一时刻只有一个当前计划。
  Future<void> activatePlan(String id, {DateTime? startFrom}) async {
    final t = _now();
    await _db.transaction(() async {
      await (_db.update(_db.plans)..where((p) => p.isActive.equals(true) & p.deletedAt.isNull()))
          .write(PlansCompanion(isActive: const Value(false), updatedAt: Value(t), dirty: const Value(true)));
      await (_db.update(_db.plans)..where((p) => p.id.equals(id))).write(PlansCompanion(
        isActive: const Value(true),
        startDate: Value(WorkoutRepository.dateKey(startFrom ?? t)),
        updatedAt: Value(t),
        dirty: const Value(true),
      ));
    });
  }

  Future<void> deactivatePlan(String id) async {
    final t = _now();
    await (_db.update(_db.plans)..where((p) => p.id.equals(id)))
        .write(PlansCompanion(isActive: const Value(false), updatedAt: Value(t), dirty: const Value(true)));
  }

  Future<void> deletePlan(String id) async {
    final t = _now();
    await _db.transaction(() async {
      await (_db.update(_db.planDays)..where((d) => d.planId.equals(id) & d.deletedAt.isNull()))
          .write(PlanDaysCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
      await (_db.update(_db.plans)..where((p) => p.id.equals(id))).write(PlansCompanion(
          isActive: const Value(false), deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
    });
  }

  // ------------------------------------------------------------------ 工具

  /// 先推一次当前数据，之后每次相关表变化都重新加载并推送。
  Stream<T> _reloading<T>(Stream<Set<TableUpdate>> changes, Future<T> Function() load) {
    late final StreamController<T> controller;
    StreamSubscription<Set<TableUpdate>>? sub;
    var seq = 0;

    Future<void> emit() async {
      final mine = ++seq;
      try {
        final v = await load();
        if (!controller.isClosed && mine == seq) controller.add(v);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        sub = changes.listen((_) => emit());
        emit();
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}
