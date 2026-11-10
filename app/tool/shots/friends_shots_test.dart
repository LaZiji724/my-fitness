// 好友功能截图：用假数据把好友相关页面渲染成 PNG（浅色 + 深色），改界面时自查用。
//
// 用法（在 app/ 目录下）：
//   flutter test tool/shots/friends_shots_test.dart --dart-define=SHOTS_OUT=/tmp/friend-shots
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/app/app_shell.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/friends/chat_page.dart';
import 'package:my_fitness/features/friends/friend_activity_page.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_search_page.dart';
import 'package:my_fitness/features/friends/friends_page.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';
import 'package:my_fitness/features/friends/my_qr_page.dart';
import 'package:my_fitness/features/friends/privacy_page.dart';
import 'package:my_fitness/features/friends/scan_page.dart';

import '../../test/support/fake_friends.dart';

const _out = String.fromEnvironment('SHOTS_OUT', defaultValue: 'build/friend-shots');

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

UserCard person(String id, String username, String name, String avatar, [FriendRelation r = FriendRelation.friend]) =>
    UserCard(id: id, username: username, displayName: name, avatarRef: avatar, relation: r);

void main() {
  testWidgets('好友截图', (tester) async {
    await tester.runAsync(_loadFonts);
    debugDisableShadows = false;
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
    addTearDown(tester.view.reset);
    Directory(_out).createSync(recursive: true);

    final now = DateTime.now();
    final bob = person('u-bob', 'bob_fit', '铁牛', 'avatar_05');
    final lin = person('u-lin', 'linlin', '林林', 'avatar_08');
    final kai = person('u-kai', 'kai_squat', 'Kai', 'avatar_02');
    final mei = person('u-mei', 'mei', '小美', 'avatar_11', FriendRelation.incoming);
    final dan = person('u-dan', 'dan_dan', '阿丹', 'avatar_04', FriendRelation.outgoing);
    final eve = person('u-eve', 'eve_run', '小跑', 'avatar_06', FriendRelation.none);
    final eve2 = person('u-eve2', 'runner_eve', 'Eve 的健身日记', 'avatar_09', FriendRelation.none);

    DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));

    final fake = FakeFriendsRepository(
      users: [bob, lin, kai, mei, dan, eve, eve2, person('u-scan', 'scanned', '阿杰', 'avatar_07', FriendRelation.none)],
      entries: [
        FriendEntry(friendshipId: 'f1', user: bob, since: ago(60 * 24 * 12), lastBody: '明天练腿吗 🦵', lastAt: ago(3), unread: 2),
        FriendEntry(friendshipId: 'f2', user: lin, since: ago(60 * 24 * 40), lastBody: '今天的卧推破纪录了！🔥', lastAt: ago(60 * 5), lastFromMe: true),
        FriendEntry(friendshipId: 'f3', user: kai, since: ago(60 * 24 * 3), lastBody: '好的，周六见', lastAt: ago(60 * 30)),
        FriendEntry(friendshipId: 'f4', user: mei, since: ago(20)),
        FriendEntry(friendshipId: 'f5', user: dan, since: ago(60 * 3)),
      ],
      chats: {
        'u-bob': [
          ChatMessage(id: 'a1', senderId: 'u-bob', receiverId: 'me', body: '今天练啥？', createdAt: ago(60 * 26)),
          ChatMessage(id: 'a2', senderId: 'me', receiverId: 'u-bob', body: '胸和三头，刚做完', createdAt: ago(60 * 26 - 2)),
          ChatMessage(id: 'a3', senderId: 'me', receiverId: 'u-bob', body: '卧推 80 做了 8 个 💪', createdAt: ago(60 * 26 - 3)),
          ChatMessage(id: 'a4', senderId: 'u-bob', receiverId: 'me', body: '可以啊，我这周腿日被虐惨了 😭', createdAt: ago(60 * 3)),
          ChatMessage(id: 'a5', senderId: 'me', receiverId: 'u-bob', body: '深蹲别憋气，注意呼吸', createdAt: ago(60 * 3 - 1)),
          ChatMessage(id: 'a6', senderId: 'u-bob', receiverId: 'me', body: '明天练腿吗 🦵', createdAt: ago(4)),
          ChatMessage(id: 'a7', senderId: 'u-bob', receiverId: 'me', body: '一起，我 7 点到', createdAt: ago(3)),
        ],
      },
      privacy: const PrivacySettings(),
      activities: {
        'u-bob': FriendActivity(
          settings: const PrivacySettings(),
          workouts: [
            FriendWorkout(id: 'w1', localDate: '2026-11-09', name: '胸肩', durationMin: 62, setCount: 14, volumeKg: 5420, exercises: const [
              FriendExercise(name: '杠铃卧推', bodyPart: 'chest', sets: [
                FriendSet(kind: 'warmup', weightKg: 40, reps: 10),
                FriendSet(weightKg: 80, reps: 8),
                FriendSet(weightKg: 80, reps: 8),
                FriendSet(weightKg: 85, reps: 6),
              ]),
              FriendExercise(name: '哑铃推肩', bodyPart: 'shoulders', sets: [
                FriendSet(weightKg: 24, reps: 10),
                FriendSet(weightKg: 24, reps: 9),
              ]),
              FriendExercise(name: '侧平举', bodyPart: 'shoulders', sets: [FriendSet(weightKg: 10, reps: 15), FriendSet(weightKg: 10, reps: 14)]),
            ]),
            FriendWorkout(id: 'w2', localDate: '2026-11-07', name: '背部', durationMin: 55, setCount: 12, volumeKg: 6100, exercises: const [
              FriendExercise(name: '引体向上', bodyPart: 'back', sets: [FriendSet(reps: 8), FriendSet(reps: 7), FriendSet(reps: 6)]),
            ]),
            FriendWorkout(id: 'w3', localDate: '2026-11-05', name: '腿部', durationMin: 70, setCount: 16, volumeKg: 9800, exercises: const [
              FriendExercise(name: '杠铃深蹲', bodyPart: 'legs', sets: [FriendSet(weightKg: 100, reps: 5), FriendSet(weightKg: 100, reps: 5)]),
            ]),
          ],
          bodyWeight: [WeightPoint(DateTime(2026, 11, 9), 72.4), WeightPoint(DateTime(2026, 11, 2), 72.9)],
        ),
      },
    );

    var mode = ThemeMode.light;
    final boundary = GlobalKey();
    final notifier = ValueNotifier<ThemeMode>(mode);
    void Function(String)? emitScan;

    final router = GoRouter(
      initialLocation: '/friends',
      routes: [
        GoRoute(path: '/friends/search', builder: (_, _) => const FriendSearchPage()),
        GoRoute(path: '/friends/scan', builder: (_, _) => const ScanPage()),
        GoRoute(path: '/friends/qr', builder: (_, _) => const MyQrPage()),
        GoRoute(path: '/friends/privacy', builder: (_, _) => const PrivacyPage()),
        GoRoute(path: '/friends/chat/:id', builder: (_, s) => ChatPage(friendId: s.pathParameters['id']!)),
        GoRoute(path: '/friends/activity/:id', builder: (_, s) => FriendActivityPage(friendId: s.pathParameters['id']!)),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            for (final p in ['today', 'plan', 'calendar', 'exercises', 'stats'])
              StatefulShellBranch(routes: [GoRoute(path: '/$p', builder: (_, _) => const SizedBox())]),
            StatefulShellBranch(routes: [GoRoute(path: '/friends', builder: (_, _) => const FriendsPage())]),
          ],
        ),
      ],
    );

    final container = ProviderContainer(overrides: [
      friendsRepositoryProvider.overrideWithValue(fake),
      currentUserIdProvider.overrideWithValue('me'),
      profileSummaryProvider.overrideWithValue(const ProfileSummary(
          username: 'hotchicken', displayName: 'Hotchicken', avatarKind: 'preset', avatarRef: 'avatar_03')),
      scannerBuilderProvider.overrideWithValue(({required onCode, required torch, required paused}) {
        emitScan = onCode;
        // 模拟相机画面：一张暗色渐变，看取景框和文案的效果
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3A3A3F), Color(0xFF1A1A1C), Color(0xFF4A3A30)],
            ),
          ),
        );
      }),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: boundary,
        child: ValueListenableBuilder(
          valueListenable: notifier,
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
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      final images = find.byType(Image, skipOffstage: true).evaluate().toList();
      await tester.runAsync(() async {
        for (final e in images) {
          try {
            await precacheImage((e.widget as Image).image, e).timeout(const Duration(seconds: 3));
          } catch (_) {}
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
        final suffix = notifier.value == ThemeMode.dark ? '_dark' : '';
        File('$_out/$name$suffix.png').writeAsBytesSync(data!.buffer.asUint8List());
        print('  已保存 $name$suffix.png');
      });
    }

    Future<void> closeSheet() async {
      Navigator.of(tester.element(find.byType(BottomSheet).first)).pop();
      await settle();
    }

    Future<void> both(String name, Future<void> Function() go, {bool dark = true, bool sheet = false}) async {
      for (final m in [ThemeMode.light, if (dark) ThemeMode.dark]) {
        notifier.value = m;
        await tester.pump();
        await go();
        await snap(name);
        if (sheet) await closeSheet();
      }
      notifier.value = ThemeMode.light;
      await tester.pump();
    }

    Future<void> back() async {
      router.pop();
      await settle();
    }

    // 1 好友列表
    await both('01-friends', () async {});

    // 2 点好友弹出的卡片
    await both('02-friend-sheet', () async {
      await tester.tap(find.text('铁牛'));
      await settle();
    }, sheet: true);

    // 3 右上角添加好友
    await both('03-add-sheet', () async {
      await tester.tap(find.byTooltip('添加好友'));
      await settle();
    }, sheet: true);

    // 4 搜索
    router.push('/friends/search');
    await settle();
    await both('04-search-empty', () async {});
    await tester.enterText(find.byType(TextField), 'eve');
    await tester.pump(const Duration(milliseconds: 500));
    await both('05-search-results', () async {});
    await back();

    // 5 我的二维码
    router.push('/friends/qr');
    await both('06-my-qr', () async {});
    await back();

    // 6 扫一扫
    router.push('/friends/scan');
    await settle();
    await both('07-scan', () async {}, dark: false);
    emitScan!('myfit://friend/${'a' * 32}');
    await settle();
    await both('08-scan-result', () async {}, dark: false);
    await closeSheet();
    await back();

    // 7 聊天
    router.push('/friends/chat/u-bob');
    await settle();
    await both('09-chat', () async {});
    await tester.tap(find.byTooltip('表情'));
    await settle();
    await both('10-chat-emoji', () async {});
    await tester.enterText(find.byType(TextField), '好，7 点见 💪');
    await settle();
    await both('11-chat-typing', () async {}, dark: false);
    await back();

    // 8 好友的运动记录
    router.push('/friends/activity/u-bob');
    await settle();
    await both('12-activity', () async {});
    await tester.tap(find.text('胸肩'));
    await settle();
    await both('13-activity-open', () async {});
    await back();

    // 9 隐私设置
    router.push('/friends/privacy');
    await settle();
    await both('14-privacy', () async {});
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await settle();
    await both('15-privacy-bottom', () async {}, dark: false);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    debugDisableShadows = true;
  }, timeout: const Timeout(Duration(minutes: 5)));
}
