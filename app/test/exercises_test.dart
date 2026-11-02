import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart';

List<Exercise> loadSeed() {
  final raw = File('assets/seed/exercises.json').readAsStringSync();
  return (jsonDecode(raw) as List)
      .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
      .toList();
}

class _FakeRepo implements ExerciseRepository {
  _FakeRepo(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}

void main() {
  final all = loadSeed();

  group('动作库数据', () {
    test('235 个精选动作 + 86 个原创补充动作，id/slug/中文名唯一', () {
      expect(all.length, 321);
      expect(all.map((e) => e.id).toSet().length, all.length);
      expect(all.map((e) => e.slug).toSet().length, all.length);
      expect(all.map((e) => e.nameZh).toSet().length, all.length);
      for (final e in all) {
        expect(e.nameZh.trim(), isNotEmpty);
      }
    });

    test('精选动作每个都有两张图；原创补充动作（fc_）没有图，但都有动作要点', () {
      final curated = all.where((e) => !e.slug.startsWith('fc_')).toList();
      final extra = all.where((e) => e.slug.startsWith('fc_')).toList();
      expect(curated.length, 235);
      expect(extra.length, 86);
      for (final e in curated) {
        expect(e.imageCount, 2, reason: e.slug);
        for (var i = 0; i < e.imageCount; i++) {
          expect(File(e.imageAsset(i)).existsSync(), isTrue, reason: e.imageAsset(i));
        }
      }
      for (final e in extra) {
        expect(e.imageCount, 0, reason: e.slug);
        expect(e.instructionsZh?.trim(), isNotEmpty, reason: e.slug);
      }
    });

    test('部位与器械分组都能归类', () {
      for (final e in all.where((e) => !e.slug.startsWith('fc_'))) {
        expect(e.bodyPart, isNot(BodyPart.other), reason: e.nameZh);
      }
      expect(EquipmentGroup.of('e-z curl bar'), EquipmentGroup.barbell);
      expect(EquipmentGroup.of('body only'), EquipmentGroup.bodyweight);
      expect(EquipmentGroup.of(null), EquipmentGroup.other);
    });
  });

  group('筛选与搜索', () {
    test('按部位筛选', () {
      final chest = filterExercises(all, const ExerciseFilter(bodyPart: BodyPart.chest));
      expect(chest, isNotEmpty);
      expect(chest.every((e) => e.bodyPart == BodyPart.chest), isTrue);
    });

    test('器械分组叠加在部位上', () {
      final f = const ExerciseFilter(bodyPart: BodyPart.chest, equipment: EquipmentGroup.dumbbell);
      final r = filterExercises(all, f);
      expect(r.every((e) => e.bodyPart == BodyPart.chest && e.equipmentGroup == EquipmentGroup.dumbbell), isTrue);
    });

    test('搜索跨部位，中英文都能搜', () {
      final zh = filterExercises(all, const ExerciseFilter(query: '卧推'));
      expect(zh.length, greaterThan(5));
      expect(zh.any((e) => e.nameZh == '杠铃卧推'), isTrue);
      final en = filterExercises(all, const ExerciseFilter(query: 'bench press'));
      expect(en, isNotEmpty);
      expect(filterExercises(all, const ExerciseFilter(query: '不存在的动作xyz')), isEmpty);
    });

    test('器械计数只统计有结果的分组', () {
      final counts = equipmentCounts(all, const ExerciseFilter(bodyPart: BodyPart.chest));
      expect(counts[EquipmentGroup.all], filterExercises(all, const ExerciseFilter(bodyPart: BodyPart.chest)).length);
      expect(counts[EquipmentGroup.barbell], greaterThan(0));
    });
  });

  testWidgets('动作库页面：默认显示胸部动作，点部位与搜索会更新列表', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [exerciseRepositoryProvider.overrideWithValue(_FakeRepo(all))],
      child: MaterialApp(theme: AppTheme.light(), home: const ExercisesPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('动作'), findsOneWidget);
    expect(find.textContaining('胸 · '), findsOneWidget);
    expect(find.text('杠铃卧推'), findsWidgets);

    await tester.tap(find.text('腿').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('腿 · '), findsOneWidget);

    await tester.enterText(find.byType(TextField), '深蹲');
    await tester.pumpAndSettle();
    expect(find.textContaining('搜索结果 · '), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('没有找到动作'), findsOneWidget);
  });
}
