// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/library/program.dart';
import 'package:my_fitness/features/plan/plan_math.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

/// 计划库内容来源：随包的 JSON（离线可用）。
abstract class ProgramSource {
  Future<List<Program>> loadAll();
}

class AssetProgramSource implements ProgramSource {
  const AssetProgramSource([this.assetPath = 'assets/seed/programs.json']);
  final String assetPath;

  @override
  Future<List<Program>> loadAll() async {
    final raw = await rootBundle.loadString(assetPath);
    final list = jsonDecode(raw) as List<dynamic>;
    return List.unmodifiable(list.map((e) => Program.fromJson(e as Map<String, dynamic>)));
  }
}

/// 计划库里的用户操作：收藏、加入计划、添加到日历、直接练一节。
class ProgramLibraryRepository {
  ProgramLibraryRepository(
    this._db, {
    required String Function() userId,
    DateTime Function()? now,
  })  : _userId = userId,
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final String Function() _userId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  // ------------------------------------------------------------------ 收藏

  /// 收藏的 id 由「用户 + 计划」决定：多台设备各自收藏同一个计划也只会有一行。
  String favoriteId(String programId) => _uuid.v5(Namespace.url.value, 'my-fitness/favorite-program/${_userId()}/$programId');

  Stream<Set<String>> watchFavoriteIds() {
    final q = _db.select(_db.favoritePrograms)
      ..where((f) => f.deletedAt.isNull() & f.userId.equals(_userId()));
    return q.watch().map((rows) => {for (final r in rows) r.programId});
  }

  Future<void> setFavorite(String programId, bool favorite) async {
    final t = _now();
    final id = favoriteId(programId);
    final existing =
        await (_db.select(_db.favoritePrograms)..where((f) => f.id.equals(id))).getSingleOrNull();
    if (existing == null) {
      if (!favorite) return;
      await _db.into(_db.favoritePrograms).insert(FavoriteProgramsCompanion.insert(
            id: id,
            createdAt: t,
            updatedAt: t,
            userId: _userId(),
            programId: programId,
          ));
    } else {
      await (_db.update(_db.favoritePrograms)..where((f) => f.id.equals(id))).write(
        FavoriteProgramsCompanion(
          deletedAt: Value(favorite ? null : t),
          updatedAt: Value(t),
          dirty: const Value(true),
        ),
      );
    }
  }

  // ------------------------------------------------------------------ 进度

  /// 每个计划已完成的训练节数（不含放弃的）。
  Stream<Map<String, int>> watchCompletedCounts() {
    final w = _db.workouts;
    final count = w.id.count();
    final q = _db.selectOnly(w)
      ..addColumns([w.sourceProgramId, count])
      ..where(w.sourceProgramId.isNotNull() &
          w.endedAt.isNotNull() &
          w.deletedAt.isNull() &
          w.userId.equals(_userId()))
      ..groupBy([w.sourceProgramId]);
    return q.watch().map((rows) => {for (final r in rows) r.read(w.sourceProgramId)!: r.read(count) ?? 0});
  }

