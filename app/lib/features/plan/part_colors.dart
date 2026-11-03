import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';

/// 日历圆点、分布图用的部位色。
Color partColor(AppColors c, BodyPart p) => switch (p) {
      BodyPart.chest => c.partChest,
      BodyPart.back => c.partBack,
      BodyPart.legs || BodyPart.glutes => c.partLegs,
      BodyPart.shoulders => c.partShoulders,
      BodyPart.arms => c.partArms,
      BodyPart.core || BodyPart.cardio || BodyPart.other => c.partCore,
    };

/// 日历图例里的分组名。
String partGroupLabel(BodyPart p) => switch (p) {
      BodyPart.chest => '胸',
      BodyPart.back => '背',
      BodyPart.legs || BodyPart.glutes => '腿臀',
      BodyPart.shoulders => '肩',
      BodyPart.arms => '手臂',
      BodyPart.core || BodyPart.cardio || BodyPart.other => '核心',
    };

/// 日历标签可轮换的六种部位色（和日历圆点同一套）。
const _tagPalette = [
  BodyPart.chest,
  BodyPart.back,
  BodyPart.legs,
  BodyPart.shoulders,
  BodyPart.arms,
  BodyPart.core,
];

BodyPart _group(BodyPart p) => switch (p) {
      BodyPart.glutes => BodyPart.legs,
      BodyPart.cardio || BodyPart.other => BodyPart.core,
      _ => p,
    };

/// 模板里正式训练动作最多的部位（没有正式训练就看全部动作；空模板为 null）。
BodyPart? dominantPart(TemplateView t, Map<String, Exercise> byId) {
  var items = t.exercises.where((e) => e.section == 'main').toList();
  if (items.isEmpty) items = t.exercises;
  final counts = <BodyPart, int>{};
  for (final e in items) {
    final ex = byId[e.exerciseId];
    if (ex != null) counts.update(_group(ex.bodyPart), (v) => v + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return null;
  // 并列时按调色板顺序取，结果稳定
  return _tagPalette.where(counts.containsKey).reduce((a, b) => counts[b]! > counts[a]! ? b : a);
}

/// 给计划里出现的每个模板分一个标签色（按出现顺序）。
/// 先用模板主练部位的颜色；已被前一个模板用掉就换下一种没用过的，这样标签之间尽量不撞色。
Map<String, BodyPart> templateTagParts(Iterable<TemplateView> ordered, Map<String, Exercise> byId) {
  final result = <String, BodyPart>{};
  final used = <BodyPart>{};
  for (final t in ordered) {
    if (result.containsKey(t.template.id)) continue;
    var pick = dominantPart(t, byId) ?? _tagPalette.first;
    if (used.contains(pick)) {
      pick = _tagPalette.firstWhere((p) => !used.contains(p), orElse: () => pick);
    }
    used.add(pick);
    result[t.template.id] = pick;
  }
  return result;
}

/// 日历标签：文字是模板名，颜色来自 [templateTagParts]。
class PlanTag {
  const PlanTag(this.id, this.name, this.part);
  final String id;
  final String name;
  final BodyPart part;
}

/// 当前计划一个循环里出现的模板，按第 1 天、第 2 天……的顺序，每个只出现一次。没有当前计划时为空。
List<PlanTag> planTags(List<PlanView> plans, List<TemplateView> templates, Map<String, Exercise> byId) {
  final active = plans.where((p) => p.plan.isActive).firstOrNull;
  if (active == null) return const [];
  final ordered = <TemplateView>[];
  for (final d in active.days) {
    final tid = d?.templateId;
    if (tid == null) continue;
    final t = templates.where((t) => t.template.id == tid).firstOrNull;
    if (t != null && !ordered.any((o) => o.template.id == tid)) ordered.add(t);
  }
  final parts = templateTagParts(ordered, byId);
  return [for (final t in ordered) PlanTag(t.template.id, t.template.name, parts[t.template.id]!)];
}
