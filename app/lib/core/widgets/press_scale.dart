import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:my_fitness/core/theme/app_theme.dart';

/// 统一的「按压动效」：手指按下时控件轻轻缩小，松手后带一点回弹。
///
/// 用法：把任何可点的控件（按钮、卡片、分栏项…）整个包起来即可，
/// 不用改里面的 onTap / onPressed。
///
/// 特点：
/// - 只在手指真的按在「可点击」的地方才缩小，灰掉的按钮、空白处不会动；
/// - 手指拖动超过一小段（在滑动列表）就自动弹回，不会一滑动就缩；
/// - 系统开了「减少动画」时不缩放；
/// - 不抢点击事件，不影响里面原有的水波纹。
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = defaultScale});

  final Widget child;

  /// 按下时缩到的比例。越大的控件缩得越少，小控件缩得多一点才看得出来。
  final double scale;

  /// 普通按钮。
  static const double defaultScale = 0.96;

  /// 整行 / 大卡片（缩太多会显得晃）。
  static const double cardScale = 0.98;

  /// 小标签、筛选项、数字键、日历格。
  static const double chipScale = 0.94;

  /// 小图标按钮（加减、关闭、完成这一组…）。
  static const double smallScale = 0.88;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  int? _pointer;
  Offset _start = Offset.zero;

  /// 手指按下的位置下面，有没有真正能点的东西。
  bool _hitsTappable(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(globalPosition));
    for (final entry in result.path) {
      final target = entry.target;
      // 点击会在语义层留下「可点」标记：新版 GestureDetector / InkWell 用
      // Semantics(onTap)，旧写法用 RenderSemanticsGestureHandler，两种都认。
      if (target is RenderSemanticsAnnotations) {
        final p = target.properties;
        if (p.onTap != null || p.onLongPress != null) return true;
      } else if (target is RenderSemanticsGestureHandler) {
        if (target.onTap != null || target.onLongPress != null) return true;
      }
    }
    return false;
  }

  void _onDown(PointerDownEvent e) {
    if (_pointer != null) return; // 多指时只跟第一根
    if (!_hitsTappable(e.position)) return;
    _pointer = e.pointer;
    _start = e.position;
    setState(() => _down = true);
  }

  void _onMove(PointerMoveEvent e) {
    // 长按拖动排序时，原来的卡片会被拿走换成拖动中的副本，手指的后续事件仍会路由到这里
    if (!mounted || e.pointer != _pointer || !_down) return;
    if ((e.position - _start).distance > kTouchSlop) {
      setState(() => _down = false);
    }
  }

  void _onEnd(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (mounted && _down) setState(() => _down = false);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final pressed = _down && !reduce;
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onEnd,
      onPointerCancel: _onEnd,
      child: AnimatedScale(
        scale: pressed ? widget.scale : 1,
        // 按下要快，松手稍慢并略微回弹，手感更「弹」
        duration: pressed
            ? const Duration(milliseconds: 80)
            : AppMotion.standard,
        curve: pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
