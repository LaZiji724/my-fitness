import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/library/program.dart';

/// 分类图标。
IconData categoryIcon(String? category) => switch (category) {
      '有氧跟练' => Icons.directions_run_rounded,
      '团课计划' => Icons.groups_rounded,
      '瘦身减脂' => Icons.local_fire_department_rounded,
      '塑形美体' => Icons.accessibility_new_rounded,
      '增肌增重' => Icons.fitness_center_rounded,
      '健康改善' => Icons.health_and_safety_rounded,
      '拉伸放松' => Icons.self_improvement_rounded,
      '激活热身' => Icons.bolt_rounded,
      '丰满翘臀' => Icons.sports_gymnastics_rounded,
      _ => Icons.bolt_rounded,
    };

/// 分类的点缀色（取自部位色，随主题变化）。
Color categoryTint(AppColors c, String category) => switch (category) {
      '有氧跟练' => c.partLegs,
      '团课计划' => c.partShoulders,
      '瘦身减脂' => c.partChest,
      '塑形美体' => c.partArms,
      '增肌增重' => c.partBack,
      '健康改善' => c.success,
      '拉伸放松' => c.info,
      '激活热身' => c.partShoulders,
      _ => c.accent,
    };

/// 「铁与火」风格的计划封面：健身房照片（暖黑白处理）+ 深色渐变 + 大号图标；没有照片时退回到分类色渐变。
class ProgramCover extends StatelessWidget {
  const ProgramCover({
    super.key,
    required this.program,
    required this.child,
    this.height = 148,
    this.radius,
    this.iconSize = 120,
  });

  final Program program;
  final Widget child;
  final double height;
  final BorderRadius? radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = categoryTint(c, program.category);
    return ClipRRect(
      borderRadius: radius ?? AppRadius.card,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(c.hero, tint, 0.34)!, c.hero, Color.lerp(c.hero2, tint, 0.10)!],
                  stops: const [0, 0.62, 1],
                ),
              ),
            ),
            Image.asset(
              'assets/programs/${program.slug}.webp',
              fit: BoxFit.cover,
              cacheWidth: 720,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            // 压暗照片，保证封面上的白字清晰
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(c.hero, tint, 0.20)!.withValues(alpha: 0.45),
                    c.hero.withValues(alpha: 0.86),
                  ],
                ),
              ),
            ),
            Positioned(
              right: -iconSize * 0.12,
              top: -iconSize * 0.08,
              child: Icon(categoryIcon(program.category), size: iconSize, color: tint.withValues(alpha: 0.22)),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

/// 封面上的小标签（「新上线」「推荐」「已加入」）。
class CoverTag extends StatelessWidget {
  const CoverTag(this.label, {super.key, this.filled = false});
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? c.accent : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: filled ? c.onAccent : c.onHero,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String programMetaLine(Program p) => '${p.levelText} · ${p.weeks} 周 · 每周 ${p.daysPerWeek} 练 · 约 ${p.minutes} 分钟';

/// 列表里的计划封面卡。
class ProgramCard extends StatelessWidget {
  const ProgramCard({
    super.key,
    required this.program,
    required this.onTap,
    this.completed = 0,
    this.joined = false,
    this.favorite = false,
  });

  final Program program;
  final VoidCallback onTap;
  final int completed;
  final bool joined;
  final bool favorite;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '${program.name}，${programMetaLine(program)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: onTap,
          child: ProgramCover(
            program: program,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s12, AppSpace.s16, AppSpace.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (program.isNew) ...[const CoverTag('新上线', filled: true), const SizedBox(width: 6)],
                      if (program.featured) ...[const CoverTag('推荐'), const SizedBox(width: 6)],
                      if (joined) const CoverTag('已加入'),
                      const Spacer(),
                      if (favorite) Icon(Icons.star_rounded, size: 20, color: c.accent),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    program.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleMedium.copyWith(color: c.onHero, fontSize: 19),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    program.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label.copyWith(color: c.onHero2),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          programMetaLine(program),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(color: c.onHero2, fontSize: 12),
                        ),
                      ),
                      if (completed > 0)
                        Text('已练 $completed 节', style: AppText.caption.copyWith(color: c.accentText, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 页面里的小标签（器械、场景、人群）。
class InfoPill extends StatelessWidget {
  const InfoPill(this.label, {super.key, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(AppRadius.xs + 4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: c.text2), const SizedBox(width: 4)],
            Text(label, style: AppText.label.copyWith(color: c.text2)),
          ],
        ),
      ),
    );
  }
}

/// 头部的数字指标：「4 周」「每周 3 练」。
class StatBlock extends StatelessWidget {
  const StatBlock({super.key, required this.value, required this.unit, required this.label});
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(
              text: value,
              // 「入门」「进阶」这类文字值用黑体，与数字的视觉高度对齐
              style: _isNumeric(value)
                  ? AppText.numLarge.copyWith(color: c.onHero)
                  : AppText.titleMedium.copyWith(color: c.onHero, height: 1.5),
            ),
            TextSpan(text: ' $unit', style: AppText.caption.copyWith(color: c.onHero2, fontSize: 12)),
          ])),
          Text(label, style: AppText.caption.copyWith(color: c.onHero2)),
        ],
      ),
    );
  }
}

bool _isNumeric(String v) => RegExp(r'^[0-9.\-–+]+$').hasMatch(v);
