import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/plan/plan_estimate.dart';

import 'exercises_test.dart' show loadSeed;

TemplateExercise entry(
  String exerciseId, {
  int sets = 3,
  int? repsMin,
  int? repsMax,
  int? rest,
  int warm = 0,
  int? seconds,
}) {
  final now = DateTime(2026, 11, 8);
  return TemplateExercise(
    id: 'te-$exerciseId',
    createdAt: now,
    updatedAt: now,
    dirty: false,
    userId: 'u1',
    templateId: 't1',
    exerciseId: exerciseId,
    position: 0,
    targetSets: sets,
    repsMin: repsMin,
    repsMax: repsMax,
    restSec: rest,
    warmupSets: warm,
    targetDurationSec: seconds,
    section: 'main',
  );
}

void main() {
  final seed = loadSeed();
  final byId = {for (final e in seed) e.id: e};
  final byName = {for (final e in seed) e.nameZh: e};
  Exercise ex(String name) => byName[name]!;

  test('空模板不显示预估', () {
    expect(estimateTemplateSeconds(const [], byId), 0);
    expect(estimateLabel(const [], byId), isNull);
  });

  test('按次数：次数 × 每次秒数 + 准备 + 组间休息，最后一组不再休息', () {
    final bench = ex('杠铃卧推');
    // 3 组 × 10 次 × 4 秒 = 120，+ 3 × 6 准备 = 138，+ 2 次休息 120 = 258，+ 换动作 30（用器械）- 末组休息 60
    final sec = estimateTemplateSeconds([entry(bench.id, repsMin: 10, repsMax: 10, rest: 60)], {bench.id: bench});
    expect(sec, 3 * (10 * 4 + kEstimateSetupSec) + 2 * 60 + kEstimateSwitchEquipmentSec);
  });

  test('按时间：直接用设定的秒数；左右各做的动作翻倍；休息 0 秒就不加', () {
    final stretch = byId.values.firstWhere((e) => e.perSide && e.kind == ExerciseKind.stretch);
    final one = estimateTemplateSeconds(
        [entry(stretch.id, sets: 1, seconds: 40, rest: 0)], {stretch.id: stretch});
    expect(one, 2 * 40 + kEstimateSetupSec + kEstimateSwitchLightSec);
  });

  test('热身组算轻一点，并加进总时长', () {
    final squat = ex('杠铃深蹲');
    final noWarm = estimateTemplateSeconds([entry(squat.id, repsMin: 8, repsMax: 8, rest: 90)], {squat.id: squat});
    final warm = estimateTemplateSeconds([entry(squat.id, repsMin: 8, repsMax: 8, rest: 90, warm: 2)], {squat.id: squat});
    expect(warm, greaterThan(noWarm));
    expect(warm - noWarm, 2 * (kEstimateWarmupReps * 4 + kEstimateSetupSec + kEstimateWarmupRestMaxSec));
  });

  test('没填次数、没填休息时用默认值，组数越多时间越长', () {
    final curl = ex('哑铃交替弯举');
    final three = estimateTemplateSeconds([entry(curl.id)], {curl.id: curl});
    final four = estimateTemplateSeconds([entry(curl.id, sets: 4)], {curl.id: curl});
    expect(three, greaterThan(0));
    expect(four, greaterThan(three));
  });

  test('「臂」模板大约半小时（实际训练记录是 31 分钟左右）', () {
    final list = [
      entry(ex('手腕绕环').id, sets: 1, seconds: 30, rest: 30),
      entry(ex('窄距俯卧撑').id, repsMin: 10, repsMax: 12, rest: 60),
      entry(ex('哑铃交替弯举').id, repsMin: 12, repsMax: 15, rest: 60),
      entry(ex('交替锤式弯举').id, repsMin: 12, repsMax: 15, rest: 60),
      entry(ex('俯卧撑').id, repsMin: 12, repsMax: 15, rest: 90),
      entry(ex('门框胸部拉伸').id, sets: 1, seconds: 40, rest: 0),
    ];
    final minutes = estimateTemplateMinutes(list, byId);
    expect(minutes, inInclusiveRange(25, 35));
    expect(estimateLabel(list, byId), '预估 $minutes 分钟');
  });
}
