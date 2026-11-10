import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/app/app_shell.dart';
import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';

void main() {
  Widget host(ThemeData theme) {
    Widget page(String t) => Center(child: Text('页面-$t'));
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            for (final p in ['plan', 'calendar', 'today', 'stats', 'friends'])
              StatefulShellBranch(routes: [
                GoRoute(path: '/$p', builder: (_, _) => page(p)),
              ]),
          ],
        ),
      ],
    );
    return ProviderScope(overrides: [friendsBadgeProvider.overrideWithValue(0)], child: MaterialApp.router(theme: theme, routerConfig: router));
  }

  for (final dark in [false, true]) {
    testWidgets('底部 5 个分栏可切换（${dark ? '深色' : '浅色'}）', (tester) async {
      await tester.pumpWidget(host(dark ? AppTheme.dark() : AppTheme.light()));
      await tester.pumpAndSettle();

      for (final label in ['计划', '日历', '训练', '数据', '好友']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('页面-today'), findsOneWidget);

      // 「训练」在正中间，比两侧的分栏项更靠下的标签位置相同，但圆钮更大
      final train = tester.getCenter(find.text('训练')).dx;
      final screen = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(train, closeTo(screen / 2, 1));
      expect(tester.getCenter(find.text('计划')).dx, lessThan(tester.getCenter(find.text('日历')).dx));
      expect(tester.getCenter(find.text('数据')).dx, lessThan(tester.getCenter(find.text('好友')).dx));
      expect(tester.getCenter(find.text('日历')).dx, lessThan(train));
      expect(tester.getCenter(find.text('数据')).dx, greaterThan(train));

      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      expect(find.text('页面-calendar'), findsOneWidget);

      await tester.tap(find.text('数据'));
      await tester.pumpAndSettle();
      expect(find.text('页面-stats'), findsOneWidget);
    });
  }

  testWidgets('底部分栏按下时有缩放动效，松手恢复', (tester) async {
    await tester.pumpWidget(host(AppTheme.light()));
    await tester.pumpAndSettle();

    double scaleOf(String label) => tester
        .widget<AnimatedScale>(find
            .ancestor(of: find.text(label), matching: find.byType(AnimatedScale))
            .first)
        .scale;

    final g = await tester.startGesture(tester.getCenter(find.text('日历')));
    await tester.pump();
    expect(scaleOf('日历'), PressScale.chipScale);
    expect(scaleOf('计划'), 1); // 别的分栏不动
    await g.up();
    await tester.pumpAndSettle();
    expect(scaleOf('日历'), 1);
    expect(find.text('页面-calendar'), findsOneWidget);
  });

  testWidgets('点正中间的训练圆钮回到首页', (tester) async {
    await tester.pumpWidget(host(AppTheme.light()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('好友'));
    await tester.pumpAndSettle();
    expect(find.text('页面-friends'), findsOneWidget);
    // 圆钮本身（不是文字）也能点
    await tester.tap(find.byIcon(AppIcons.navTrain));
    await tester.pumpAndSettle();
    expect(find.text('页面-today'), findsOneWidget);
  });

  test('主题令牌：浅色与深色都能取到颜色扩展', () {
    expect(AppTheme.light().extension<AppColors>(), isNotNull);
    expect(AppTheme.dark().extension<AppColors>(), isNotNull);
    expect(AppColors.light.heatFor(0), AppColors.light.heat[0]);
    expect(AppColors.light.heatFor(13), AppColors.light.heat[4]);
  });
}
