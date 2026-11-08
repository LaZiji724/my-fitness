/// 模板「预估总时长」：把每个动作的做组时间、组间休息、换动作的准备时间加起来。
///
/// 纯函数，不依赖界面。数字是经验估计，不求精确，目的是让人心里有数。
library;

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';

/// 没填次数时，按这个次数算。
const int kEstimateDefaultReps = 10;

/// 没填秒数的按时间动作，按这个秒数算。
const int kEstimateDefaultSeconds = 30;

/// 每组开始前的准备（摆好姿势、拿起器械）。
const int kEstimateSetupSec = 6;

/// 没填休息时间时按这个算，和训练页的默认值一致。
const int kEstimateDefaultRestSec = 90;

/// 热身组比正式组轻：次数按这个数算，休息最多算这么久。
const int kEstimateWarmupReps = 8;
const int kEstimateWarmupRestMaxSec = 45;

/// 换到下一个动作的准备时间：用器械的力量动作要走过去、调重量，徒手和拉伸动作很快。
const int kEstimateSwitchEquipmentSec = 30;
const int kEstimateSwitchLightSec = 10;

/// 一次动作大约花几秒（含上下两个方向和控制节奏）。
///
/// 大肌群的复合动作慢一些（深蹲、划船、卧推约 4 秒），
/// 手臂、肩、腹的单关节动作约 3.5 秒，热身激活动作约 3 秒，
/// 改成按次数的拉伸 / 泡沫轴动作每次要停一下，约 5 秒。
double secondsPerRep(Exercise? ex) {
  if (ex == null) return 4;
  switch (ex.kind) {
    case ExerciseKind.activation:
    case ExerciseKind.dynamicWarmup:
      return 3;
    case ExerciseKind.stretch:
    case ExerciseKind.foam:
      return 5;
    case ExerciseKind.cardio:
      return 2;
    case ExerciseKind.strength:
      switch (ex.bodyPart) {
        case BodyPart.arms:
        case BodyPart.shoulders:
        case BodyPart.core:
          return 3.5;
        case BodyPart.cardio:
          return 2;
        default:
          return 4;
      }
  }
}

bool _usesEquipment(Exercise? ex) {
  if (ex == null) return false;
  if (ex.kind != ExerciseKind.strength) return false;
  return EquipmentGroup.of(ex.equipment) != EquipmentGroup.bodyweight && ex.equipment != null;
}

/// 一组正式组大约花多少秒（不含休息）。
int _workSetSeconds(TemplateExercise e, Exercise? ex) {
  final timed = e.targetDurationSec != null || (ex?.isTimed ?? false);
  final double sec;
  if (timed) {
    sec = (e.targetDurationSec ?? ex?.defaultSeconds ?? kEstimateDefaultSeconds).toDouble();
  } else {
    final lo = e.repsMin ?? ex?.defaultReps;
    final hi = e.repsMax ?? lo;
    final reps = lo == null ? kEstimateDefaultReps : (lo + (hi ?? lo)) / 2;
    sec = reps * secondsPerRep(ex);
  }
  // 左右各做一次的动作，运动量是每一侧的
  final sides = (ex?.perSide ?? false) ? 2 : 1;
  return (sec * sides).round() + kEstimateSetupSec;
}

int _warmupSetSeconds(Exercise? ex) {
  final sides = (ex?.perSide ?? false) ? 2 : 1;
  return (kEstimateWarmupReps * secondsPerRep(ex) * sides).round() + kEstimateSetupSec;
}

/// 整个模板大约要练多少秒。动作列表为空返回 0。
int estimateTemplateSeconds(Iterable<TemplateExercise> entries, Map<String, Exercise> byId) {
  var total = 0;
  var lastRest = 0;
  var any = false;
  for (final e in entries) {
    final ex = byId[e.exerciseId];
    final rest = e.restSec ?? kEstimateDefaultRestSec;
    final warm = e.warmupSets < 0 ? 0 : e.warmupSets;
    final sets = e.targetSets < 0 ? 0 : e.targetSets;
    if (sets + warm == 0) continue;

    total += warm * (_warmupSetSeconds(ex) + (rest < kEstimateWarmupRestMaxSec ? rest : kEstimateWarmupRestMaxSec));
    total += sets * (_workSetSeconds(e, ex) + rest);
    total += _usesEquipment(ex) ? kEstimateSwitchEquipmentSec : kEstimateSwitchLightSec;
    lastRest = rest;
    any = true;
  }
  // 整场最后一组做完不用再休息
  return any ? total - lastRest : 0;
}

/// 预估分钟数，四舍五入，有动作时至少 1 分钟。
int estimateTemplateMinutes(Iterable<TemplateExercise> entries, Map<String, Exercise> byId) {
  final sec = estimateTemplateSeconds(entries, byId);
  if (sec <= 0) return 0;
  final m = (sec / 60).round();
  return m < 1 ? 1 : m;
}

/// 界面上显示的文字，例如「预估 38 分钟」；没有动作时返回 null（不显示）。
String? estimateLabel(Iterable<TemplateExercise> entries, Map<String, Exercise> byId) {
  final m = estimateTemplateMinutes(entries, byId);
  return m <= 0 ? null : '预估 $m 分钟';
}
