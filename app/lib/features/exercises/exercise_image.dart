import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';

/// 动作图：读 App 内置图片，缺图时显示占位。
class ExerciseImage extends StatelessWidget {
  const ExerciseImage({
    super.key,
    required this.exercise,
    this.index = 0,
    this.radius = AppRadius.md,
    this.cacheWidth = 480,
    this.mono = true,
  });

  final Exercise exercise;
  final int index;
  final double radius;
  final int cacheWidth;

  /// 列表和小图统一成黑白，和界面的墨色一个调子；动作详情的大图保留原色。
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: exercise.imageRatio,
        child: Image.asset(
          exercise.imageAsset(index),
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          semanticLabel: exercise.nameZh,
          color: mono ? const Color(0xFF808080) : null,
          colorBlendMode: mono ? BlendMode.saturation : null,
          errorBuilder: (_, _, _) => ColoredBox(
            color: c.sunken,
            child: Icon(AppIcons.barbell, color: c.text3),
          ),
        ),
      ),
    );
  }
}
