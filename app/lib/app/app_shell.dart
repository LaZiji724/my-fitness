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
    // 键盘弹出时收起底栏，把地方让给输入
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: AppNavFrame(
        items: destinations,
        centerIndex: trainIndex,
        badges: {friendsIndex: ref.watch(friendsBadgeProvider)},
        index: shell.currentIndex,
        showBar: !keyboardUp,
        onSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        child: UpdateAutoCheck(child: shell),
      ),
    );
  }
}

/// 页面内容 + 底栏。
///
/// 底栏只占自己那一条高度，页面内容滚动到底栏上沿就停住，不会被一整条透明区域挡住；
/// 正中间的「训练」圆钮有一半伸到底栏上方，它单独浮在最上层，只有圆钮本身那一小块会盖住内容、接收点击。
class AppNavFrame extends StatelessWidget {
  const AppNavFrame({
    super.key,
    required this.child,
    required this.items,
    required this.index,
    required this.onSelected,
    this.centerIndex = 2,
    this.badges = const {},
    this.showBar = true,
  });

  final Widget child;
  final List<NavItem> items;
  final Map<int, int> badges;
  final int index;
  final int centerIndex;
  final bool showBar;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final inset = showBar ? MediaQuery.paddingOf(context).bottom : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Column(
            children: [
              // 底栏自己会把底部安全区撑开，页面里不要再留一份
              Expanded(child: MediaQuery.removePadding(context: context, removeBottom: true, child: child)),
              if (showBar)
                AppNavBar(
                  items: items,
                  index: index,
                  centerIndex: centerIndex,
                  badges: badges,
                  bottomInset: inset,
                  onSelected: onSelected,
                ),
            ],
          ),
        ),
        if (showBar)
          Positioned(
            left: 0,
            right: 0,
            bottom: inset + AppNavBar.height - AppNavBar.ringBottom,
            height: AppNavBar.ringOuter,
            child: Center(
              child: _TrainButton(item: items[centerIndex], selected: index == centerIndex, onTap: () => onSelected(centerIndex)),
            ),
          ),
      ],
    );
  }
}

/// 底栏：纸色底、顶部一条发丝线。两侧各两项，选中项图标变实心、文字变墨色加粗；
/// 正中间留给凸起的「训练」圆钮：底栏在圆钮周围向下凹出一个缺口，
/// 「训练」两个字和其他分栏的文字排在同一条线上。
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
    this.centerIndex = 2,
    this.badges = const {},
    this.bottomInset = 0,
  });

  final List<NavItem> items;

  /// 分栏序号 → 角标数字（0 不显示）
  final Map<int, int> badges;
  final int index;
  final int centerIndex;
  final double bottomInset;
  final ValueChanged<int> onSelected;

  /// 底栏本体高度（不含底部安全区）
  static const double height = AppSize.navBar;

  /// 图标、图标与文字的间距、文字行高：所有分栏项（包括正中间的「训练」）共用，保证文字在同一条线上
  static const double iconSize = 24;
  static const double labelGap = 4;
  static const double labelHeight = 16;

  /// 文字上沿离底栏顶线的距离（图标 + 文字整体在底栏里上下居中）
  static const double labelTop = (height - (iconSize + labelGap + labelHeight)) / 2 + iconSize + labelGap;

  /// 圆钮：里面的圆盘、外面的橙色圈、两者之间的空隙
  static const double disc = 48;
  static const double ringGap = 3.5;
  static const double ringStroke = 2.5;
  static const double ringOuter = disc + (ringGap + ringStroke) * 2;

  /// 圆钮圆心比底栏顶线低多少：圆钮底边离「训练」文字留 4px
  static const double centerDrop = labelTop - 4 - ringOuter / 2;

  /// 圆钮底边离底栏顶线的距离
  static const double ringBottom = centerDrop + ringOuter / 2;

  /// 底栏缺口的半径（比橙色圈再大一点）
  static const double notchRadius = ringOuter / 2 + 5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final slot = notchRadius * 2 + 8;
    return SizedBox(
      height: height + bottomInset,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _NavBarPainter(fill: c.surface, line: c.line, notchRadius: notchRadius, centerDrop: centerDrop),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: height,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  if (i == centerIndex)
                    // 正中间只放「训练」两个字，圆钮在上面一层
                    SizedBox(
                      width: slot,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i != index) HapticFeedback.selectionClick();
                          onSelected(i);
                        },
                        child: ExcludeSemantics(
                          child: _NavSlot(
                            icon: const SizedBox(height: iconSize),
                            label: items[i].label,
                            selected: i == index,
                          ),
                        ),
                      ),
                    )
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
        ],
      ),
    );
  }
}

