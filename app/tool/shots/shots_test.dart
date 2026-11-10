// 界面截图工具：用假数据把每个页面渲染成 PNG，改界面时用来自查。
//
// 用法（在 app/ 目录下）：
//   flutter test tool/shots/shots_test.dart --dart-define=SHOTS_OUT=/tmp/shots
// 只截某几页：再加 --dart-define=SHOTS_ONLY=today,workout
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/app/app_shell.dart';
import 'package:my_fitness/app/router.dart' show templateRoutes;
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/auth/login_page.dart';
import 'package:my_fitness/features/auth/register_page.dart';
import 'package:my_fitness/features/calendar/calendar_page.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_detail_page.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/exercises/exercises_page.dart';
import 'package:my_fitness/features/library/library_page.dart';
import 'package:my_fitness/features/library/library_providers.dart';
import 'package:my_fitness/features/library/library_repository.dart';
import 'package:my_fitness/features/library/program_detail_page.dart';
import 'package:my_fitness/features/library/session_detail_page.dart';
import 'package:my_fitness/features/plan/plan_edit_page.dart';
import 'package:my_fitness/features/plan/plan_page.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/plan/today_overrides.dart';
import 'package:my_fitness/features/profile/profile_page.dart';
import 'package:my_fitness/features/stats/body_repository.dart';
import 'package:my_fitness/features/stats/stats_page.dart';
import 'package:my_fitness/features/stats/stats_providers.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:my_fitness/features/today/today_page.dart';
import 'package:my_fitness/features/today/today_preview_page.dart';
import 'package:my_fitness/features/update/update_models.dart';
import 'package:my_fitness/features/update/update_service.dart';
import 'package:my_fitness/features/update/update_ui.dart';
import 'package:my_fitness/features/workout/workout_math.dart';
import 'package:my_fitness/features/workout/workout_page.dart';
import 'package:my_fitness/features/workout/workout_pick_page.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';
import 'package:my_fitness/features/workout/workout_summary_page.dart';

const _out = String.fromEnvironment('SHOTS_OUT', defaultValue: 'build/shots');
const _only = String.fromEnvironment('SHOTS_ONLY');

class _IdleSync extends SyncController {
  @override
  SyncStatus build() => SyncStatus(lastSync: DateTime.now().subtract(const Duration(minutes: 3)));
  @override
  Future<void> requestSync() async {}
}

