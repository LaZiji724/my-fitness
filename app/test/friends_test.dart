import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/friends/chat_page.dart';
import 'package:my_fitness/features/friends/emoji_panel.dart';
import 'package:my_fitness/features/friends/friend_activity_page.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_search_page.dart';
import 'package:my_fitness/features/friends/friends_page.dart';
import 'package:my_fitness/features/friends/friends_repository.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';
import 'package:my_fitness/features/friends/my_qr_page.dart';
import 'package:my_fitness/features/friends/privacy_page.dart';
import 'package:my_fitness/features/workout/workout_providers.dart' show clockProvider;
import 'package:my_fitness/features/friends/scan_page.dart';

import 'support/fake_friends.dart';

UserCard user(String id, String username, String name, {FriendRelation r = FriendRelation.none}) =>
    UserCard(id: id, username: username, displayName: name, relation: r);

FakeFriendsRepository world() {
  final bob = user('u-bob', 'bob_fit', '铁牛', r: FriendRelation.friend);
  final carol = user('u-carol', 'carol', '小C', r: FriendRelation.incoming);
  final dan = user('u-dan', 'dan', '阿丹', r: FriendRelation.outgoing);
  final now = DateTime.now();
  return FakeFriendsRepository(
    users: [
      bob,
      carol,
      dan,
      user('u-eve', 'eve_run', '小跑'),
      user('u-scan', 'scanned', '被扫的人'),
      user('me', 'me_user', '我'),
    ],
    entries: [
      FriendEntry(
        friendshipId: 'f-bob',
        user: bob,
        since: now.subtract(const Duration(days: 12)),
        lastBody: '明天练腿吗',
        lastAt: now.subtract(const Duration(minutes: 3)),
        unread: 2,
      ),
      FriendEntry(friendshipId: 'f-carol', user: carol, since: now),
      FriendEntry(friendshipId: 'f-dan', user: dan, since: now),
    ],
    chats: {
      'u-bob': [
        ChatMessage(id: 'm1', senderId: 'u-bob', receiverId: 'me', body: '今天练了吗', createdAt: now.subtract(const Duration(hours: 2))),
        ChatMessage(id: 'm2', senderId: 'me', receiverId: 'u-bob', body: '练了，胸', createdAt: now.subtract(const Duration(hours: 1, minutes: 58))),
        ChatMessage(id: 'm3', senderId: 'u-bob', receiverId: 'me', body: '明天练腿吗', createdAt: now.subtract(const Duration(minutes: 3))),
      ],
    },
    activities: {
      'u-bob': FriendActivity(
        settings: const PrivacySettings(),
        workouts: [
          FriendWorkout(
            id: 'w1',
            localDate: '2026-11-08',
            name: '胸肩',
            durationMin: 62,
            setCount: 12,
            volumeKg: 5400,
            exercises: const [
              FriendExercise(name: '杠铃卧推', bodyPart: 'chest', sets: [
                FriendSet(kind: 'warmup', weightKg: 40, reps: 10),
                FriendSet(weightKg: 80, reps: 8),
              ]),
            ],
          ),
        ],
      ),
    },
  );
}

ProviderContainer? _mounted;

