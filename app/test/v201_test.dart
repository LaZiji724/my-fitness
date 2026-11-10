import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/app/router.dart' show templateRoutes;
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/calendar/calendar_page.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart';
import 'package:my_fitness/features/plan/part_colors.dart';
import 'package:my_fitness/features/plan/plan_page.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;

class _IdleSync extends SyncController {
  @override
  SyncStatus build() => SyncStatus(lastSync: DateTime(2026, 11, 2, 8));
  @override
  Future<void> requestSync() async {}
}

class _FakeRepo implements ExerciseRepository {
  _FakeRepo(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}

void main() {
  late AppDatabase db;
  late WorkoutRepository workouts;
  late PlanRepository plans;
  late GoRouter router;
  final all = loadSeed();
  final byId = {for (final e in all) e.id: e};
  final bench = all.firstWhere((e) => e.nameZh.contains('卧推'));
  final squat = all.firstWhere(
      (e) => e.nameZh.contains('深蹲') && e.bodyPart == BodyPart.legs && e.equipmentGroup == EquipmentGroup.barbell);
  final today = DateTime(2026, 11, 2);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db, userId: () => 'u1', now: () => DateTime(2026, 11, 2, 9));
    plans = PlanRepository(db, userId: () => 'u1', now: () => DateTime(2026, 11, 2, 9));
  });
  tearDown(() => db.close());

  Widget host(Widget home, {List<RouteBase> extra = const []}) {
    router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, _) => home),
        ...extra,
        GoRoute(path: '/workout', builder: (_, _) => const Scaffold(body: Text('训练页'))),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workoutRepositoryProvider.overrideWithValue(workouts),
        planRepositoryProvider.overrideWithValue(plans),
        exerciseRepositoryProvider.overrideWithValue(_FakeRepo(all)),
        profileSummaryProvider.overrideWithValue(null),
        todayProvider.overrideWithValue(today),
        syncControllerProvider.overrideWith(_IdleSync.new),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  group('日历标签颜色分配', () {
    test('两个都主练胸的模板也会拿到不同颜色', () async {
      final a = await plans.createTemplate('推日');
      final b = await plans.createTemplate('胸肩日');
      await plans.addTemplateExercise(a, bench.id, exercise: bench);
      await plans.addTemplateExercise(b, bench.id, exercise: bench);
      final views = await plans.listTemplates();
      final parts = templateTagParts(views, byId);
      expect(parts.length, 2);
      expect(parts.values.toSet().length, 2);
      expect(parts[views.first.template.id], BodyPart.chest);
    });

    test('planTags：按计划里第几天出现的顺序、去重、跳过休息日；没有当前计划为空', () async {
      final a = await plans.createTemplate('腿日');
      final b = await plans.createTemplate('推日');
      await plans.addTemplateExercise(a, squat.id, exercise: squat);
      await plans.addTemplateExercise(b, bench.id, exercise: bench);
      final p = await plans.createPlan('三分化', 5, startDate: today);
      await plans.setPlanDay(p, 0, b);
      await plans.setPlanDay(p, 2, a);
      await plans.setPlanDay(p, 3, b);
      final templates = await plans.listTemplates();
      final planViews = await plans.watchPlans().first;
      final tags = planTags(planViews, templates, byId);
      expect(tags.map((t) => t.name), ['推日', '腿日']);
      expect(tags.map((t) => t.part), [BodyPart.chest, BodyPart.legs]);
      expect(planTags(const [], templates, byId), isEmpty);
    });
  });

  testWidgets('日历：图例和每天的标签跟着计划里的模板名走', (tester) async {
    setViewport(tester);
    final t = await plans.createTemplate('推日');
    await plans.addTemplateExercise(t, bench.id, exercise: bench);
    final p = await plans.createPlan('推拉腿', 3, startDate: today);
    await plans.setPlanDay(p, 0, t);

    await tester.pumpWidget(host(const CalendarPage()));
    await tester.pumpAndSettle();
    // 图例是模板名，不再是写死的「胸 / 背 / 腿臀…」
    expect(find.text('推日'), findsOneWidget);
    expect(find.text('腿臀'), findsNothing);
    expect(find.text('启用计划以显示每日训练任务'), findsNothing);

    // 在计划里改模板名，日历立刻跟着变
    await plans.renameTemplate(t, '胸肩日');
    await tester.pumpAndSettle();
    expect(find.text('胸肩日'), findsOneWidget);
    expect(find.text('推日'), findsNothing);
    await unmount(tester);
  });

  testWidgets('日历：没有启用计划时不显示部位图例，改为提示启用计划', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(host(const CalendarPage()));
    await tester.pumpAndSettle();
    expect(find.text('启用计划以显示每日训练任务'), findsOneWidget);
    expect(find.text('腿臀'), findsNothing);
    expect(find.text('胸'), findsNothing);
    await unmount(tester);
  });

  group('模板选动作', () {
    late String tid;

    Widget templateHost() => host(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => context.push('/template/$tid'),
                  child: const Text('进入模板'),
                ),
              ),
            ),
          ),
          extra: templateRoutes,
        );

    ExerciseFilter filterOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(exerciseFilterProvider);

    testWidgets('点动作先看详情，点「添加动作」才加入；继续添加仍停在腿 + 杠铃；退出再进入重置', (tester) async {
      setViewport(tester);
      tid = await plans.createTemplate('腿日');
      await tester.pumpWidget(templateHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('进入模板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加动作'));
      await tester.pumpAndSettle();
      expect(find.text('选择动作'), findsOneWidget);

      await tester.tap(find.text('腿'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Wrap), matching: find.text('杠铃')));
      await tester.pumpAndSettle();
      expect(filterOf(tester).bodyPart, BodyPart.legs);
      expect(filterOf(tester).equipment, EquipmentGroup.barbell);

      // 点动作：进入详情，还没有加入（深蹲可能排在第一屏下面，先滚到看得见）
      await tester.ensureVisible(find.text(squat.nameZh).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(squat.nameZh).first);
      await tester.pumpAndSettle();
      expect(find.text('添加动作'), findsOneWidget);
      expect(find.text('加入设置'), findsOneWidget);
      expect((await plans.listTemplates()).single.exercises, isEmpty);

      // 只从详情返回：仍然没有加入
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('选择动作'), findsOneWidget);
      expect((await plans.listTemplates()).single.exercises, isEmpty);

      // 再点进去，点「添加动作」才加入并回到模板页
      await tester.ensureVisible(find.text(squat.nameZh).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(squat.nameZh).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加动作'));
      await tester.pumpAndSettle();
      final exs = (await plans.listTemplates()).single.exercises;
      expect(exs.single.exerciseId, squat.id);
      expect(find.text('选择动作'), findsNothing);
      expect(find.text(squat.nameZh), findsOneWidget); // 模板页的动作行

      // 继续添加下一个：仍然是腿 + 杠铃
      await tester.tap(find.text('添加动作'));
      await tester.pumpAndSettle();
      expect(find.text('选择动作'), findsOneWidget);
      expect(filterOf(tester).bodyPart, BodyPart.legs);
      expect(filterOf(tester).equipment, EquipmentGroup.barbell);

      // 退出模板编辑，下次进入回到默认
      router.pop();
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('进入模板'));
      await tester.pumpAndSettle();
      expect(filterOf(tester).bodyPart, BodyPart.chest);
      expect(filterOf(tester).equipment, EquipmentGroup.all);
      await unmount(tester);
    });
  });

  testWidgets('模板列表：左滑露出占 30% 宽的红色删除，点它才删除', (tester) async {
    setViewport(tester);
    final a = await plans.createTemplate('推日');
    await plans.createTemplate('拉日');
    await tester.pumpWidget(host(const PlanPage(initialTab: 2)));
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.delete), findsNWidgets(2)); // 在卡片底下，尚未露出
    final card = tester.getRect(find.ancestor(of: find.text('推日'), matching: find.byType(Material)).first);

    await tester.drag(find.text('推日'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    final icon = tester.getCenter(find.byIcon(AppIcons.delete).first);
    // 红色按钮占卡片宽度 30%，图标居中在最右侧 15% 处
    expect(icon.dx, closeTo(card.right - card.width * 0.15, 3));
    expect((await plans.listTemplates()), hasLength(2)); // 滑一下不会删

    await tester.tap(find.byIcon(AppIcons.delete).first);
    await tester.pumpAndSettle();
    final left = await plans.listTemplates();
    expect(left.map((t) => t.template.name), ['拉日']);
    expect(left.any((t) => t.template.id == a), isFalse);
    expect(find.text('推日'), findsNothing);
    await unmount(tester);
  });

  testWidgets('模板列表：左滑后点卡片只是收起，不进入模板，也不删除', (tester) async {
    setViewport(tester);
    await plans.createTemplate('推日');
    await tester.pumpWidget(host(const PlanPage(initialTab: 2)));
    await tester.pumpAndSettle();
    await tester.drag(find.text('推日'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(60, 0) + tester.getTopLeft(find.text('推日')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/start');
    expect(await plans.listTemplates(), hasLength(1));
    await unmount(tester);
  });

  testWidgets('动作库：器械筛选条固定不动；点左侧部位或筛选项后右侧回到顶部', (tester) async {
    setViewport(tester);
    await tester.pumpWidget(host(const ExercisesPage()));
    await tester.pumpAndSettle();

    final chip = find.descendant(of: find.byType(Wrap), matching: find.text('全部')).first;
    final chipTop = tester.getTopLeft(chip);
    final grid = find.byType(CustomScrollView);
    double offset() => tester.state<ScrollableState>(find.descendant(of: grid, matching: find.byType(Scrollable)).first).position.pixels;

    await tester.drag(grid, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(0));
    expect(tester.getTopLeft(chip), chipTop); // 筛选条没有跟着滑走

    // 点器械筛选 → 回到顶部
    await tester.tap(find.descendant(of: find.byType(Wrap), matching: find.text('哑铃')));
    await tester.pumpAndSettle();
    expect(offset(), 0);

    // 再滑下去，点左侧部位 → 回到顶部
    await tester.drag(grid, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(0));
    await tester.tap(find.text('背'));
    await tester.pumpAndSettle();
    expect(offset(), 0);
    await unmount(tester);
  });
}
