import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';

/// 单手输入重量/次数用的数字键盘（底部弹层）。
/// 返回输入的数值；点遮罩关闭返回 null。
Future<double?> showNumberPad(
  BuildContext context, {
  required String title,
  required String unit,
  double? initial,
  bool decimal = false,
  List<double> steps = const [1],
  String hint = '',
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NumberPad(
      title: title,
      unit: unit,
      initial: initial,
      decimal: decimal,
      steps: steps,
      hint: hint,
    ),
  );
}

class _NumberPad extends StatefulWidget {
  const _NumberPad({
    required this.title,
    required this.unit,
    required this.initial,
    required this.decimal,
    required this.steps,
    required this.hint,
  });

  final String title;
  final String unit;
  final double? initial;
  final bool decimal;
  final List<double> steps;
  final String hint;

  @override
  State<_NumberPad> createState() => _NumberPadState();
}

class _NumberPadState extends State<_NumberPad> {
  late String _text;
  bool _fresh = true; // 第一次按数字键时替换原值

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    _text = v == null ? '' : _format(v);
  }

  static String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double get _value => double.tryParse(_text) ?? 0;

  void _key(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        _fresh = false;
        _text = _text.isEmpty ? '' : _text.substring(0, _text.length - 1);
        return;
      }
      if (_fresh) {
        _text = '';
        _fresh = false;
      }
      if (k == '.') {
        if (!widget.decimal || _text.contains('.')) return;
        _text = _text.isEmpty ? '0.' : '$_text.';
        return;
      }
      if (_text == '0') _text = '';
      if (_text.length >= 6) return;
      _text += k;
    });
  }

  void _step(double delta) {
    HapticFeedback.selectionClick();
    setState(() {
      final next = (_value + delta).clamp(0, 9999).toDouble();
      _text = _format(double.parse(next.toStringAsFixed(2)));
      _fresh = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.title, style: AppText.titleSmall.copyWith(color: c.text)),
                Text(widget.hint, style: AppText.label.copyWith(color: c.text3)),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            Row(
              children: [
                for (final s in widget.steps.reversed)
                  _StepButton(label: '−${_format(s)}', onTap: () => _step(-s)),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(_text.isEmpty ? '0' : _text,
                          key: const Key('pad-value'),
                          style: AppText.numLarge.copyWith(
                              color: _text.isEmpty ? c.text3 : c.text, fontSize: 44)),
                      const SizedBox(width: 4),
                      Text(widget.unit, style: AppText.label.copyWith(color: c.text2)),
                    ],
                  ),
                ),
                for (final s in widget.steps)
                  _StepButton(label: '+${_format(s)}', onTap: () => _step(s)),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.3,
              children: [
                for (final k in keys)
                  PressScale(
                    scale: PressScale.chipScale,
                    child: Material(
                      color: c.sunken,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _key(k),
                        child: Center(
                          child: k == '⌫'
                              ? Icon(Icons.backspace_outlined, color: c.text)
                              : Text(k, style: AppText.numMedium.copyWith(color: c.text)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            PressScale(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _value),
                child: const Text('确定'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: PressScale(
        scale: PressScale.chipScale,
        child: Material(
          color: c.sunken,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 44,
              child: Center(child: Text(label, style: AppText.numSmall.copyWith(color: c.text))),
            ),
          ),
        ),
      ),
    );
  }
}
