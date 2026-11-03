import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';

/// 左滑露出红色「删除」按钮（占整张卡片宽度的 30%），点按钮才真正删除。
///
/// 往右滑回去、点一下卡片、或者滑得不够远，都会收回，不会误删。
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.label = '删除',
    this.radius,
  });

  final Widget child;
  final VoidCallback onDelete;
  final String label;
  final BorderRadius? radius;

  /// 露出的按钮占卡片宽度的比例。
  static const double revealFraction = 0.3;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> with SingleTickerProviderStateMixin {
  /// 0 = 收起，1 = 完全露出
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  void _settle(double velocityDx) {
    final fling = velocityDx.abs() > 400;
    final target = fling ? (velocityDx < 0 ? 1.0 : 0.0) : (_open.value > 0.5 ? 1.0 : 0.0);
    _open.animateTo(target, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = widget.radius ?? AppRadius.card;
    return LayoutBuilder(builder: (context, box) {
      final reveal = box.maxWidth * SwipeToDelete.revealFraction;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => _open.value = (_open.value - d.delta.dx / reveal).clamp(0.0, 1.0),
        onHorizontalDragEnd: (d) => _settle(d.velocity.pixelsPerSecond.dx),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: reveal,
                    child: Material(
                      color: c.danger,
                      child: InkWell(
                        onTap: () {
                          _open.value = 0;
                          widget.onDelete();
                        },
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                              const SizedBox(height: 2),
                              Text(
                                widget.label,
                                style: AppText.label.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _open,
                builder: (context, child) => Transform.translate(offset: Offset(-reveal * _open.value, 0), child: child),
                // 露出时点卡片只是收起，不进入模板
                child: AnimatedBuilder(
                  animation: _open,
                  builder: (context, child) => _open.value > 0
                      ? GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _open.animateTo(0), child: AbsorbPointer(child: child))
                      : child!,
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