/// 底栏的底色：顶线在正中间向下凹出一个圆形缺口，给「训练」圆钮让位。
class _NavBarPainter extends CustomPainter {
  _NavBarPainter({required this.fill, required this.line, required this.notchRadius, required this.centerDrop});

  final Color fill;
  final Color line;
  final double notchRadius;
  final double centerDrop;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final center = Offset(cx, centerDrop);
    // 圆与顶线相交处离圆心的水平距离
    final dx = math.sqrt(notchRadius * notchRadius - centerDrop * centerDrop);
    // 从左交点出发，沿圆经过下方走到右交点（大半圈）
    final startAngle = math.atan2(-centerDrop, -dx);
    final sweep = -(math.pi + 2 * math.asin(centerDrop / notchRadius));

    final edge = Path()
      ..moveTo(0, 0)
      ..lineTo(cx - dx, 0)
      ..arcTo(Rect.fromCircle(center: center, radius: notchRadius), startAngle, sweep, false)
      ..lineTo(size.width, 0);
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
      old.fill != fill || old.line != line || old.notchRadius != notchRadius || old.centerDrop != centerDrop;
}

/// 一个分栏项的版面：图标在上、文字在下，整体在底栏里上下居中。
/// 所有分栏项（含正中间的「训练」）都用它，所以文字一定在同一条线上。
class _NavSlot extends StatelessWidget {
  const _NavSlot({required this.icon, required this.label, required this.selected});

  final Widget icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.text : c.text3;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: AppNavBar.iconSize, child: Center(child: icon)),
        const SizedBox(height: AppNavBar.labelGap),
        SizedBox(
          height: AppNavBar.labelHeight,
          child: Center(
            child: Text(
              label,
              style: AppText.caption.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, height: 1),
            ),
          ),
        ),
      ],
    );
  }
}

/// 正中间的「训练」圆钮（只有图标，文字在底栏里）。
class _TrainButton extends StatelessWidget {
  const _TrainButton({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: PressScale(
        scale: PressScale.chipScale,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!selected) HapticFeedback.selectionClick();
            onTap();
          },
          // 点击区比圆钮略大一圈，拇指好按
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedContainer(
              duration: AppMotion.standard,
              curve: AppMotion.curve,
              width: AppNavBar.ringOuter,
              height: AppNavBar.ringOuter,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.accent, width: AppNavBar.ringStroke),
                boxShadow: [
                  BoxShadow(
                    color: c.accent.withValues(alpha: selected ? 0.38 : 0.14),
                    blurRadius: selected ? 16 : 8,
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
                  // 浅色模式下没选中时和页面背景同色（不是黑的）；深色模式保持墨色
                  color: selected ? c.accent : (Theme.of(context).brightness == Brightness.dark ? c.hero : c.bg),
                ),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 28,
                  color: selected ? c.onAccent : c.accent,
                ),
              ),
            ),
          ),
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
        child: _NavSlot(
          selected: selected,
          label: item.label,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedSwitcher(
                duration: AppMotion.fast,
                child: Icon(selected ? item.selectedIcon : item.icon, key: ValueKey(selected), size: AppNavBar.iconSize, color: color),
              ),
              if (badge > 0)
                Positioned(
                  left: 14,
                  top: -6,
                  child: IgnorePointer(child: UnreadBadge(badge)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
