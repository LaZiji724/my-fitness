import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_fitness/core/widgets/press_scale.dart';

double _scaleOf(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('按下可点的按钮会缩小，松手后恢复', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(PressScale(
      child: FilledButton(onPressed: () => taps++, child: const Text('完成')),
    )));
    expect(_scaleOf(tester), 1);

    final g = await tester.startGesture(tester.getCenter(find.text('完成')));
    await tester.pump();
    expect(_scaleOf(tester), PressScale.defaultScale);
    await tester.pump(const Duration(milliseconds: 200));
    final pressed = tester.getSize(find.byType(FilledButton));

    await g.up();
    await tester.pump();
    expect(_scaleOf(tester), 1);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.getSize(find.byType(FilledButton)), pressed);
  });

  testWidgets('灰掉的按钮不会缩小', (tester) async {
    await tester.pumpWidget(_host(PressScale(
      child: const FilledButton(onPressed: null, child: Text('不能点')),
    )));
    final g = await tester.startGesture(tester.getCenter(find.text('不能点')));
    await tester.pump();
    expect(_scaleOf(tester), 1);
    await g.up();
  });

  testWidgets('普通文字、空白处不会缩小', (tester) async {
    await tester.pumpWidget(_host(const PressScale(child: Text('只是文字'))));
    final g = await tester.startGesture(tester.getCenter(find.text('只是文字')));
    await tester.pump();
    expect(_scaleOf(tester), 1);
    await g.up();
  });

  testWidgets('手指拖动（滑动列表）时自动弹回，且不触发点击', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(PressScale(
      child: Material(
        child: InkWell(
          onTap: () => taps++,
          child: const SizedBox(width: 200, height: 80, child: Text('卡片')),
        ),
      ),
    )));
    final g = await tester.startGesture(tester.getCenter(find.text('卡片')));
    await tester.pump();
    expect(_scaleOf(tester), PressScale.defaultScale);
    await g.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(_scaleOf(tester), 1);
    await g.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('系统开了「减少动画」时不缩放，但点击照常', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(
      PressScale(
        child: FilledButton(onPressed: () => taps++, child: const Text('完成')),
      ),
      disableAnimations: true,
    ));
    final g = await tester.startGesture(tester.getCenter(find.text('完成')));
    await tester.pump();
    expect(_scaleOf(tester), 1);
    await g.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('自定义缩放比例生效', (tester) async {
    await tester.pumpWidget(_host(PressScale(
      scale: PressScale.smallScale,
      child: IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
    )));
    final g = await tester.startGesture(tester.getCenter(find.byIcon(Icons.add)));
    await tester.pump();
    expect(_scaleOf(tester), PressScale.smallScale);
    await g.up();
    await tester.pumpAndSettle();
  });
}
