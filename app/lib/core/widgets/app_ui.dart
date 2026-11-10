// 2.8.0 公共界面零件：卡片、墨色主卡、分段切换、筛选标签、对话框、空状态、底部操作栏。
// 页面只拼这些零件，不各写各的圆角和边框。

import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';

/// 把几段说明拼成一行：「6 个动作  24 组  约 55 分钟」。段与段之间留两个空格，不用圆点。
String metaLine(Iterable<String?> parts) => parts.where((p) => p != null && p.isNotEmpty).join('  ');

/// 平铺卡片：白底 + 发丝边，不带阴影。可点时整张有按压反馈。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.cardPadding),
    this.onTap,
    this.onLongPress,
    this.color,
    this.radius = AppRadius.lg,
    this.borderColor,
    this.borderWidth = AppStroke.hairline,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final double radius;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? c.border, width: borderWidth),
    );
    final body = Padding(padding: padding, child: child);
    final card = Material(
      color: color ?? c.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null ? body : InkWell(onTap: onTap, onLongPress: onLongPress, child: body),
    );
    if (onTap == null) return card;
    return PressScale(scale: PressScale.cardScale, child: card);
  }
}

/// 墨色主卡：全 App 最重的一块，只放「今天要做什么」和训练中的状态。
/// 右上角有一片很淡的杠铃滚花纹。
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.onTap, this.radius = AppRadius.lg});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: dark ? c.border : Colors.transparent, width: AppStroke.hairline),
    );
    final body = CustomPaint(
      painter: KnurlPainter(color: c.onHero),
      child: Padding(padding: padding, child: child),
    );
    final card = Material(
      color: c.hero,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              splashColor: c.onHero.withValues(alpha: 0.06),
              highlightColor: c.onHero.withValues(alpha: 0.04),
              child: body,
            ),
    );
    if (onTap == null) return card;
    return PressScale(scale: PressScale.cardScale, child: card);
  }
}

/// 杠铃握把上的滚花：两组交叉的细斜线，从右上角往左下淡出。
class KnurlPainter extends CustomPainter {
  const KnurlPainter({required this.color, this.strength = 0.09});
  final Color color;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..shader = RadialGradient(
        center: Alignment.topRight,
        radius: 1.1,
        colors: [color.withValues(alpha: strength), color.withValues(alpha: 0)],
        stops: const [0, 1],
      ).createShader(rect);
    const step = 9.0;
    const slope = 1.6; // 约 58°
    final reach = size.height / slope;
    canvas.save();
    canvas.clipRect(rect);
    for (double x = size.width * 0.25 - reach; x < size.width + reach; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + reach, size.height), paint);
      canvas.drawLine(Offset(x + reach, 0), Offset(x, size.height), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(KnurlPainter old) => old.color != color || old.strength != strength;
}

/// 分栏页顶部的大标题行。
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.trailing = const []});

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: AppSize.pageHeader,
      child: Row(
        children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleLarge.copyWith(color: c.text)),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// 卡片外的小节标题。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppText.titleSmall.copyWith(color: c.text))),
          ?trailing,
        ],
      ),
    );
  }
}

/// 分段切换：凹槽里一块会滑动的白色滑块。
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.height = AppSize.segmented,
    this.enabled = true,
  }) : assert(values.length == labels.length);

  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final n = values.length;
    final index = values.indexOf(selected).clamp(0, n - 1);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.text.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            duration: reduce ? Duration.zero : AppMotion.standard,
            curve: AppMotion.curve,
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: c.border, width: AppStroke.hairline),
                  boxShadow: dark ? null : const [BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1))],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: PressScale(
                    scale: PressScale.chipScale,
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      child: InkWell(
                        onTap: enabled ? () => onChanged(values[i]) : null,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: Center(
                          child: Text(
                            labels[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(
                              color: i == index ? c.text : c.text2,
                              fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 筛选标签：选中是橙色实心（深色模式是亮色实心），未选中是白底发丝边。
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.count,
    this.leading,
    this.trailing,
    this.height = AppSize.chip,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final int? count;
  final IconData? leading;
  final IconData? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onSelected : c.text;
    final chip = Material(
      color: selected ? c.selectedFill : c.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? Colors.transparent : c.text.withValues(alpha: 0.10), width: 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[Icon(leading, size: 16, color: fg), const SizedBox(width: 6)],
              Text(label, style: AppText.label.copyWith(color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text('$count', style: AppText.numSmall.copyWith(fontSize: 14, color: selected ? c.onSelected.withValues(alpha: 0.7) : c.text3)),
              ],
              if (trailing != null) ...[const SizedBox(width: 4), Icon(trailing, size: 12, color: selected ? fg : c.text3)],
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return chip;
    return PressScale(scale: PressScale.chipScale, child: chip);
  }
}

/// 不可点的小标签（「入门」「哑铃」「热身」）。
class AppTag extends StatelessWidget {
  const AppTag(this.label, {super.key, this.color, this.background, this.icon});

  final String label;
  final Color? color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.text2;
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: background ?? c.text.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(label, style: AppText.caption.copyWith(color: fg, fontWeight: FontWeight.w600, height: 1.2)),
        ],
      ),
    );
  }
}

/// 圆形图标按钮（页头右侧的「更多」「搜索」）。
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.tooltip, this.onPressed, this.size = 40, this.iconSize = 20, this.color, this.background});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressScale(
      scale: PressScale.smallScale,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: background ?? c.surface,
          shape: CircleBorder(side: BorderSide(color: c.border, width: AppStroke.hairline)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: iconSize, color: onPressed == null ? c.text3 : (color ?? c.text)),
            ),
          ),
        ),
      ),
    );
  }
}

