import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/library/program.dart';

/// 分类图标。
IconData categoryIcon(String? category) => switch (category) {
      '有氧跟练' => AppIcons.catCardio,
      '团课计划' => AppIcons.catGroup,
      '瘦身减脂' => AppIcons.catFatLoss,
      '塑形美体' => AppIcons.catShape,
      '增肌增重' => AppIcons.catMuscle,
      '健康改善' => AppIcons.catRehab,
      '拉伸放松' => AppIcons.catStretch,
      '激活热身' => AppIcons.catPower,
      '丰满翘臀' => AppIcons.catShape,
      _ => AppIcons.catPower,
    };

/// 计划封面：黑白处理的健身房照片 + 自上而下压暗的墨色渐变；没有照片时是墨色底加滚花纹。
/// 封面上不放颜色，颜色只留给「新上线」标签。
class ProgramCover extends StatelessWidget {
  const ProgramCover({
    super.key,
    required this.program,
    required this.child,
    this.height = 152,
    this.radius,
  });

  final Program program;
  final Widget child;
  final double height;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: radius ?? AppRadius.card,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: c.hero, child: CustomPaint(painter: KnurlPainter(color: c.onHero))),
            Image.asset(
              'assets/programs/${program.slug}.webp',
              fit: BoxFit.cover,
              cacheWidth: 720,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              color: const Color(0xFF808080),
              colorBlendMode: BlendMode.saturation,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            // 压暗照片，保证封面上的白字清晰
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [const Color(0xFF0B0B0C).withValues(alpha: 0.35), const Color(0xFF0B0B0C).withValues(alpha: 0.88)],
                ),
              ),
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
        color: filled ? c.accent : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: filled ? c.onAccent : c.onHero,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

String programMetaLine(Program p) => metaLine([p.levelText, '${p.weeks} 周', '每周 ${p.daysPerWeek} 练', '约 ${p.minutes} 分钟']);

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
    return PressScale(
      scale: PressScale.cardScale,
      child: Semantics(
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
                padding: const EdgeInsets.all(AppSpace.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (program.isNew) ...[const CoverTag('新上线', filled: true), const SizedBox(width: 8)],
                        if (program.featured) ...[const CoverTag('推荐'), const SizedBox(width: 8)],
                        if (joined) const CoverTag('已加入'),
                        const Spacer(),
                        if (favorite) Icon(AppIcons.starOn, size: 18, color: c.onHero),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      program.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.titleMedium.copyWith(color: c.onHero),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      program.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(color: c.onHero2),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            programMetaLine(program),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(color: c.onHero2),
                          ),
                        ),
                        if (completed > 0)
                          Text('已练 $completed 节', style: AppText.caption.copyWith(color: c.accent, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
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
    return AppTag(label, icon: icon);
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
          Text(label, style: AppText.caption.copyWith(color: c.onHero2)),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: [
            TextSpan(
              text: value,
              // 「入门」「进阶」这类文字值用黑体，与数字的视觉高度对齐
              style: _isNumeric(value)
                  ? AppText.numMedium.copyWith(color: c.onHero)
                  : AppText.titleMedium.copyWith(color: c.onHero, height: 1.45),
            ),
            TextSpan(text: ' $unit', style: AppText.caption.copyWith(color: c.onHero2)),
          ])),
        ],
      ),
    );
  }
}

bool _isNumeric(String v) => RegExp(r'^[0-9.\-–+]+$').hasMatch(v);
