import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';
import 'package:my_fitness/features/update/update_ui.dart';

/// 底部分栏的一项。
class NavItem {
  const NavItem(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 底部 5 个分栏：计划、日历 | 训练 | 数据、好友。
/// 「训练」在正中间，做成凸起的大圆钮，外面围一圈橙色；
/// 「动作库」和「模板」并入「计划」页的分栏，「我的」从训练页左上角头像进入。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const destinations = <NavItem>[
    NavItem('计划', AppIcons.navPlan, AppIcons.navPlanOn),
    NavItem('日历', AppIcons.navCalendar, AppIcons.navCalendarOn),
    NavItem('训练', AppIcons.navTrain, AppIcons.navTrainOn),
    NavItem('数据', AppIcons.navStats, AppIcons.navStatsOn),
    NavItem('好友', AppIcons.navFriends, AppIcons.navFriendsOn),
  ];

  /// 「训练」在 [destinations] 里的位置（正中间）
  static const trainIndex = 2;

  /// 「好友」在 [destinations] 里的位置
  static const friendsIndex = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: UpdateAutoCheck(child: shell),
      bottomNavigationBar: AppNavBar(
        items: destinations,
        centerIndex: trainIndex,
        badges: {friendsIndex: ref.watch(friendsBadgeProvider)},
        index: shell.currentIndex,
        onSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

/// 底栏：纸色底、顶部一条发丝线。两侧各两项，选中项图标变实心、文字变墨色加粗；
/// 正中间的 [centerIndex] 是凸起的圆钮：外面一圈炭火橙，底栏在它周围向下凹出一个缺口，
/// 选中时圆钮整个填成橙色并亮起光晕。
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
    this.centerIndex = 2,
    this.badges = const {},
  });

  final List<NavItem> items;

  /// 分栏序号 → 角标数字（0 不显示）
  final Map<int, int> badges;
  final int index;
  final int centerIndex;
  final ValueChanged<int> onSelected;

  /// 圆钮凸出底栏顶线的高度（这一段是透明的，只有圆钮自己能点）
  static const double lift = 26;

  /// 圆钮：里面的圆盘、外面的橙色圈、两者之间的空隙
  static const double disc = 52;
  static const double ringGap = 3;
  static const double ringStroke = 2.5;
  static const double ringOuter = disc + (ringGap + ringStroke) * 2;

  /// 圆钮圆心比底栏顶线低多少
  static const double centerDrop = 6;

  /// 底栏缺口的半径（比橙色圈再大一点）
  static const double notchRadius = ringOuter / 2 + 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final slot = notchRadius * 2 + 12;
    return SizedBox(
      height: lift + AppSize.navBar + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _NavBarPainter(fill: c.surface, line: c.line, notchRadius: notchRadius, centerDrop: centerDrop, lift: lift),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: lift,
            height: AppSize.navBar,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  if (i == centerIndex)
                    SizedBox(width: slot)
                  else
                    Expanded(
                      // 每个分栏项按下时轻轻缩一下
                      child: PressScale(
                        scale: PressScale.chipScale,
                        child: _NavButton(item: items[i], selected: i == index, badge: badges[i] ?? 0, onTap: () => onSelected(i)),
                      ),
                    ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            height: lift + AppSize.navBar,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: slot,
                child: PressScale(
                  scale: PressScale.chipScale,
                  child: _TrainButton(item: items[centerIndex], selected: index == centerIndex, onTap: () => onSelected(centerIndex)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底栏的底色：顶线在正中间向下凹出一个圆形缺口，给「训练」圆钮让位。
class _NavBarPainter extends CustomPainter {
  _NavBarPainter({required this.fill, required this.line, required this.notchRadius, required this.centerDrop, required this.lift});

  final Color fill;
  final Color line;
  final double notchRadius;
  final double centerDrop;
  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final topY = lift;
    final center = Offset(cx, topY + centerDrop);
    // 圆与顶线相交处离圆心的水平距离
    final dx = math.sqrt(notchRadius * notchRadius - centerDrop * centerDrop);
    // 从左交点出发，沿圆经过下方走到右交点（大半圈）
    final startAngle = math.atan2(-centerDrop, -dx);
    final sweep = -(math.pi + 2 * math.asin(centerDrop / notchRadius));

    final edge = Path()
      ..moveTo(0, topY)
      ..lineTo(cx - dx, topY)
      ..arcTo(Rect.fromCircle(center: center, radius: notchRadius), startAngle, sweep, false)
      ..lineTo(size.width, topY);
    final body = Path.from(edge)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(
      edge,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_NavBarPainter old) =>
      old.fill != fill || old.line != line || old.notchRadius != notchRadius || old.centerDrop != centerDrop || old.lift != lift;
}

/// 正中间的「训练」圆钮。
class _TrainButton extends StatelessWidget {
  const _TrainButton({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const ringBox = AppNavBar.ringOuter;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap();
        },
        child: Column(
          children: [
            SizedBox(height: AppNavBar.lift + AppNavBar.centerDrop - ringBox / 2),
            // 橙色圈 + 光晕
            AnimatedContainer(
              duration: AppMotion.standard,
              curve: AppMotion.curve,
              width: ringBox,
              height: ringBox,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.accent, width: AppNavBar.ringStroke),
                boxShadow: [
                  BoxShadow(
                    color: c.accent.withValues(alpha: selected ? 0.42 : 0.16),
                    blurRadius: selected ? 18 : 10,
                    spreadRadius: selected ? 1 : 0,
                  ),
                ],
              ),
              // 圆盘：没选中是墨色底橙色图标，选中填成橙色
              child: AnimatedContainer(
                duration: AppMotion.standard,
                curve: AppMotion.curve,
                width: AppNavBar.disc,
                height: AppNavBar.disc,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? c.accent : c.hero,
                ),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 28,
                  color: selected ? c.onAccent : c.accent,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: AppText.caption.copyWith(color: selected ? c.text : c.text3, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap, this.badge = 0});

  final NavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.text : c.text3;
    return Semantics(
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onTap();
        },
        radius: 36,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: AppMotion.fast,
                  child: Icon(selected ? item.selectedIcon : item.icon, key: ValueKey(selected), size: 24, color: color),
                ),
                if (badge > 0)
                  Positioned(
                    left: 14,
                    top: -6,
                    child: IgnorePointer(child: UnreadBadge(badge)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: AppText.caption.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}
