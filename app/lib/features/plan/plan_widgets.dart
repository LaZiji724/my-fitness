import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';

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
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        PressScale(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))),
        PressScale(child: TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: Text(widget.confirm))),
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
    return AlertDialog(
      title: const Text('新建计划'),
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
        PressScale(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))),
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context, (name: _controller.text, days: _days)),
            child: const Text('创建'),
          ),
        ),
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
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        PressScale(child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消'))),
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            // 删除类操作用警示红，避免和普通确认混淆
            style: confirm.contains('删除') ? TextButton.styleFrom(foregroundColor: ctx.colors.danger) : null,
            child: Text(confirm),
          ),
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
              color: c.sunken,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(icon, color: onTap == null ? c.text3 : c.text),
                ),
              ),
            ),
          ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body.copyWith(color: c.text))),
          button(Icons.remove_rounded, '$label 减少', value - step < min ? null : () => onChanged(value - step)),
          SizedBox(
            width: 84,
            child: Center(
              child: Text('$value$unit', style: AppText.numMedium.copyWith(color: c.text)),
            ),
          ),
          button(Icons.add_rounded, '$label 增加', value + step > max ? null : () => onChanged(value + step)),
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
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: PressScale(
                  scale: PressScale.chipScale,
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: AnimatedContainer(
                        duration: AppMotion.fast,
                        height: AppSize.segmented - 8,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == index ? c.raised : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.md - 3),
                        ),
                        child: Text(
                          labels[i],
                          style: AppText.body.copyWith(
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
      ),
    );
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s24, horizontal: AppSpace.s16),
        child: Center(
          child: Column(
            children: [
              Text(title, style: AppText.titleSmall.copyWith(color: c.text)),
              const SizedBox(height: AppSpace.s4),
              Text(hint, textAlign: TextAlign.center, style: AppText.label.copyWith(color: c.text2)),
            ],
          ),
        ),
      ),
    );
  }
}