  /// 来自计划库的计划：计划库计划 id → 我的计划 id。
  Stream<Map<String, String>> watchJoined() {
    final q = _db.select(_db.plans)
      ..where((p) => p.sourceProgramId.isNotNull() & p.deletedAt.isNull() & p.userId.equals(_userId()))
      ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]);
    return q.watch().map((rows) {
      final out = <String, String>{};
      for (final r in rows) {
        out.putIfAbsent(r.sourceProgramId!, () => r.id);
      }
      return out;
    });
  }

  /// 下一节该练哪个：按一个循环里的课次顺序，根据已完成节数轮转。
  static ProgramSession? nextSession(Program p, int completed) {
    final order = p.weekOrder;
    if (order.isEmpty) return null;
    return order[completed % order.length];
  }

  // ------------------------------------------------------------------ 加入 / 日历

  /// 把计划库里的计划变成「我的计划」：每节课生成一个模板，再生成按周循环的计划。
  /// 已经加入过就直接返回原来的计划，不会重复。
  Future<String> join(Program program, {bool activate = false, DateTime? startFrom}) async {
    final existing = await (_db.select(_db.plans)
          ..where((p) =>
              p.sourceProgramId.equals(program.id) & p.deletedAt.isNull() & p.userId.equals(_userId()))
          ..limit(1))
        .getSingleOrNull();
    final String planId;
    if (existing != null) {
      planId = existing.id;
    } else {
      planId = await _createPlanFrom(program);
    }
    if (activate) {
      await PlanRepository(_db, userId: _userId, now: _now).activatePlan(planId, startFrom: startFrom);
    }
    return planId;
  }

  Future<String> _createPlanFrom(Program program) async {
    final t = _now();
    final planId = _uuid.v4();
    await _db.transaction(() async {
      final templateIds = <String, String>{};
      var order = 0;
      for (final s in program.sessions) {
        final tid = _uuid.v4();
        templateIds[s.key] = tid;
        await _db.into(_db.templates).insert(TemplatesCompanion.insert(
              id: tid,
              createdAt: t,
              updatedAt: t,
              userId: _userId(),
              name: '${program.name}·${s.name}',
              note: Value(s.focus),
              sortOrder: Value(100000 + order++),
            ));
        for (final it in s.items) {
          await _db.into(_db.templateExercises).insert(TemplateExercisesCompanion.insert(
                id: _uuid.v4(),
                createdAt: t,
                updatedAt: t,
                userId: _userId(),
                templateId: tid,
                exerciseId: it.exerciseId,
                position: it.position,
                targetSets: Value(it.sets),
                repsMin: Value(it.repsMin),
                repsMax: Value(it.repsMax),
                restSec: Value(it.restSec),
                note: Value(itemNote(it)),
                warmupSets: Value(it.warmupSets),
                targetDurationSec: Value(it.durationSec),
                section: Value(it.section),
              ));
        }
      }
      final hasActive = await (_db.select(_db.plans)
            ..where((p) => p.isActive.equals(true) & p.deletedAt.isNull() & p.userId.equals(_userId())))
          .get();
      await _db.into(_db.plans).insert(PlansCompanion.insert(
            id: planId,
            createdAt: t,
            updatedAt: t,
            userId: _userId(),
            name: program.name,
            cycleDays: 7,
            startDate: WorkoutRepository.dateKey(mondayOf(t)),
            isActive: Value(hasActive.isEmpty),
            sourceProgramId: Value(program.id),
          ));
      for (var i = 0; i < 7; i++) {
        final key = program.schedule[i];
        await _db.into(_db.planDays).insert(PlanDaysCompanion.insert(
              id: _uuid.v4(),
              createdAt: t,
              updatedAt: t,
              userId: _userId(),
              planId: planId,
              dayIndex: i,
              templateId: Value(key == '.' ? null : templateIds[key]),
              label: Value(key == '.' ? null : program.sessionByKey(key)?.name),
            ));
      }
    });
    return planId;
  }

  /// 动作要点 + 距离目标，写进模板/训练的备注。
  static String? itemNote(ProgramItem it) {
    final parts = [
      if (it.distanceM != null) '目标 ${formatDistance(it.distanceM!)}',
      if (it.note != null && it.note!.trim().isNotEmpty) it.note!.trim(),
    ];
    return parts.isEmpty ? null : parts.join('；');
  }

  // ------------------------------------------------------------------ 直接练一节

  /// 不加入计划，直接按这一节的动作链开始一次训练。已有进行中的训练时返回它（null 表示新建失败不会发生）。
  Future<({Workout workout, bool created})> startSession(
    WorkoutRepository workouts,
    Program program,
    ProgramSession session, {
    Map<String, Exercise>? exercises,
  }) async {
    final existing = await workouts.activeWorkout();
    if (existing != null) return (workout: existing, created: false);
    final w = await workouts.startWorkout(name: '${program.name}·${session.name}', programId: program.id);
    for (final it in session.items) {
      final ex = exercises?[it.exerciseId];
      await workouts.addExercise(
        w.id,
        it.exerciseId,
        tracking: ex?.trackingType,
        fallbackReps: ex?.defaultReps,
        fallbackSeconds: ex?.defaultSeconds,
        section: it.section,
        defaultSets: it.sets,
        exactSets: true,
        defaultReps: it.repsMin,
        restSec: it.restSec,
        warmupSets: it.warmupSets,
        defaultDurationSec: it.durationSec,
        note: itemNote(it),
      );
    }
    return (workout: w, created: true);
  }
}
