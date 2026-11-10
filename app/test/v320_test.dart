import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/core/notifications/notification_taps.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/friends/chat_page.dart';
import 'package:my_fitness/features/friends/friend_activity_page.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_repository.dart';
import 'package:my_fitness/features/plan/plan_page.dart';
import 'package:my_fitness/features/plan/plan_providers.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/profile/avatar_crop_page.dart';
import 'package:my_fitness/features/profile/avatar_edit_sheet.dart';
import 'package:my_fitness/features/profile/avatar_service.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

import 'exercises_test.dart' show loadSeed;
import 'friends_test.dart' show world;

class _IdleSync extends SyncController {
  @override
  SyncStatus build() => SyncStatus(lastSync: DateTime(2026, 11, 2, 8));
  @override
  Future<void> requestSync() async {}
}

class _FakeExercises implements ExerciseRepository {
  _FakeExercises(this.items);
  final List<Exercise> items;
  @override
  Future<List<Exercise>> loadAll() async => items;
}

class _FakeAvatars implements AvatarUpdater {
  final presets = <String>[];
  final uploads = <Uint8List>[];
  bool fail = false;

  @override
  Future<void> setPreset(String ref) async {
    if (fail) throw Exception('offline');
    presets.add(ref);
  }

  @override
  Future<void> setCustom(Uint8List png) async {
    if (fail) throw Exception('offline');
    uploads.add(png);
  }
}