enum AppDialogActionKind { primary, neutral, danger }

class AppDialogAction {
  const AppDialogAction(this.label, {this.onPressed, this.kind = AppDialogActionKind.neutral});
  final String label;
  final VoidCallback? onPressed;
  final AppDialogActionKind kind;
}

/// 对话框：标题、说明、底部一排等宽按钮（最多两个；三个以上竖着排）。
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, this.message, this.content, this.actions = const [], this.icon});

  final String title;
  final String? message;
  final Widget? content;
  final List<AppDialogAction> actions;
  final IconData? icon;

  Widget _button(BuildContext context, AppDialogAction a) {
    final c = context.colors;
    final child = FittedBox(fit: BoxFit.scaleDown, child: Text(a.label, maxLines: 1));
    return PressScale(
      child: switch (a.kind) {
        AppDialogActionKind.primary => FilledButton(onPressed: a.onPressed, child: child),
        AppDialogActionKind.neutral => ElevatedButton(onPressed: a.onPressed, child: child),
        AppDialogActionKind.danger => ElevatedButton(
            onPressed: a.onPressed,
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? c.text3 : c.danger),
            ),
            child: child,
          ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stacked = actions.length > 2;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(icon, size: 24, color: c.accentText),
                ),
                const SizedBox(height: 16),
              ],
              Text(title, style: AppText.titleMedium.copyWith(color: c.text)),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: AppText.label.copyWith(color: c.text2, height: 1.6)),
              ],
              if (content != null) ...[
                const SizedBox(height: 16),
                Flexible(child: content!),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 24),
                if (stacked)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _button(context, actions[i]),
                      ],
                    ],
                  )
                else
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: _button(context, actions[i])),
                      ],
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 空状态：一个线框图标、一句话、可选的一个下一步按钮。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.hint, this.action, this.compact = false});

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 20 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.text.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Icon(icon, size: 28, color: c.text3),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppText.titleSmall.copyWith(color: c.text)),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, textAlign: TextAlign.center, style: AppText.label.copyWith(color: c.text2)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// 页面底部固定的操作栏：纸色底 + 顶部一条发丝线。
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line, width: 1))),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: child),
      ),
    );
  }
}

/// 卡片里的一条发丝分隔线。
class HairDivider extends StatelessWidget {
  const HairDivider({super.key, this.indent = 0});
  final double indent;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(left: indent), child: Container(height: 1, color: context.colors.line));
}

/// 设置页的一行：左图标、标题、右侧值或箭头。
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.icon, required this.title, this.subtitle, this.value, this.onTap, this.trailing, this.danger = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = danger ? c.danger : c.text;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 22, color: danger ? c.danger : c.text2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppText.body.copyWith(color: fg, fontWeight: FontWeight.w500)),
                    if (subtitle != null) Text(subtitle!, style: AppText.caption.copyWith(color: c.text3)),
                  ],
                ),
              ),
              if (value != null) Text(value!, style: AppText.label.copyWith(color: c.text2)),
              if (trailing != null)
                trailing!
              else if (onTap != null && !danger) ...[
                const SizedBox(width: 4),
                Icon(AppIcons.chevronRight, size: 14, color: c.text3),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
