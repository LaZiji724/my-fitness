import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/update/update_ui.dart';

/// 底部分栏的一项。
class NavItem {
  const NavItem(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// 底部 5 个分栏：训练、计划、日历、动作、数据。
/// 「模板」并入「计划」页，「我的」从训练页左上角头像进入。
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const destinations = <NavItem>[
    NavItem('训练', AppIcons.navTrain, AppIcons.navTrainOn),
    NavItem('计划', AppIcons.navPlan, AppIcons.navPlanOn),
    NavItem('日历', AppIcons.navCalendar, AppIcons.navCalendarOn),
    NavItem('动作', AppIcons.navExercises, AppIcons.navExercisesOn),
    NavItem('数据', AppIcons.navStats, AppIcons.navStatsOn),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: UpdateAutoCheck(child: shell),
      bottomNavigationBar: AppNavBar(
        items: destinations,
        index: shell.currentIndex,
        onSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

/// 底栏：纸色底、顶部一条发丝线；选中项图标变实心、文字变墨色加粗，不用色块。
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.items, required this.index, required this.onSelected});

  final List<NavItem> items;
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
                    child: _NavButton(item: items[i], selected: i == index, onTap: () => onSelected(i)),
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
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
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
            AnimatedSwitcher(
              duration: AppMotion.fast,
              child: Icon(selected ? item.selectedIcon : item.icon, key: ValueKey(selected), size: 24, color: color),
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
