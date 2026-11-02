import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/features/exercises/exercise.dart';

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

final exercisesProvider = FutureProvider<List<Exercise>>(
  (ref) => ref.watch(exerciseRepositoryProvider).loadAll(),
);

/// 页面筛选条件：左侧部位 + 器械分组 + 搜索词。
class ExerciseFilter {
  const ExerciseFilter({
    this.bodyPart = BodyPart.chest,
    this.equipment = EquipmentGroup.all,
    this.query = '',
  });

  final BodyPart bodyPart;
  final EquipmentGroup equipment;
  final String query;

  ExerciseFilter copyWith({
    BodyPart? bodyPart,
    EquipmentGroup? equipment,
    String? query,
  }) =>
      ExerciseFilter(
        bodyPart: bodyPart ?? this.bodyPart,
        equipment: equipment ?? this.equipment,
        query: query ?? this.query,
      );

  bool get isSearching => query.trim().isNotEmpty;
}

class ExerciseFilterNotifier extends Notifier<ExerciseFilter> {
  @override
  ExerciseFilter build() => const ExerciseFilter();

  void setBodyPart(BodyPart part) =>
      state = state.copyWith(bodyPart: part, equipment: EquipmentGroup.all);
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
    } else if (e.bodyPart != f.bodyPart) {
      return false;
    }
    return f.equipment == EquipmentGroup.all ||
        e.equipmentGroup == f.equipment;
  }).toList();
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