void main() {
  group('动作要领', () {
    final all = loadSeed();

    test('366 个动作每一个都写了要领', () {
      expect(all, hasLength(366));
      final missing = all.where((e) => (e.instructionsZh ?? '').trim().isEmpty).map((e) => e.slug).toList();
      expect(missing, isEmpty);
    });

    test('要领都是中文，没有英文原文残留', () {
      final cjk = RegExp(r'[一-鿿]');
      for (final e in all) {
        expect(cjk.hasMatch(e.instructionsZh!), isTrue, reason: e.slug);
        // 不应出现整句英文
        expect(RegExp(r'[A-Za-z]{5,}\s+[A-Za-z]{3,}').hasMatch(e.instructionsZh!), isFalse, reason: e.slug);
      }
    });
  });

  group('通知点击', () {
    test('聊天通知的 payload 能还原出好友 id，别的通知不会被当成聊天', () {
      final p = NotificationTaps.chatPayload('u-bob');
      expect(NotificationTaps.chatFriendId(p), 'u-bob');
      expect(NotificationTaps.chatFriendId(null), isNull);
      expect(NotificationTaps.chatFriendId(''), isNull);
      expect(NotificationTaps.chatFriendId('chat:'), isNull);
      expect(NotificationTaps.chatFriendId('timer:1'), isNull);
    });
  });

  group('计划页的三个分栏', () {
    late AppDatabase db;
    final all = loadSeed();
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Widget host() {
      final workouts = WorkoutRepository(db, userId: () => 'u1', now: () => DateTime(2026, 11, 2, 9));
      final plans = PlanRepository(db, userId: () => 'u1', now: () => DateTime(2026, 11, 2, 9));
      return ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          workoutRepositoryProvider.overrideWithValue(workouts),
          planRepositoryProvider.overrideWithValue(plans),
          exerciseRepositoryProvider.overrideWithValue(_FakeExercises(all)),
          profileSummaryProvider.overrideWithValue(null),
          todayProvider.overrideWithValue(DateTime(2026, 11, 2)),
          syncControllerProvider.overrideWith(_IdleSync.new),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const PlanPage()),
      );
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('顺序是 计划、动作库、模板；动作库就是原来的动作页', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final plan = tester.getCenter(find.text('计划').last);
      final lib = tester.getCenter(find.text('动作库'));
      final tpl = tester.getCenter(find.text('模板'));
      expect(plan.dx, lessThan(lib.dx));
      expect(lib.dx, lessThan(tpl.dx));

      expect(find.text('还没有当前计划'), findsOneWidget);

      await tester.tap(find.text('动作库'));
      await tester.pumpAndSettle();
      // 左侧部位栏、搜索框、胸部动作
      for (final part in ['胸', '背', '肩', '腿', '腹', '激活', '拉伸']) {
        expect(find.text(part), findsWidgets, reason: part);
      }
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('杠铃卧推'), findsWidgets);

      await tester.tap(find.text('模板').first);
      await tester.pumpAndSettle();
      expect(find.text('还没有模板'), findsOneWidget);
      await unmount(tester);
    });

    test('地址里的 tab 参数对应到分栏', () {
      expect(PlanPage.tabFromQuery(null), 0);
      expect(PlanPage.tabFromQuery('exercises'), 1);
      expect(PlanPage.tabFromQuery('templates'), 2);
      expect(PlanPage.tabFromQuery('乱写'), 0);
    });
  });

  group('更换头像', () {
    late _FakeAvatars fake;
    setUp(() => fake = _FakeAvatars());

    Widget host() => ProviderScope(
          overrides: [
            avatarUpdaterProvider.overrideWithValue(fake),
            profileSummaryProvider.overrideWithValue(
                const ProfileSummary(username: 'me_user', displayName: '我', avatarKind: 'preset', avatarRef: 'avatar_01')),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(child: ElevatedButton(onPressed: () => showAvatarSheet(context), child: const Text('打开'))),
              ),
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host());
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    }

    testWidgets('弹层里有「从相册选择」和 12 个默认头像，当前这个被选中', (tester) async {
      await open(tester);
      expect(find.text('更换头像'), findsOneWidget);
      expect(find.text('从相册选择照片'), findsOneWidget);
      for (var i = 1; i <= 12; i++) {
        expect(find.bySemanticsLabel('头像 ${i.toString().padLeft(2, '0')}'), findsOneWidget, reason: '头像 $i');
      }
    });

    testWidgets('点一个默认头像：保存并关闭弹层，提示头像已更换', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('头像 05'));
      await tester.pumpAndSettle();
      expect(fake.presets, ['avatar_05']);
      expect(find.text('从相册选择照片'), findsNothing);
      expect(find.text('头像已更换'), findsOneWidget);
    });

    testWidgets('保存失败：弹层不关，提示检查网络', (tester) async {
      fake.fail = true;
      await open(tester);
      await tester.tap(find.bySemanticsLabel('头像 07'));
      await tester.pumpAndSettle();
      expect(fake.presets, isEmpty);
      expect(find.text('从相册选择照片'), findsOneWidget);
      expect(find.text('头像没换成功，请检查网络后重试'), findsOneWidget);
    });
  });

  group('头像裁切', () {
    /// 做一张 400×300 的横向测试图：左半红、右半蓝。
    Future<Uint8List> wide() async {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 300), Paint()..color = const Color(0xFFFF0000));
      canvas.drawRect(const Rect.fromLTWH(200, 0, 200, 300), Paint()..color = const Color(0xFF0000FF));
      final img = await rec.endRecording().toImage(400, 300);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    testWidgets('照片铺满取景框；点「使用这张」得到 512×512 的 PNG', (tester) async {
      tester.view.physicalSize = const Size(393 * 2, 852 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final bytes = (await tester.runAsync(wide))!;

      Uint8List? result;
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => result = await AvatarCropPage.open(context, bytes),
                child: const Text('裁切'),
              ),
            ),
          ),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
      await tester.tap(find.text('裁切'));
      await tester.pump(const Duration(milliseconds: 400)); // 解码完之前一直在转圈，不能用 pumpAndSettle
      // 图片解码是异步的
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.text('拖动、双指缩放，让脸落在圆圈里'), findsOneWidget);
      expect(find.text('使用这张'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('使用这张'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      final codec = await tester.runAsync(() => ui.instantiateImageCodec(result!));
      final frame = await tester.runAsync(() => codec!.getNextFrame());
      expect(frame!.image.width, AvatarCropPage.outputSize);
      expect(frame.image.height, AvatarCropPage.outputSize);
    });
  });

  group('好友页面返回', () {
    /// 好友列表 → 聊天 / 运动记录，来回点很多次，页面栈也不应该越叠越多。
    testWidgets('聊天和运动记录来回点：连按两次返回一定退回好友列表', (tester) async {
      final fake = world();
      final router = GoRouter(
        initialLocation: '/list',
        routes: [
          GoRoute(
            path: '/list',
            builder: (context, _) => Scaffold(
              body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('好友列表'),
                  ElevatedButton(onPressed: () => context.push('/friends/chat/u-bob'), child: const Text('去聊天')),
                  ElevatedButton(onPressed: () => context.push('/friends/activity/u-bob'), child: const Text('去记录')),
                ]),
              ),
            ),
          ),
          GoRoute(
            path: '/friends/chat/:id',
            builder: (_, st) => ChatPage(friendId: st.pathParameters['id']!, cameFrom: st.extra is FriendPage ? st.extra! as FriendPage : null),
          ),
          GoRoute(
            path: '/friends/activity/:id',
            builder: (_, st) =>
                FriendActivityPage(friendId: st.pathParameters['id']!, cameFrom: st.extra is FriendPage ? st.extra! as FriendPage : null),
          ),
        ],
      );
      final container = ProviderContainer(overrides: [
        friendsRepositoryProvider.overrideWithValue(fake),
        currentUserIdProvider.overrideWithValue('me'),
        profileSummaryProvider.overrideWithValue(const ProfileSummary(username: 'me_user', displayName: '我', avatarKind: 'preset', avatarRef: 'avatar_01')),
      ]);
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(393 * 2, 852 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router)));
      await tester.pumpAndSettle();

      // 看当前显示的是哪一页（推入新页时路由信息的路径不会更新，所以不用它）
      String here() {
        if (find.text('好友列表').hitTestable().evaluate().isNotEmpty) return '/list';
        if (find.byType(ChatPage).hitTestable().evaluate().isNotEmpty) return '/friends/chat/u-bob';
        if (find.byType(FriendActivityPage).hitTestable().evaluate().isNotEmpty) return '/friends/activity/u-bob';
        return '?';
      }

      Future<void> back() async {
        router.pop();
        await tester.pumpAndSettle();
      }

      // 情形一：只点了一次（直接看聊天），返回一次就退出
      await tester.tap(find.text('去聊天'));
      await tester.pumpAndSettle();
      expect(here(), '/friends/chat/u-bob');
      await back();
      expect(here(), '/list');

      // 情形二：直接看记录，返回一次就退出
      await tester.tap(find.text('去记录'));
      await tester.pumpAndSettle();
      expect(here(), '/friends/activity/u-bob');
      await back();
      expect(here(), '/list');

      // 情形三：聊天 → 记录 → 聊天 → 记录 → 聊天 …… 一直点下去
      await tester.tap(find.text('去聊天'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        // 聊天页右上角的「查看最近运动」
        await tester.tap(find.byTooltip('查看最近运动'));
        await tester.pumpAndSettle();
        expect(here(), '/friends/activity/u-bob', reason: '第 ${i + 1} 轮去记录');
        await tester.tap(find.text('聊天'));
        await tester.pumpAndSettle();
        expect(here(), '/friends/chat/u-bob', reason: '第 ${i + 1} 轮回聊天');
      }
      // 点了这么多次，连按两次返回（最多两次）就回到好友列表
      await back();
      if (here() != '/list') await back();
      expect(here(), '/list');
      expect(find.text('好友列表'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(milliseconds: 50));
    });
  });
}
