import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

/// 「今天这次训练」对模板里某个动作运动量的临时修改。
///
/// 只存在本机（借用 sync_states 表存 JSON），不会写进模板，也不会改计划，
/// 当天开练时按它开始；换一天自动失效。每一项为空表示「沿用模板」。
class DoseOverride {
  const DoseOverride({
    this.targetSets,
    this.repsMin,
    this.repsMax,
    this.restSec,
    this.warmupSets,
    this.targetDurationSec,
    this.clearDuration = false,
    this.section,
  });

  final int? targetSets;
  final int? repsMin;
  final int? repsMax;
  final int? restSec;
  final int? warmupSets;
  final int? targetDurationSec;

  /// 今天改成「按次数」：去掉模板里的每组时长。
  final bool clearDuration;
  final String? section;

  bool get isEmpty =>
      targetSets == null &&
      repsMin == null &&
      repsMax == null &&
      restSec == null &&
      warmupSets == null &&
      targetDurationSec == null &&
      !clearDuration &&
      section == null;

  /// 在已有修改上再叠一次修改（后改的覆盖先改的）。
  DoseOverride merge(DoseOverride o) => DoseOverride(
        targetSets: o.targetSets ?? targetSets,
        repsMin: o.repsMin ?? repsMin,
        repsMax: o.repsMax ?? repsMax,
        restSec: o.restSec ?? restSec,
        warmupSets: o.warmupSets ?? warmupSets,
        // 改成按时间后不再「去掉时长」；改成按次数则去掉时长
        targetDurationSec: o.clearDuration ? null : (o.targetDurationSec ?? targetDurationSec),
        clearDuration: o.targetDurationSec != null ? false : (o.clearDuration || clearDuration),
        section: o.section ?? section,
      );

  Map<String, dynamic> toJson() => {
        'sets': ?targetSets,
        'repsMin': ?repsMin,
        'repsMax': ?repsMax,
        'rest': ?restSec,
        'warmup': ?warmupSets,
        'duration': ?targetDurationSec,
        if (clearDuration) 'clearDuration': true,
        'section': ?section,
      };

  factory DoseOverride.fromJson(Map<String, dynamic> j) => DoseOverride(
        targetSets: j['sets'] as int?,
        repsMin: j['repsMin'] as int?,
        repsMax: j['repsMax'] as int?,
        restSec: j['rest'] as int?,
        warmupSets: j['warmup'] as int?,
        targetDurationSec: j['duration'] as int?,
        clearDuration: j['clearDuration'] == true,
        section: j['section'] as String?,
      );

  /// 把修改叠到模板动作上，得到「今天实际要练的量」。模板本身不变。
  TemplateExercise applyTo(TemplateExercise e) => e.copyWith(
        targetSets: targetSets?.clamp(1, 50),
        repsMin: repsMin == null ? const Value.absent() : Value(repsMin!.clamp(1, 999)),
        repsMax: repsMax == null ? const Value.absent() : Value(repsMax!.clamp(1, 999)),
        restSec: restSec == null ? const Value.absent() : Value(restSec!.clamp(0, 3600)),
        warmupSets: warmupSets?.clamp(0, 10),
        targetDurationSec: clearDuration
            ? const Value(null)
            : (targetDurationSec == null ? const Value.absent() : Value(targetDurationSec!.clamp(1, 36000))),
        section: section,
      );
}

/// 模板动作 id → 今天的修改。
typedef DoseOverrides = Map<String, DoseOverride>;