class _FakeExercises implements ExerciseRepository {
  _FakeExercises(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}

List<Exercise> _loadSeed() {
  final raw = File('assets/seed/exercises.json').readAsStringSync();
  return (jsonDecode(raw) as List).map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList();
}

Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final f in manifest) {
    final loader = FontLoader(f['family'] as String);
    for (final font in f['fonts'] as List) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

void main() {
  final all = _loadSeed();
  Exercise ex(String name) => all.firstWhere((e) => e.nameZh == name);

  testWidgets('截图', (tester) async {
    await tester.runAsync(_loadFonts);
    debugDisableShadows = false; // 截图里要看到真实的阴影
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var clock = now;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final workouts = WorkoutRepository(db, userId: () => 'u', now: () => clock);
    final plans = PlanRepository(db, userId: () => 'u', now: () => clock);
    final body = BodyRepository(db, userId: () => 'u', now: () => clock);
    final byId = {for (final e in all) e.id: e};

    // ---------------------------------------------------------------- 假数据
    Future<String> template(String name, List<(String, int, int, double?, String)> items) async {
      final id = await plans.createTemplate(name);
      for (final (n, sets, reps, kg, section) in items) {
        final e = ex(n);
        await plans.addTemplateExercise(id, e.id,
            exercise: e,
            dose: section == 'main'
                ? ExerciseDose(section: WorkoutSection.main, timed: false, sets: sets, reps: reps, seconds: 30, weightKg: kg)
                : ExerciseDose(
                    section: WorkoutSection.fromKey(section), timed: e.isTimed, sets: sets, reps: reps, seconds: reps));
      }
      return id;
    }

    final push = await template('推日', [
      ('猫牛式', 2, 30, null, 'warmup'),
      ('杠铃卧推', 4, 8, 70, 'main'),
      ('哑铃上斜卧推', 3, 10, 24, 'main'),
      ('坐姿哑铃推举', 3, 10, 20, 'main'),
      ('哑铃侧平举', 4, 15, 8, 'main'),
      ('绳索三头下压', 3, 12, 25, 'main'),
      ('门框胸部拉伸', 2, 30, null, 'cooldown'),
    ]);
    final pull = await template('拉日', [
      ('引体向上', 4, 8, null, 'main'),
      ('杠铃俯身划船', 4, 8, 60, 'main'),
      ('坐姿绳索划船', 3, 12, 50, 'main'),
      ('面拉', 3, 15, 20, 'main'),
      ('哑铃弯举', 3, 12, 12, 'main'),
    ]);
    final legs = await template('腿日', [
      ('杠铃深蹲', 5, 5, 100, 'main'),
      ('罗马尼亚硬拉', 3, 8, 80, 'main'),
      ('腿举', 3, 12, 160, 'main'),
      ('坐姿腿弯举', 3, 12, 40, 'main'),
      ('站姿提踵', 4, 15, 60, 'main'),
    ]);
    final planId = await plans.createPlan('推拉腿', 7);
    final cycle = [push, pull, legs, null, push, pull, null];
    for (var i = 0; i < 7; i++) {
      await plans.setPlanDay(planId, i, cycle[i]);
    }
    await plans.activatePlan(planId, startFrom: today.subtract(const Duration(days: 28)));
    final other = await plans.createPlan('上下肢四分化', 7);
    await plans.setPlanDay(other, 0, push);
    await plans.setPlanDay(other, 1, legs);

    final skip = {3, 9, 10, 17, 22};
    for (var d = 34; d >= 1; d--) {
      final tid = cycle[(28 - d) % 7 < 0 ? (28 - d) % 7 + 7 : (28 - d) % 7];
      if (tid == null || skip.contains(d)) continue;
      clock = today.subtract(Duration(days: d)).add(const Duration(hours: 18, minutes: 40));
      final w = await plans.startFromTemplate(workouts, tid, planId: planId, exercises: byId);
      final view = (await workouts.loadWorkout(w.id))!;
      for (final b in view.exercises) {
        final e = byId[b.exercise.exerciseId]!;
        for (final s in b.sets) {
          if (e.isTimed) {
            await workouts.updateSet(s.id, durationSec: 30);
          } else {
            final base = s.weightKg;
            await workouts.updateSet(s.id,
                weightKg: base == null ? null : base + ((34 - d) ~/ 7) * 2.5, reps: (s.reps ?? 8) + (d % 3 == 0 ? 1 : 0));
          }
          await workouts.setCompleted(s.id, true);
        }
      }
      clock = clock.add(Duration(minutes: 52 + d % 9));
      await workouts.finishWorkout(w.id);
    }
    for (var d = 30; d >= 0; d -= 2) {
      clock = today.subtract(Duration(days: d)).add(const Duration(hours: 8));
      await body.setWeight(today.subtract(Duration(days: d)), 72.4 - (30 - d) * 0.04 + (d % 4) * 0.15);
    }
    clock = now;

    // ---------------------------------------------------------------- 外壳
    final mode = ValueNotifier(ThemeMode.light);
    final boundary = GlobalKey();
    WorkoutSummary? summary;
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
        GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
        GoRoute(path: '/me', builder: (_, _) => const ProfilePage()),
        GoRoute(path: '/exercise/:slug', builder: (_, s) => ExerciseDetailPage(slug: s.pathParameters['slug']!)),
        GoRoute(path: '/today/preview', builder: (_, _) => const TodayPreviewPage()),
        ...templateRoutes,
        GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
        GoRoute(
          path: '/library/:slug',
          builder: (_, s) => ProgramDetailPage(slug: s.pathParameters['slug']!),
          routes: [
            GoRoute(
              path: ':key',
              builder: (_, s) => SessionDetailPage(slug: s.pathParameters['slug']!, sessionKey: s.pathParameters['key']!),
            ),
          ],
        ),
        GoRoute(path: '/plan/:id', builder: (_, s) => PlanEditPage(planId: s.pathParameters['id']!)),
        GoRoute(path: '/workout', builder: (_, _) => const WorkoutPage()),
        GoRoute(
          path: '/workout/pick',
          builder: (_, _) => const WorkoutPickPage(),
          routes: [
            GoRoute(path: ':slug', builder: (_, s) => WorkoutPickDetailPage(slug: s.pathParameters['slug']!)),
          ],
        ),
        GoRoute(path: '/workout/summary', builder: (_, _) => WorkoutSummaryPage(summary: summary!)),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (_, _) => const TodayPage())]),
            StatefulShellBranch(routes: [GoRoute(path: '/plan', builder: (_, _) => const PlanPage())]),
            StatefulShellBranch(routes: [GoRoute(path: '/calendar', builder: (_, _) => const CalendarPage())]),
            StatefulShellBranch(routes: [GoRoute(path: '/exercises', builder: (_, _) => const ExercisesPage())]),
            StatefulShellBranch(routes: [GoRoute(path: '/stats', builder: (_, _) => const StatsPage())]),
          ],
        ),
      ],
    );

    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      workoutRepositoryProvider.overrideWithValue(workouts),
      planRepositoryProvider.overrideWithValue(plans),
      bodyRepositoryProvider.overrideWithValue(body),
      todayOverridesRepositoryProvider.overrideWithValue(TodayOverridesRepository(db, userId: () => 'u')),
      exercisePrefsRepositoryProvider.overrideWithValue(ExercisePrefsRepository(db, userId: () => 'u')),
      libraryRepositoryProvider.overrideWithValue(ProgramLibraryRepository(db, userId: () => 'u')),
      exerciseRepositoryProvider.overrideWithValue(_FakeExercises(all)),
      profileSummaryProvider.overrideWithValue(const ProfileSummary(
          username: 'hotchicken', displayName: 'Hotchicken', avatarKind: 'preset', avatarRef: 'avatar_03')),
      todayProvider.overrideWithValue(today),
      syncControllerProvider.overrideWith(_IdleSync.new),
      currentVersionProvider.overrideWith((ref) async => '2.8.0'),
    ]);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: boundary,
        child: ValueListenableBuilder(
          valueListenable: mode,
          builder: (_, m, _) => MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: m,
            routerConfig: router,
          ),
        ),
      ),
    ));

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      // 让图片真正解码出来
      final images = find.byType(Image, skipOffstage: true).evaluate().toList();
      await tester.runAsync(() async {
        for (final e in images) {
          final w = e.widget as Image;
          try {
            await precacheImage(w.image, e).timeout(const Duration(seconds: 3));
          } catch (err) {
            print('  图片没等到：${w.image}');
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    Future<void> snap(String name) async {
      await settle();
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        final suffix = mode.value == ThemeMode.dark ? '_dark' : '';
        final f = File('$_out/$name$suffix.png');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    bool want(String name) => _only.isEmpty || _only.split(',').contains(name);

    Future<void> step(String name, Future<void> Function() go, {bool dark = true}) async {
      if (!want(name)) return;
      print('>> $name');
      try {
        mode.value = ThemeMode.light;
        await go();
        await snap(name);
        if (dark) {
          mode.value = ThemeMode.dark;
          await snap(name);
          mode.value = ThemeMode.light;
        }
      } catch (e, st) {
        print('!! $name 失败：$e\n$st');
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> closeOverlay() async {
      final ctx = router.routerDelegate.navigatorKey.currentContext!;
      // 只关弹窗和底部面板，不动页面
      Navigator.of(ctx, rootNavigator: true).popUntil((r) => r is! PopupRoute);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }

    container.read(statsViewProvider.notifier).reset(today);

    // ---------------------------------------------------------------- 逐页
    await step('today', () async {
      router.go('/today');
    });
    await step('today_preview', () async {
      router.push('/today/preview');
    });
    await step('plan', () async {
      router.go('/plan');
    });
    await step('plan_templates', () async {
      router.go('/plan');
      await settle();
      await tester.tap(find.text('模板').first);
    });
    await step('template_edit', () async {
      router.push('/template/$push');
    });
    await step('dose_sheet', () async {
      router.go('/plan');
      router.push('/template/$push');
      await settle();
      await tester.tap(find.byTooltip('编辑 杠铃卧推'));
    }, dark: false);
    if (want('dose_sheet')) await closeOverlay();
    await step('plan_edit', () async {
      router.go('/plan');
      router.push('/plan/$planId');
    });
    await step('calendar', () async {
      router.go('/calendar');
    });
    await step('exercises', () async {
      router.go('/exercises');
    });
    await step('exercise_detail', () async {
      router.go('/exercises');
      router.push('/exercise/${ex('杠铃卧推').slug}');
    });
    await step('exercise_add', () async {
      router.go('/plan');
      router.push('/template/$push/pick/${ex('哑铃飞鸟').slug}');
    });
    await step('stats', () async {
      router.go('/stats');
    });
    await step('stats_2', () async {
      router.go('/stats');
      await settle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -760));
    });
    await step('stats_3', () async {
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    });
    await step('stats_month', () async {
      router.go('/stats');
      await settle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
      await settle();
      await tester.tap(find.text('月').first);
    });
    await step('stats_month_2', () async {
      await tester.drag(find.byType(ListView).first, const Offset(0, -620));
    });
    await step('profile', () async {
      router.go('/today');
      router.push('/me');
    });
    await step('library', () async {
      router.go('/plan');
      router.push('/library');
    });
    final programs = await tester.runAsync(() => const AssetProgramSource().loadAll());
    final program = programs!.firstWhere((p) => p.category == '增肌增重', orElse: () => programs.first);
    await step('program_detail', () async {
      router.go('/plan');
      router.push('/library/${program.slug}');
    });
    await step('session_detail', () async {
      router.go('/plan');
      router.push('/library/${program.slug}/${program.sessions.first.key}');
    });
    await step('login', () async {
      router.go('/login');
    });
    await step('register', () async {
      router.go('/register');
    });

    // 进行中的训练
    final w = await plans.startFromTemplate(workouts, push, planId: planId, exercises: byId);
    {
      final view = (await workouts.loadWorkout(w.id))!;
      var n = 0;
      for (final b in view.exercises.take(2)) {
        for (final s in b.sets) {
          if (n++ >= 4) break;
          final e = byId[b.exercise.exerciseId]!;
          if (e.isTimed) {
            await workouts.updateSet(s.id, durationSec: 30);
          } else {
            await workouts.updateSet(s.id, weightKg: 82.5, reps: 8);
          }
          await workouts.setCompleted(s.id, true);
        }
      }
    }
    await step('today_active', () async {
      router.go('/today');
    }, dark: false);
    await step('workout', () async {
      router.go('/today');
      router.push('/workout');
    });
    await step('workout_rest', () async {
      container.read(restTimerProvider.notifier).start(90);
      await tester.drag(find.byType(ListView).first, const Offset(0, -330));
    });
    await step('number_pad', () async {
      await tester.tap(find.text('70').first);
    }, dark: false);
    if (want('number_pad')) await closeOverlay();
    await step('finish_dialog', () async {
      await tester.tap(find.text('结束'));
    }, dark: false);
    if (want('finish_dialog')) await closeOverlay();
    container.read(restTimerProvider.notifier).skip();
    summary = WorkoutSummary(
      workoutId: w.id,
      duration: const Duration(minutes: 58),
      volume: 12350,
      setCount: 19,
      exerciseCount: 6,
      prs: {
        ex('杠铃卧推').id: {PrKind.weight, PrKind.oneRepMax},
        ex('哑铃侧平举').id: {PrKind.reps},
      },
    );
    await step('summary', () async {
      router.go('/workout/summary');
    });
    await step('update_dialog', () async {
      router.go('/today');
      await settle();
      showUpdateDialog(
        router.routerDelegate.navigatorKey.currentContext!,
        AppUpdate(
          version: '2.9.0',
          notes: '新功能：\n1. 界面全面升级，所有页面换了新的样子。\n2. 训练页顶部固定，用时和进度一直看得到。\n3. 图标换成同一套线条图标。',
          assetUrl: 'https://example.com/a.apk',
          assetName: 'my-fitness-2.9.0.apk',
          assetSize: 91 * 1024 * 1024,
          pageUrl: 'https://example.com',
        ),
        '2.8.0',
      );
    }, dark: false);

    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 20));
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