Future<ProviderContainer> mount(
  WidgetTester tester,
  FakeFriendsRepository fake,
  Widget page, {
  List<Override> overrides = const [],
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => page),
      for (final p in ['/friends/search', '/friends/scan', '/friends/qr', '/friends/privacy', '/friends/chat/:id', '/friends/activity/:id'])
        GoRoute(path: p, builder: (_, state) => Scaffold(body: Center(child: Text('去了 ${state.uri.path}')))),
    ],
  );
  final container = ProviderContainer(overrides: [
    friendsRepositoryProvider.overrideWithValue(fake),
    currentUserIdProvider.overrideWithValue('me'),
    profileSummaryProvider.overrideWithValue(const ProfileSummary(username: 'me_user', displayName: '我', avatarKind: 'preset', avatarRef: 'avatar_01')),
    ...overrides,
  ]);
  _mounted = container;
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(393 * 2, 852 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
  ));
  return container;
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  _mounted?.dispose(); // 好友总管里有定时器，要在测试结束前停掉
  _mounted = null;
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('二维码内容', () {
    test('只认本应用的 32 位随机码', () {
      final code = 'a1b2c3d4' * 4;
      expect(FriendCode.parse('myfit://friend/$code'), code);
      expect(FriendCode.parse(' myfit://friend/$code \n'), code);
      expect(FriendCode.parse('https://example.com'), isNull);
      expect(FriendCode.parse('myfit://friend/short'), isNull);
      expect(FriendCode.parse('myfit://friend/${code.toUpperCase()}'), isNull);
      expect(FriendCode.parse(null), isNull);
      expect(FriendCode(code: code, expiresAt: DateTime.now()).payload, 'myfit://friend/$code');
    });
  });

  group('隐私默认值', () {
    test('训练相关默认公开，体重默认不公开', () {
      const d = PrivacySettings.defaults;
      expect(d.showWorkouts && d.showDuration && d.showExercises && d.showVolume, isTrue);
      expect(d.showBodyWeight, isFalse);
      expect(d.historyDays, 30);
    });

    test('和云端字段互相转换', () {
      const s = PrivacySettings(historyDays: 0, showVolume: false, showBodyWeight: true);
      expect(PrivacySettings.fromJson(s.toJson()), s);
      expect(PrivacySettings.fromJson(const {}), PrivacySettings.defaults);
    });
  });

  group('表情输入', () {
    test('插在光标处，光标跟到表情后面', () {
      final c = TextEditingController(text: '练腿');
      c.selection = const TextSelection.collapsed(offset: 1);
      insertEmoji(c, '💪');
      expect(c.text, '练💪腿');
      expect(c.selection.baseOffset, 1 + '💪'.length);
    });

    test('没有光标时加在末尾；删除按一个完整表情算', () {
      final c = TextEditingController(text: '好');
      insertEmoji(c, '🏋️');
      insertEmoji(c, '🔥');
      expect(c.text, '好🏋️🔥');
      deleteBackward(c);
      expect(c.text, '好🏋️');
      deleteBackward(c);
      expect(c.text, '好');
      deleteBackward(c);
      deleteBackward(c);
      expect(c.text, '');
    });
  });

  testWidgets('好友页：申请、好友、等待通过分开显示；通过申请后移到好友里', (tester) async {
    final fake = world();
    final container = await mount(tester, fake, const FriendsPage());
    await tester.pumpAndSettle();

    expect(find.text('新的朋友'), findsOneWidget);
    expect(find.text('我的好友'), findsOneWidget);
    expect(find.text('等待对方通过'), findsOneWidget);
    expect(find.text('隐私设置'), findsOneWidget); // 醒目的设置按钮
    expect(find.text('明天练腿吗'), findsOneWidget);
    expect(container.read(friendsControllerProvider).badge, 3); // 2 条未读 + 1 个申请

    await tester.tap(find.text('通过'));
    await tester.pumpAndSettle();
    expect(find.text('新的朋友'), findsNothing);
    expect(container.read(friendsControllerProvider).friends.length, 2);
    await unmount(tester);
  });

  testWidgets('点好友出现两个按钮：聊天 和 最近运动', (tester) async {
    final fake = world();
    await mount(tester, fake, const FriendsPage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('铁牛'));
    await tester.pumpAndSettle();
    expect(find.text('聊天'), findsOneWidget);
    expect(find.text('最近运动'), findsOneWidget);

    await tester.tap(find.text('最近运动'));
    await tester.pumpAndSettle();
    expect(find.text('去了 /friends/activity/u-bob'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('右上角添加好友：可选搜索、扫一扫、我的二维码', (tester) async {
    await mount(tester, world(), const FriendsPage());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('添加好友'));
    await tester.pumpAndSettle();
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('扫一扫'), findsOneWidget);
    expect(find.text('我的二维码'), findsOneWidget);
    await tester.tap(find.text('扫一扫'));
    await tester.pumpAndSettle();
    expect(find.text('去了 /friends/scan'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('删除好友：确认后从列表消失', (tester) async {
    final fake = world();
    await mount(tester, fake, const FriendsPage());
    await tester.pumpAndSettle();
    await tester.tap(find.text('铁牛'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除好友'));
    await tester.pumpAndSettle();
    expect(find.text('删除好友？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(fake.removed, ['u-bob']);
    expect(find.text('我的好友'), findsNothing);
    await unmount(tester);
  });

  testWidgets('没有好友时显示空状态和添加入口', (tester) async {
    await mount(tester, FakeFriendsRepository(), const FriendsPage());
    await tester.pumpAndSettle();
    expect(find.text('还没有好友'), findsOneWidget);
    expect(find.text('添加好友'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('断网时好友页给出提示，点再试一次可恢复', (tester) async {
    final fake = world()..offline = true;
    await mount(tester, fake, const FriendsPage());
    await tester.pumpAndSettle();
    expect(find.text('好友列表没加载出来'), findsOneWidget);
    expect(find.text('网络不可用，请检查网络后重试'), findsOneWidget);
    fake.offline = false;
    await tester.tap(find.text('再试一次'));
    await tester.pumpAndSettle();
    expect(find.text('我的好友'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('搜索：按用户名或昵称找到人，发申请后变成「已申请」', (tester) async {
    final fake = world();
    await mount(tester, fake, const FriendSearchPage());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '跑');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('小跑'), findsOneWidget);
    expect(find.text('@eve_run'), findsOneWidget);

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(fake.sentRequests, ['u-eve']);
    expect(find.text('已申请'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bob');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('已是好友'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '查无此人');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('没有找到这个人'), findsOneWidget);
    await unmount(tester);
  });

  group('新消息', () {
    test('来了新消息：未读 +1，并通知提醒；正在看那个人的聊天时不计未读', () async {
      final fake = world();
      final container = ProviderContainer(overrides: [
        friendsRepositoryProvider.overrideWithValue(fake),
        currentUserIdProvider.overrideWithValue('me'),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(friendsControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sub.read().byUser('u-bob')!.unread, 2);

      final arrived = <ChatMessage>[];
      container.read(friendsControllerProvider.notifier).incomingMessages.listen(arrived.add);
      fake.incoming('u-bob', '晚上见');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(arrived.map((m) => m.body), ['晚上见']);
      expect(sub.read().byUser('u-bob')!.unread, 3);
      expect(sub.read().byUser('u-bob')!.lastBody, '晚上见');

      container.read(activeChatProvider.notifier).set('u-bob');
      fake.incoming('u-bob', '在吗');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sub.read().byUser('u-bob')!.unread, 0); // 正在看，直接算已读
      expect(arrived.length, 2); // 仍会通知聊天页

      sub.close();
    });

    test('同一条消息被实时通道和定时刷新各报一次，只提醒一次', () async {
      final fake = world();
      final container = ProviderContainer(overrides: [
        friendsRepositoryProvider.overrideWithValue(fake),
        currentUserIdProvider.overrideWithValue('me'),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(friendsControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final arrived = <ChatMessage>[];
      container.read(friendsControllerProvider.notifier).incomingMessages.listen(arrived.add);

      fake.incoming('u-bob', '一条');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await container.read(friendsControllerProvider.notifier).refresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(arrived.length, 1);
      sub.close();
    });

    test('实时通道漏掉的消息，定时刷新会补上提醒', () async {
      final fake = world();
      final container = ProviderContainer(overrides: [
        friendsRepositoryProvider.overrideWithValue(fake),
        currentUserIdProvider.overrideWithValue('me'),
      ]);
      addTearDown(container.dispose);
      final sub = container.listen(friendsControllerProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final arrived = <ChatMessage>[];
      container.read(friendsControllerProvider.notifier).incomingMessages.listen(arrived.add);

      // 只写进库，不推实时事件
      final i = fake.entries.indexWhere((e) => e.user.id == 'u-bob');
      fake.entries[i] = fake.entries[i].copyWith(lastBody: '漏掉的', lastAt: DateTime.now().add(const Duration(minutes: 1)), unread: 3);
      await container.read(friendsControllerProvider.notifier).refresh();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(arrived.map((m) => m.body), ['漏掉的']);
      sub.close();
    });
  });

  testWidgets('聊天页：显示历史、发消息、表情进输入框；对方变成非好友后不能再发', (tester) async {
    final fake = world();
    final container = await mount(tester, fake, const ChatPage(friendId: 'u-bob'));
    await tester.pumpAndSettle();

    expect(find.text('今天练了吗'), findsOneWidget);
    expect(find.text('练了，胸'), findsOneWidget);
    expect(find.text('铁牛'), findsOneWidget);
    expect(container.read(activeChatProvider), 'u-bob');
    expect(container.read(friendsControllerProvider).byUser('u-bob')!.unread, 0);
    expect(find.text('发送'), findsNothing); // 没字时只有表情按钮

    await tester.tap(find.byTooltip('表情'));
    await tester.pumpAndSettle();
    expect(find.text('💪'), findsOneWidget);
    await tester.tap(find.text('💪'));
    await tester.tap(find.text('🔥'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '💪🔥');

    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('💪🔥'), findsOneWidget);
    expect(fake.chats['u-bob']!.last.body, '💪🔥');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');

    fake.incoming('u-bob', '走起');
    await tester.pumpAndSettle();
    expect(find.text('走起'), findsOneWidget);
    expect(container.read(friendsControllerProvider).byUser('u-bob')!.unread, 0); // 正在看，不计未读

    await unmount(tester);
  });

  testWidgets('聊天页：发送失败的消息有红色提示，点一下重发', (tester) async {
    final fake = world();
    await mount(tester, fake, const ChatPage(friendId: 'u-bob'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '你好');
    await tester.pumpAndSettle();
    fake.offline = true;
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('发送失败，点一下重发'), findsOneWidget);
    expect(find.text('网络不可用，请检查网络后重试'), findsOneWidget);

    fake.offline = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byTooltip('发送失败，点一下重发'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('发送失败，点一下重发'), findsNothing);
    expect(fake.chats['u-bob']!.last.body, '你好');
    await unmount(tester);
  });

  testWidgets('聊天页：已经不是好友时输入栏换成说明', (tester) async {
    final fake = world();
    await mount(tester, fake, const ChatPage(friendId: 'u-bob'));
    await tester.pumpAndSettle();
    fake.entries.removeWhere((e) => e.user.id == 'u-bob');
    fake.events$.add(const FriendshipsChanged());
    await tester.pumpAndSettle();
    expect(find.text('你们已经不是好友了，不能再发消息'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await unmount(tester);
  });

  testWidgets('隐私设置：每一项单独选，默认体重仅自己可见，改完立即保存', (tester) async {
    final fake = world();
    await mount(tester, fake, const PrivacyPage());
    await tester.pumpAndSettle();

    expect(find.text('训练记录'), findsWidgets);
    expect(find.text('具体运动量'), findsOneWidget);
    expect(find.text('体重'), findsOneWidget);
    expect(find.text('仅自己可见'), findsNWidgets(5));
    expect(find.text('好友可见'), findsNWidgets(5));

    // 体重那一项：点「好友可见」
    await tester.tap(find.text('好友可见').at(4)); // 五项里的最后一项是体重
    await tester.pumpAndSettle();
    expect(fake.privacy.showBodyWeight, isTrue);

    await tester.scrollUntilVisible(find.text('近 7 天'), 200);
    await tester.tap(find.text('近 7 天'));
    await tester.pumpAndSettle();
    expect(fake.privacy.historyDays, 7);
    await unmount(tester);
  });

  testWidgets('隐私设置：保存失败时退回原样并提示', (tester) async {
    final fake = world();
    await mount(tester, fake, const PrivacyPage());
    await tester.pumpAndSettle();
    fake.offline = true;
    await tester.scrollUntilVisible(find.text('全部'), 200);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('网络不可用，请检查网络后重试'), findsOneWidget);
    expect(fake.privacy.historyDays, 30);
    await unmount(tester);
  });

  testWidgets('好友运动记录：只显示对方公开的部分，点开看动作和每组', (tester) async {
    final fake = world();
    await mount(tester, fake, const FriendActivityPage(friendId: 'u-bob'));
    await tester.pumpAndSettle();

    expect(find.text('胸肩'), findsOneWidget);
    expect(find.text('体重对方没有公开'), findsOneWidget);
    expect(find.text('杠铃卧推'), findsNothing);
    await tester.tap(find.text('胸肩'));
    await tester.pumpAndSettle();
    expect(find.text('杠铃卧推'), findsOneWidget);
    expect(find.text('80×8'), findsOneWidget);
    expect(find.text('热 40×10'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('好友运动记录：对方什么都没公开时给出说明', (tester) async {
    final fake = world();
    fake.activities['u-bob'] = const FriendActivity(settings: PrivacySettings(showWorkouts: false));
    await mount(tester, fake, const FriendActivityPage(friendId: 'u-bob'));
    await tester.pumpAndSettle();
    expect(find.text('对方没有公开运动记录'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('我的二维码：生成随机码并倒计时，到期自动换新的', (tester) async {
    var now = DateTime(2026, 11, 10, 12);
    final fake = world()..codeExpiry = now.add(const Duration(seconds: 3));
    await mount(tester, fake, const MyQrPage(), overrides: [clockProvider.overrideWithValue(() => now)]);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.codesCreated, 1);
    expect(find.text('有效时间还剩'), findsOneWidget);
    expect(find.textContaining('00:0'), findsOneWidget);

    now = now.add(const Duration(seconds: 4)); // 过期
    fake.codeExpiry = now.add(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(fake.codesCreated, 2);
    expect(find.text('10:00'), findsOneWidget);
    await unmount(tester);
  });

  group('扫一扫', () {
    var now = DateTime(2026, 11, 10, 12);
    Future<void Function(String)> mountScan(WidgetTester tester, FakeFriendsRepository fake) async {
      void Function(String)? emit;
      await mount(
        tester,
        fake,
        const ScanPage(),
        overrides: [
          clockProvider.overrideWithValue(() => now),
          scannerBuilderProvider.overrideWithValue(({required onCode, required torch, required paused}) {
            emit = onCode;
            return const ColoredBox(color: Colors.black);
          }),
        ],
      );
      await tester.pumpAndSettle();
      return (s) => emit!(s);
    }

    testWidgets('扫到有效的码：看到对方，点「加为好友」直接成为好友', (tester) async {
      final fake = world();
      final scan = await mountScan(tester, fake);
      scan('myfit://friend/${'a' * 32}');
      await tester.pumpAndSettle();
      expect(find.text('被扫的人'), findsOneWidget);
      await tester.tap(find.text('加为好友'));
      await tester.pumpAndSettle();
      expect(fake.entries.any((e) => e.user.id == 'u-scan' && e.relation == FriendRelation.friend), isTrue);
      await unmount(tester);
    });

    testWidgets('过期或无效的码给出提示，不会弹出加好友', (tester) async {
      final fake = world();
      final scan = await mountScan(tester, fake);
      scan('myfit://friend/${'c' * 32}');
      await tester.pumpAndSettle();
      expect(find.text('二维码已过期，请对方刷新后再扫'), findsOneWidget);
      expect(find.text('加为好友'), findsNothing);
      now = now.add(const Duration(seconds: 4));
      scan('hello');
      await tester.pumpAndSettle();
      expect(find.text('这不是「我的健身」的好友二维码'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('扫到自己的码：说明是自己的', (tester) async {
      final fake = world();
      final scan = await mountScan(tester, fake);
      scan('myfit://friend/${'b' * 32}');
      await tester.pumpAndSettle();
      expect(find.text('这是你自己的二维码'), findsOneWidget);
      expect(find.text('加为好友'), findsNothing);
      await unmount(tester);
    });
  });
}