/// 把今天的修改叠到模板视图上；没有修改时原样返回。
TemplateView applyDoseOverrides(TemplateView view, DoseOverrides overrides) {
  if (overrides.isEmpty) return view;
  return TemplateView(view.template, [
    for (final e in view.exercises) overrides[e.id]?.applyTo(e) ?? e,
  ]);
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 读写「今天训练」的临时修改。数据只在本机，退出登录时随本机数据一起清掉。
class TodayOverridesRepository {
  TodayOverridesRepository(this._db, {required this.userId});

  final AppDatabase _db;
  final String Function() userId;

  /// 键前缀（含账号），退出登录清理时也用它。
  static String prefixFor(String uid) => 'today_override:$uid:';

  String _key(DateTime date, String templateId) => '${prefixFor(userId())}${_dateKey(date)}:$templateId';

  DoseOverrides _decode(List<QueryRow> rows) {
    if (rows.isEmpty) return const {};
    try {
      final raw = jsonDecode(rows.first.read<String>('value')) as Map<String, dynamic>;
      return {
        for (final e in raw.entries) e.key: DoseOverride.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      return const {};
    }
  }

  Stream<DoseOverrides> watch(DateTime date, String templateId) => _db
      .customSelect('SELECT value FROM sync_states WHERE key = ?',
          variables: [Variable<String>(_key(date, templateId))], readsFrom: {_db.syncStates})
      .watch()
      .map(_decode);

  Future<DoseOverrides> load(DateTime date, String templateId) async => _decode(await _db
      .customSelect('SELECT value FROM sync_states WHERE key = ?',
          variables: [Variable<String>(_key(date, templateId))], readsFrom: {_db.syncStates}).get());

  /// 改今天某个动作的运动量，只写这条本机记录，不碰模板。
  Future<void> save(DateTime date, String templateId, String templateExerciseId, DoseOverride change) async {
    final all = Map<String, DoseOverride>.from(await load(date, templateId));
    final merged = (all[templateExerciseId] ?? const DoseOverride()).merge(change);
    if (merged.isEmpty) {
      all.remove(templateExerciseId);
    } else {
      all[templateExerciseId] = merged;
    }
    await _write(date, templateId, all);
  }

  /// 恢复成模板原来的量。
  Future<void> clear(DateTime date, String templateId) => _write(date, templateId, const {});

  Future<void> _write(DateTime date, String templateId, DoseOverrides all) async {
    final key = _key(date, templateId);
    final uid = userId();
    await _db.transaction(() async {
      // 顺手清掉这个账号以前日子的修改，避免越攒越多
      await _db.customUpdate(
        'DELETE FROM sync_states WHERE key LIKE ? AND key NOT LIKE ?',
        variables: [Variable<String>('${prefixFor(uid)}%'), Variable<String>('${prefixFor(uid)}${_dateKey(date)}:%')],
        updates: {_db.syncStates},
        updateKind: UpdateKind.delete,
      );
      if (all.isEmpty) {
        await _db.customUpdate('DELETE FROM sync_states WHERE key = ?',
            variables: [Variable<String>(key)], updates: {_db.syncStates}, updateKind: UpdateKind.delete);
      } else {
        await _db.customInsert(
          'INSERT OR REPLACE INTO sync_states (key, value) VALUES (?, ?)',
          variables: [
            Variable<String>(key),
            Variable<String>(jsonEncode({for (final e in all.entries) e.key: e.value.toJson()})),
          ],
          updates: {_db.syncStates},
        );
      }
    });
  }
}

final todayOverridesRepositoryProvider = Provider<TodayOverridesRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return TodayOverridesRepository(ref.watch(appDatabaseProvider), userId: () => uid);
});

/// 今天这个模板的临时修改（没有修改时为空）。
final todayDoseOverridesProvider = StreamProvider.family<DoseOverrides, String>((ref, templateId) {
  final today = ref.watch(todayProvider);
  return ref.watch(todayOverridesRepositoryProvider).watch(today, templateId);
});

/// 今天实际要练的计划模板：模板 + 今天的临时修改。休息日或没有计划时为 null。
final todayEffectiveTemplateProvider = Provider<TemplateView?>((ref) {
  final tpl = ref.watch(todayPlanProvider)?.template;
  if (tpl == null) return null;
  final overrides = ref.watch(todayDoseOverridesProvider(tpl.template.id)).value ?? const {};
  return applyDoseOverrides(tpl, overrides);
});

/// 按今天的计划开始训练：量取「模板 + 今天的修改」，模板本身不动。没有今日计划模板时什么都不做。
Future<void> startTodayPlan(WidgetRef ref) async {
  final entry = ref.read(todayPlanProvider);
  final tpl = entry?.template;
  if (entry == null || tpl == null) return;
  final overrides = await ref.read(todayOverridesRepositoryProvider).load(ref.read(todayProvider), tpl.template.id);
  await ref.read(planRepositoryProvider).startFromTemplate(
        ref.read(workoutRepositoryProvider),
        tpl.template.id,
        planId: entry.plan.plan.id,
        exercises: ref.read(exerciseByIdProvider),
        adjust: (v) => applyDoseOverrides(v, overrides),
      );
}
