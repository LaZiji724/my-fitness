import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/plan/start_date_sheet.dart';

void main() {
  test('startDateLabel / startDateRelative：带周几和相对今天的说法', () {
    final today = DateTime(2026, 11, 26); // 周四
    expect(startDateLabel(today), '11月26日 周四');
    expect(startDateLabel(DateTime(2026, 12, 1)), '12月1日 周二');
    expect(startDateRelative(today, today), '今天');
    expect(startDateRelative(DateTime(2026, 11, 25), today), '昨天');
    expect(startDateRelative(DateTime(2026, 11, 27), today), '明天');
    expect(startDateRelative(DateTime(2026, 11, 19), today), '7 天前');
    expect(startDateRelative(DateTime(2026, 12, 3), today), '7 天后');
  });

  Future<DateTime?> openSheet(
    WidgetTester tester, {
    bool alignToMonday = false,
    Brightness brightness = Brightness.light,
  }) async {
    DateTime? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showStartDateSheet(
                    context,
                    today: DateTime(2026, 11, 26, 9, 30),
                    planName: '推拉腿',
                    alignToMonday: alignToMonday,
                  );
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('计划开始日期'), findsOneWidget);
    expect(done, isFalse);
    return result;
  }

  testWidgets('默认选中今天，前后各 7 天共 15 格，每格有周几', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openSheet(tester);
    // 15 个日期格：19..30（11 月）+ 1、2、3（12 月）
    for (final d in [19, 26, 30, 1, 3]) {
      expect(find.text('$d'), findsWidgets);
    }
    expect(find.text('12月'), findsOneWidget); // 跨月的 1 号标出月份
    expect(find.text('11月'), findsOneWidget); // 第一格标出月份
    expect(find.text('周四'), findsWidgets);
    expect(find.text('今天'), findsWidgets); // 顶部胶囊 + 格子
  });

  testWidgets('点选过去的日期后确定，返回该日期（只含年月日）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showStartDateSheet(
              context,
              today: DateTime(2026, 11, 26, 9, 30),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('11月21日 周六')));
    await tester.pumpAndSettle();
    expect(find.text('5 天前'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result, DateTime(2026, 11, 21));
  });

  testWidgets('取消返回 null；计划库计划提示从所在周周一开始', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DateTime? result = DateTime(2000);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showStartDateSheet(
              context,
              today: DateTime(2026, 11, 26),
              alignToMonday: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('从 11月23日 周一 起算第 1 周'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
