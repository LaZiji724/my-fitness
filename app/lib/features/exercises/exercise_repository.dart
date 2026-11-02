import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';

/// 动作库数据来源。V1 内置动作随 App 打包，离线可用；
/// 自定义动作与收藏接入本地数据库后，在这里合并。
abstract class ExerciseRepository {
  Future<List<Exercise>> loadAll();
}

class AssetExerciseRepository implements ExerciseRepository {
  const AssetExerciseRepository([this.assetPath = 'assets/seed/exercises.json']);

  final String assetPath;

  @override
  Future<List<Exercise>> loadAll() async {
    final raw = await rootBundle.loadString(assetPath);
    final list = jsonDecode(raw) as List<dynamic>;
    return List.unmodifiable(
      list.map((e) => Exercise.fromJson(e as Map<String, dynamic>)),
    );
  }
}

final exerciseRepositoryProvider =
    Provider<ExerciseRepository>((ref) => const AssetExerciseRepository());

/// 内置动作原始数据（不含用户偏好）。
final baseExercisesProvider = FutureProvider<List<Exercise>>(
  (ref) => ref.watch(exerciseRepositoryProvider).loadAll(),
);

/// 动作库：在内置数据上叠加用户对「按次数 / 按时间」的偏好，全 App 都用这一份。
final exercisesProvider = FutureProvider<List<Exercise>>((ref) async {
  final base = await ref.watch(baseExercisesProvider.future);
  final prefs = ref.watch(exercisePrefsProvider).value ?? const <String, TrackingType>{};
  if (prefs.isEmpty) return base;
  return List.unmodifiable([
    for (final e in base)
      prefs[e.id] == null || prefs[e.id] == e.trackingType ? e : e.withTracking(prefs[e.id]!),
  ]);
});

/// 左侧分栏：按部位 / 激活 / 拉伸。
enum ExerciseTab { part, activation, stretch }

/// 页面筛选条件：左侧分栏（部位或激活 / 拉伸）+ 器械分组 + 区域 + 类型 + 搜索词。
class ExerciseFilter {
  const ExerciseFilter({
    this.tab = ExerciseTab.part,
    this.bodyPart = BodyPart.chest,
    this.equipment = EquipmentGroup.all,
    this.region,
    this.kind,
    this.query = '',
  });

  final ExerciseTab tab;
  final BodyPart bodyPart;
  final EquipmentGroup equipment;

  /// 仅「激活 / 拉伸」分栏使用：身体区域；空 = 全部
  final ExerciseRegion? region;

  /// 仅「激活 / 拉伸」分栏使用：具体类型（激活 / 动态热身，或静态拉伸 / 泡沫轴）；空 = 全部
  final ExerciseKind? kind;
  final String query;

  ExerciseFilter copyWith({
    ExerciseTab? tab,
    BodyPart? bodyPart,
    EquipmentGroup? equipment,
    ExerciseRegion? region,
    bool clearRegion = false,
    ExerciseKind? kind,
    bool clearKind = false,
    String? query,
  }) =>
      ExerciseFilter(
        tab: tab ?? this.tab,
        bodyPart: bodyPart ?? this.bodyPart,
        equipment: equipment ?? this.equipment,
        region: clearRegion ? null : (region ?? this.region),
        kind: clearKind ? null : (kind ?? this.kind),
        query: query ?? this.query,
      );

  bool get isSearching => query.trim().isNotEmpty;

  /// 当前是否在「激活 / 拉伸」分栏（搜索时回到全库）
  bool get isWarmupTab => !isSearching && tab != ExerciseTab.part;
}

class ExerciseFilterNotifier extends Notifier<ExerciseFilter> {
  @override
  ExerciseFilter build() => const ExerciseFilter();

  void setBodyPart(BodyPart part) => state = state.copyWith(
      tab: ExerciseTab.part, bodyPart: part, equipment: EquipmentGroup.all, clearRegion: true, clearKind: true);
  void setTab(ExerciseTab tab) => state = state.copyWith(
      tab: tab, equipment: EquipmentGroup.all, clearRegion: true, clearKind: true);
  void setRegion(ExerciseRegion? region) =>
      state = region == null ? state.copyWith(clearRegion: true) : state.copyWith(region: region);
  void setKind(ExerciseKind? kind) =>
      state = kind == null ? state.copyWith(clearKind: true) : state.copyWith(kind: kind);
  void setEquipment(EquipmentGroup group) =>
      state = state.copyWith(equipment: group);
  void setQuery(String query) => state = state.copyWith(query: query);
  void reset() => state = const ExerciseFilter();
}

final exerciseFilterProvider =
    NotifierProvider<ExerciseFilterNotifier, ExerciseFilter>(
  ExerciseFilterNotifier.new,
);

/// 搜索时跨部位查找（忽略左侧部位），否则按部位筛选；器械分组始终生效。
List<Exercise> filterExercises(List<Exercise> all, ExerciseFilter f) {
  final q = f.query.trim().toLowerCase();
  return all.where((e) {
    if (q.isNotEmpty) {
      final hit = e.nameZh.toLowerCase().contains(q) ||
          (e.nameEn?.toLowerCase().contains(q) ?? false);
      if (!hit) return false;
    } else if (f.tab == ExerciseTab.part) {
      if (e.bodyPart != f.bodyPart) return false;
    } else {
      final inTab = f.tab == ExerciseTab.activation ? e.kind.isActivationTab : e.kind.isStretchTab;
      if (!inTab) return false;
      if (f.kind != null && e.kind != f.kind) return false;
      if (f.region != null && e.region != f.region) return false;
    }
    return f.equipment == EquipmentGroup.all ||
        e.equipmentGroup == f.equipment;
  }).toList();
}

/// 「激活 / 拉伸」分栏里各身体区域各有多少个动作（不受区域筛选影响）。
Map<ExerciseRegion, int> regionCounts(List<Exercise> all, ExerciseFilter f) {
  final base = filterExercises(all, f.copyWith(clearRegion: true, equipment: EquipmentGroup.all));
  final counts = <ExerciseRegion, int>{};
  for (final e in base) {
    if (e.region != null) counts.update(e.region!, (v) => v + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// 当前部位（或搜索结果）下，各器械分组各有多少个动作，用于隐藏没有结果的筛选项。
Map<EquipmentGroup, int> equipmentCounts(List<Exercise> all, ExerciseFilter f) {
  final base = filterExercises(all, f.copyWith(equipment: EquipmentGroup.all));
  final counts = <EquipmentGroup, int>{EquipmentGroup.all: base.length};
  for (final e in base) {
    counts.update(e.equipmentGroup, (v) => v + 1, ifAbsent: () => 1);
  }
  return counts;
}
