import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/calendar/calendar_math.dart';
import 'package:my_fitness/features/calendar/calendar_page.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/plan/plan_edit_page.dart';
import 'package:my_fitness/features/plan/plan_page.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/plan/template_edit_page.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:my_fitness/features/plan/today_overrides.dart';
import 'package:my_fitness/features/today/today_page.dart';
import 'package:my_fitness/features/today/today_preview_page.dart';
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
  test('monthCells：周一起始，补齐整周', () {
    final cells = monthCells(DateTime(2026, 11));
    expect(cells.length % 7, 0);
    // 2026-11-01 是周日 → 前面 6 个空格
    expect(cells.take(6).every((c) => c == null), isTrue);
    expect(cells[6], DateTime(2026, 11, 1));
    expect(cells.whereType<DateTime>(), hasLength(30));
    final feb = monthCells(DateTime(2026, 2)); // 2026-02-01 周日，28 天
    expect(feb.whereType<DateTime>(), hasLength(28));
    expect(feb.length, 35);
  });

  late AppDatabase db;
  late WorkoutRepository workouts;
  late PlanRepository plans;
  final all = loadSeed();
  final bench = all.firstWhere((e) => e.nameZh.contains('卧推'));
  final today = DateTime(2026, 11, 2);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    workouts = WorkoutRepository(db, userId: () => 'u1', now: () => DateTime(2026, 11, 2, 9));
    plans = PlanRepository(db, userId: () => 'u1', now: () => DateTime(2026, 11, 2, 9));
  });
  tearDown(() => db.close());

  Widget host(Widget home) {
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, _) => home),
        GoRoute(path: '/workout', builder: (_, _) => const Scaffold(body: Text('训练页'))),
        GoRoute(path: '/plan/:id', builder: (_, s) => PlanEditPage(planId: s.pathParameters['id']!)),
        GoRoute(path: '/template/:id', builder: (_, s) => TemplateEditPage(templateId: s.pathParameters['id']!)),
        GoRoute(path: '/today/preview', builder: (_, _) => const TodayPreviewPage()),
        GoRoute(path: '/exercise/:slug', builder: (_, s) => Scaffold(body: Text('动作详情 ${s.pathParameters['slug']}'))),
        GoRoute(path: '/me', builder: (_, _) => const SizedBox()),
        GoRoute(path: '/calendar', builder: (_, _) => const Text('日历页')),
      ],
    );
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        workoutRepositoryProvider.overrideWithValue(workouts),
        planRepositoryProvider.overrideWithValue(plans),
        todayOverridesRepositoryProvider.overrideWithValue(TodayOverridesRepository(db, userId: () => 'u1')),
        exerciseRepositoryProvider.overrideWithValue(_FakeRepo(all)),
        profileSummaryProvider.overrideWithValue(null),
        todayProvider.overrideWithValue(today),
        syncControllerProvider.overrideWith(_IdleSync.new),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  /// 卸载页面并让 drift 关闭流时排的 0 秒定时器跑完，否则测试会报「还有定时器」。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> setViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('计划页：空状态 → 新建模板 → 进入模板编辑', (tester) async {
    await setViewport(tester);
    await tester.pumpWidget(host(const PlanPage()));
    await tester.pumpAndSettle();
    expect(find.text('还没有当前计划'), findsOneWidget);

    await tester.tap(find.text('模板').first);
    await tester.pumpAndSettle();
    expect(find.text('还没有模板'), findsOneWidget);

    await tester.tap(find.text('新建模板'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '推日');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(find.text('推日'), findsWidgets);
    expect(find.text('还没有动作'), findsOneWidget);
    final list = await plans.listTemplates();
    expect(list.single.template.name, '推日');
    await unmount(tester);
  });

  testWidgets('模板编辑：点动作改组数，列表文案同步更新', (tester) async {
    await setViewport(tester);
    final id = await plans.createTemplate('推日');
    await plans.addTemplateExercise(id, bench.id);
    await tester.pumpWidget(host(TemplateEditPage(templateId: id)));
    await tester.pumpAndSettle();
    expect(find.text('3 组 · 8–12 次 · 休息 90 秒'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑 ${bench.nameZh}'));
    await tester.pumpAndSettle();
    expect(find.text('只改今天这次训练，不会改动模板'), findsNothing);
    await tester.tap(find.bySemanticsLabel('组数 增加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('4 组 · 8–12 次 · 休息 90 秒'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('模板页：点动作本体打开动作详情，不再弹出编辑面板', (tester) async {
    await setViewport(tester);
    final id = await plans.createTemplate('推日');
    await plans.addTemplateExercise(id, bench.id);
    await tester.pumpWidget(host(TemplateEditPage(templateId: id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(bench.nameZh));
    await tester.pumpAndSettle();
    expect(find.text('动作详情 ${bench.slug}'), findsOneWidget);
    expect(find.text('完成'), findsNothing);
    await unmount(tester);
  });

  Future<(String, String)> planToday() async {
    final t = await plans.createTemplate('推日');
    await plans.addTemplateExercise(t, bench.id);
    final p = await plans.createPlan('推拉腿', 3, startDate: today);
    await plans.setPlanDay(p, 0, t);
    return (t, p);
  }

  testWidgets('首页：黑卡显示「点击预览」，点卡片其他地方进入预览页，按钮仍直接开练', (tester) async {
    await setViewport(tester);
    await planToday();
    await tester.pumpWidget(host(const TodayPage()));
    await tester.pumpAndSettle();
    expect(find.text('点击预览'), findsOneWidget);

    await tester.tap(find.text('推日'));
    await tester.pumpAndSettle();
    expect(find.text(bench.nameZh), findsOneWidget);
    expect(find.text('3 组 · 8–12 次 · 休息 90 秒'), findsOneWidget);
    expect(find.text('开始训练'), findsOneWidget);
    expect(find.text('训练页'), findsNothing);
    await unmount(tester);

    await tester.pumpWidget(host(const TodayPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始训练'));
    await tester.pumpAndSettle();
    expect(find.text('训练页'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('首页预览：改今天的组数只影响今天这次训练，模板和计划不变', (tester) async {
    await setViewport(tester);
    final (t, _) = await planToday();
    await tester.pumpWidget(host(const TodayPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('推日'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑 ${bench.nameZh}'));
    await tester.pumpAndSettle();
    expect(find.text('只改今天这次训练，不会改动模板'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('组数 增加'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('组间休息 增加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('4 组 · 8–12 次 · 休息 105 秒'), findsOneWidget);

    // 模板里的量一点没变
    final tpl = (await plans.getTemplate(t))!;
    expect(tpl.exercises.single.targetSets, 3);
    expect(tpl.exercises.single.restSec, isNull);

    // 开始训练按今天改过的量
    await tester.tap(find.text('开始训练'));
    await tester.pumpAndSettle();
    expect(find.text('训练页'), findsOneWidget);
    final active = (await workouts.loadWorkout((await workouts.activeWorkout())!.id))!;
    expect(active.exercises.single.sets, hasLength(4));
    expect(active.exercises.single.exercise.restSec, 105);
    // 模板依旧没变
    expect((await plans.getTemplate(t))!.exercises.single.targetSets, 3);
    await unmount(tester);
  });

  testWidgets('首页：改过今天后黑卡组数同步，「恢复为模板原来的量」可还原', (tester) async {
    await setViewport(tester);
    final (t, _) = await planToday();
    await tester.pumpWidget(host(const TodayPage()));
    await tester.pumpAndSettle();
    expect(find.text('1 个动作 · 3 组'), findsOneWidget);

    await tester.tap(find.text('推日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑 ${bench.nameZh}'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('组数 增加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复为模板原来的量'));
    await tester.pumpAndSettle();
    expect(find.text('3 组 · 8–12 次 · 休息 90 秒'), findsOneWidget);
    expect(find.text('恢复为模板原来的量'), findsNothing);
    expect((await plans.getTemplate(t))!.exercises.single.targetSets, 3);
    await unmount(tester);
  });

  testWidgets('用模板开始训练会进入训练页', (tester) async {
    await setViewport(tester);
    final id = await plans.createTemplate('推日');
    await plans.addTemplateExercise(id, bench.id);
    await tester.pumpWidget(host(TemplateEditPage(templateId: id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用这个模板开始训练'));
    await tester.pumpAndSettle();
    expect(find.text('训练页'), findsOneWidget);
    expect((await workouts.activeWorkout())?.sourceTemplateId, id);
    await unmount(tester);
  });

  testWidgets('计划编辑：为某天选模板后显示模板名', (tester) async {
    await setViewport(tester);
    final t = await plans.createTemplate('腿日');
    await plans.addTemplateExercise(t, bench.id);
    final p = await plans.createPlan('三分化', 3);
    await tester.pumpWidget(host(PlanEditPage(planId: p)));
    await tester.pumpAndSettle();
    expect(find.text('休息'), findsNWidgets(3));

    await tester.tap(find.text('第 2 天'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('腿日'));
    await tester.pumpAndSettle();
    expect(find.text('腿日'), findsOneWidget);
    expect(find.text('休息'), findsNWidgets(2));
    expect(find.text('当前计划 · 点击停用'), findsOneWidget); // 第一个计划自动成为当前
    await unmount(tester);
  });

  testWidgets('首页：今日有计划 → 显示模板并按它开始训练', (tester) async {
    await setViewport(tester);
    final t = await plans.createTemplate('推日');
    await plans.addTemplateExercise(t, bench.id);
    final p = await plans.createPlan('推拉腿', 3, startDate: today);
    await plans.setPlanDay(p, 0, t);

    await tester.pumpWidget(host(const TodayPage()));
    await tester.pumpAndSettle();
    expect(find.text('今日计划 · 推拉腿'), findsOneWidget);
    expect(find.text('推日'), findsOneWidget);
    expect(find.text('1 个动作 · 3 组'), findsOneWidget);

    await tester.tap(find.text('开始训练'));
    await tester.pumpAndSettle();
    expect(find.text('训练页'), findsOneWidget);
    final active = (await workouts.loadWorkout((await workouts.activeWorkout())!.id))!;
    expect(active.workout.name, '推日');
    expect(active.workout.planId, p);
    expect(active.exercises.single.sets, hasLength(3));
    await unmount(tester);
  });

  testWidgets('首页：无计划时开始空白训练；有进行中的训练显示继续', (tester) async {
    await setViewport(tester);
    await tester.pumpWidget(host(const TodayPage()));
    await tester.pumpAndSettle();
    expect(find.text('今日训练'), findsOneWidget);
    expect(find.text('还没有训练记录，开始你的第一次吧'), findsOneWidget);
    await tester.tap(find.text('开始训练'));
    await tester.pumpAndSettle();
    expect(find.text('训练页'), findsOneWidget);
    expect(await workouts.activeWorkout(), isNotNull);
    await unmount(tester);
  });

  testWidgets('日历：有训练的日子可点开看明细', (tester) async {
    await setViewport(tester);
    final w = await workouts.startWorkout();
    final we = await workouts.addExercise(w.id, bench.id, defaultSets: 0);
    final s = await workouts.addSet(we);
    await workouts.updateSet(s, weightKg: 80, reps: 5);
    await workouts.setCompleted(s, true);
    await workouts.finishWorkout(w.id);

    await tester.pumpWidget(host(const CalendarPage()));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);
    expect(find.text('1 次 · 400 kg'), findsOneWidget);

    // 选中的就是今天（11/2），明细里有动作名和最佳组
    expect(find.text(bench.nameZh), findsOneWidget);
    expect(find.text('80 kg × 5'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('11月5日'));
    await tester.pumpAndSettle();
    expect(find.text('这天没有训练记录'), findsOneWidget);

    await tester.tap(find.byTooltip('上个月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月'), findsOneWidget);
    expect(find.text('0 次 · 0 kg'), findsOneWidget);
    await unmount(tester);
  });
}
