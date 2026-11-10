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
    test('235 个精选动作 + 86 个计划库补充 + 45 个激活/拉伸新增，id/slug/中文名唯一', () {
      expect(all.length, 366);
      expect(all.map((e) => e.id).toSet().length, all.length);
      expect(all.map((e) => e.slug).toSet().length, all.length);
      expect(all.map((e) => e.nameZh).toSet().length, all.length);
      for (final e in all) {
        expect(e.nameZh.trim(), isNotEmpty);
      }
    });

    test('每个动作都有起止两张图，文件都在；所有动作都有动作要领', () {
      for (final e in all) {
        expect(e.imageCount, 2, reason: e.slug);
        for (var i = 0; i < e.imageCount; i++) {
          expect(File(e.imageAsset(i)).existsSync(), isTrue, reason: e.imageAsset(i));
        }
        // 3.2.0 起，所有动作都写全了动作要领
        expect(e.instructionsZh?.trim().length ?? 0, greaterThanOrEqualTo(8), reason: e.slug);
      }
    });

    test('图片比例：原有 235 个是 1:1，新增 / 补图的是 4:3', () {
      for (final e in all) {
        final old = !e.slug.startsWith('fc_') && !e.slug.startsWith('wu_');
        expect(e.imageRatio, old ? 1.0 : closeTo(4 / 3, 0.001), reason: e.slug);
      }
    });

    test('类型与区域：激活 / 拉伸类都有区域，有默认量；每个动作的默认记录方式合理', () {
      final warm = all.where((e) => e.kind != ExerciseKind.strength && e.kind != ExerciseKind.cardio).toList();
      expect(warm.length, greaterThan(90));
      for (final e in warm) {
        expect(e.region, isNotNull, reason: e.nameZh);
        expect(e.defaultSets, isNotNull, reason: e.nameZh);
      }
      // 拉伸与泡沫轴默认按时间，且有默认秒数
      for (final e in all.where((e) => e.kind.isStretchTab)) {
        expect(e.defaultTrackingType, TrackingType.duration, reason: e.nameZh);
        expect(e.defaultSeconds, greaterThan(0), reason: e.nameZh);
      }
      // 静态保持类默认按时间
      for (final name in ['平板支撑', '侧平板支撑', '靠墙静蹲', '空心撑', '悬垂', '交替打腿']) {
        final hit = all.where((e) => e.nameZh == name);
        expect(hit, isNotEmpty, reason: name);
        for (final e in hit) {
          expect(e.defaultTrackingType, TrackingType.duration, reason: e.nameZh);
        }
      }
      // 每个动作都能在次数和时间之间切换（距离类除外），切换后记录方式变化而默认值不变
      for (final e in all.where((e) => e.canSwitchTracking)) {
        final timed = e.withTracking(TrackingType.duration);
        expect(timed.isTimed, isTrue);
        expect(timed.defaultTrackingType, e.defaultTrackingType);
        expect(e.withTracking(e.repsVariant).isTimed, isFalse);
      }
    });

    test('部位与器械分组都能归类', () {
      for (final e in all.where((e) => !e.slug.startsWith('fc_') && !e.slug.startsWith('wu_'))) {
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
    expect(find.textContaining('胸  '), findsOneWidget);
    expect(find.text('杠铃卧推'), findsWidgets);

    await tester.tap(find.text('腿').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('腿  '), findsOneWidget);

    await tester.enterText(find.byType(TextField), '深蹲');
    await tester.pumpAndSettle();
    expect(find.textContaining('搜索结果  '), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('没有找到动作'), findsOneWidget);
  });
}
