import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_fitness/app/app_shell.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';

void main() {
  Widget host(ThemeData theme) {
    Widget page(String t) => Center(child: Text('页面-$t'));
    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            for (final p in ['today', 'plan', 'calendar', 'exercises', 'stats'])
              StatefulShellBranch(routes: [
                GoRoute(path: '/$p', builder: (_, _) => page(p)),
              ]),
          ],
        ),
      ],
    );
    return ProviderScope(child: MaterialApp.router(theme: theme, routerConfig: router));
  }

  for (final dark in [false, true]) {
    testWidgets('底部 5 个分栏可切换（${dark ? '深色' : '浅色'}）', (tester) async {
      await tester.pumpWidget(host(dark ? AppTheme.dark() : AppTheme.light()));
      await tester.pumpAndSettle();

      for (final label in ['训练', '计划', '日历', '动作', '数据']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('页面-today'), findsOneWidget);

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

  test('主题令牌：浅色与深色都能取到颜色扩展', () {
    expect(AppTheme.light().extension<AppColors>(), isNotNull);
    expect(AppTheme.dark().extension<AppColors>(), isNotNull);
    expect(AppColors.light.heatFor(0), AppColors.light.heat[0]);
    expect(AppColors.light.heatFor(13), AppColors.light.heat[4]);
  });
}
