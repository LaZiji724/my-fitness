import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/stats/muscle_figure_svg.dart';
import 'package:my_fitness/features/stats/stats_math.dart' show kFigureRegions;

String _hex(Color c) {
  String two(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(c.r)}${two(c.g)}${two(c.b)}';
}

/// 肌肉热度示意图（正面或背面）。[weeklySets] 是各分区的每周平均组数，
/// 键见 stats_math.dart 的 kFigureRegions。
class MuscleFigure extends StatelessWidget {
  const MuscleFigure({super.key, required this.front, required this.weeklySets, this.height = 312});

  final bool front;
  final Map<String, double> weeklySets;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var svg = front ? frontFigureTemplate : backFigureTemplate;
    svg = svg.replaceAll('{{stroke}}', _hex(c.surface)).replaceAll('{{body}}', _hex(c.bodyNeutral));
    for (final key in kFigureRegions.keys) {
      svg = svg.replaceAll('{{$key}}', _hex(c.heatFor(weeklySets[key] ?? 0)));
    }
    return SvgPicture.string(svg, height: height, semanticsLabel: front ? '正面肌肉热度图' : '背面肌肉热度图');
  }
}
