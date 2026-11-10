import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/workout/number_pad_sheet.dart';
import 'package:my_fitness/features/workout/workout_math.dart' show formatWeight;

/// 弹出一个输入名称的对话框，取消返回 null。
Future<String?> promptName(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '名称',
  String confirm = '确定',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial, hint: hint, confirm: confirm),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial, required this.hint, required this.confirm});
  final String title;
  final String initial;
  final String hint;
  final String confirm;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.title,
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        AppDialogAction('取消', onPressed: () => Navigator.pop(context)),
        AppDialogAction(widget.confirm, kind: AppDialogActionKind.primary, onPressed: () => Navigator.pop(context, _controller.text)),
      ],
    );
  }
}

/// 新建计划：名称 + 几天一循环。取消返回 null。
Future<({String name, int days})?> promptNewPlan(BuildContext context) {
  return showDialog<({String name, int days})>(
    context: context,
    builder: (_) => const _NewPlanDialog(),
  );
}

class _NewPlanDialog extends StatefulWidget {
  const _NewPlanDialog();

  @override
  State<_NewPlanDialog> createState() => _NewPlanDialogState();
}

class _NewPlanDialogState extends State<_NewPlanDialog> {
  final _controller = TextEditingController();
  int _days = 7;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: '新建计划',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(hintText: '计划名称，如 推拉腿'),
          ),
          StepperField(label: '几天一循环', value: _days, min: 1, max: 28, unit: ' 天', onChanged: (v) => setState(() => _days = v)),
        ],
      ),
      actions: [
        AppDialogAction('取消', onPressed: () => Navigator.pop(context)),
        AppDialogAction('创建', kind: AppDialogActionKind.primary, onPressed: () => Navigator.pop(context, (name: _controller.text, days: _days))),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = '确定',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      title: title,
      message: message,
      actions: [
        AppDialogAction('取消', onPressed: () => Navigator.pop(ctx, false)),
        // 删除类操作用警示红，避免和普通确认混淆
        AppDialogAction(
          confirm,
          kind: confirm.contains('删除') ? AppDialogActionKind.danger : AppDialogActionKind.primary,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 「− 数值 +」步进器，用在组数、次数、休息秒数这类小范围整数上。
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
    this.step = 1,
    this.unit = '',
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget button(IconData icon, String tip, VoidCallback? onTap) => PressScale(
      scale: PressScale.smallScale,
      child: Semantics(
            button: true,
            label: tip,
            child: Material(
              color: onTap == null ? Colors.transparent : c.sunken,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: onTap == null ? BorderSide(color: c.text.withValues(alpha: 0.08), width: 1) : BorderSide.none,
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                onTap: onTap,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(icon, size: 16, color: onTap == null ? c.text3.withValues(alpha: 0.5) : c.text),
                ),
              ),
            ),
          ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body.copyWith(color: c.text))),
          button(AppIcons.minus, '$label 减少', value - step < min ? null : () => onChanged(value - step)),
          SizedBox(
            width: 84,
            child: Center(
              child: Text('$value$unit', style: AppText.numMedium.copyWith(color: c.text)),
            ),
          ),
          button(AppIcons.plus, '$label 增加', value + step > max ? null : () => onChanged(value + step)),
        ],
      ),
    );
  }
}

/// 「− 负重 +」步进器：每次加减 2.5 公斤，点中间的数字可以直接输入；减到 0 就是「不设」。
/// [value] 为空表示不设负重（开练时沿用上次的重量）。
class WeightField extends StatelessWidget {
  const WeightField({super.key, required this.value, required this.onChanged, this.label = '负重'});

  final double? value;
  final ValueChanged<double?> onChanged;
  final String label;

  static const step = 2.5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value;

    Widget button(IconData icon, String tip, VoidCallback? onTap) => PressScale(
          scale: PressScale.smallScale,
          child: Semantics(
            button: true,
            label: tip,
            child: Material(
              color: onTap == null ? Colors.transparent : c.sunken,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: onTap == null ? BorderSide(color: c.text.withValues(alpha: 0.08), width: 1) : BorderSide.none,
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                onTap: onTap,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(icon, size: 16, color: onTap == null ? c.text3.withValues(alpha: 0.5) : c.text),
                ),
              ),
            ),
          ),
        );

    Future<void> type() async {
      final r = await showNumberPad(
        context,
        title: label,
        unit: 'kg',
        hint: '单位：公斤；填 0 表示不设',
        initial: v,
        decimal: true,
        steps: const [2.5, 5],
      );
      if (r == null) return;
      onChanged(r <= 0 ? null : r);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body.copyWith(color: c.text))),
          button(
            AppIcons.minus,
            '$label 减少',
            v == null ? null : () => onChanged(v - step <= 0 ? null : v - step),
          ),
          SizedBox(
            width: 84,
            child: InkWell(
              onTap: type,
              child: Center(
                child: Semantics(
                  button: true,
                  label: '$label 输入数值',
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      v == null ? '不设' : '${formatWeight(v)} kg',
                      style: AppText.numMedium.copyWith(color: v == null ? c.text3 : c.text),
                    ),
                  ),
                ),
              ),
            ),
          ),
          button(AppIcons.plus, '$label 增加', v == null ? () => onChanged(step) : (v + step > 1000 ? null : () => onChanged(v + step))),
        ],
      ),
    );
  }
}

/// 页面顶部「计划 / 模板」这类二选一切换。
class SegmentTabs extends StatelessWidget {
  const SegmentTabs({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSegmented<int>(
      values: [for (var i = 0; i < labels.length; i++) i],
      labels: labels,
      selected: index,
      onChanged: onChanged,
    );
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.title, required this.hint, this.icon = AppIcons.navPlan});
  final String title;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Center(child: EmptyState(icon: icon, title: title, hint: hint, compact: true)),
    );
  }
}

/// 模板 / 首页预览页底部、开始按钮上方的一行「预估 38 分钟」。[label] 为空时不占位置。
class EstimateHint extends StatelessWidget {
  const EstimateHint({super.key, required this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label;
    if (text == null) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.timerSmall, size: 14, color: c.text3),
          const SizedBox(width: 6),
          Text(text, style: AppText.label.copyWith(color: c.text2, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
