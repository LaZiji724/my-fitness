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

/// 底部 6 个分栏：训练、计划、日历、动作、数据、好友。
/// 「模板」并入「计划」页，「我的」从训练页左上角头像进入。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const destinations = <NavItem>[
    NavItem('训练', AppIcons.navTrain, AppIcons.navTrainOn),
    NavItem('计划', AppIcons.navPlan, AppIcons.navPlanOn),
    NavItem('日历', AppIcons.navCalendar, AppIcons.navCalendarOn),
    NavItem('动作', AppIcons.navExercises, AppIcons.navExercisesOn),
    NavItem('数据', AppIcons.navStats, AppIcons.navStatsOn),
    NavItem('好友', AppIcons.navFriends, AppIcons.navFriendsOn),
  ];

  /// 「好友」在 [destinations] 里的位置
  static const friendsIndex = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: UpdateAutoCheck(child: shell),
      bottomNavigationBar: AppNavBar(
        items: destinations,
        badges: {friendsIndex: ref.watch(friendsBadgeProvider)},
        index: shell.currentIndex,
        onSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

/// 底栏：纸色底、顶部一条发丝线；选中项图标变实心、文字变墨色加粗，不用色块。
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.items, required this.index, required this.onSelected, this.badges = const {}});

  final List<NavItem> items;

  /// 分栏序号 → 角标数字（0 不显示）
  final Map<int, int> badges;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSize.navBar,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
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
