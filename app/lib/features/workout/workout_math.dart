/// 训练统计的纯函数，不依赖数据库与界面，方便测试。
/// 口径：只统计「已完成」且「非热身」的组。
library;

class SetEntry {
  const SetEntry({
    this.weightKg,
    this.reps,
    this.kind = 'normal',
    this.completed = false,
  });

  final double? weightKg;
  final int? reps;
  final String kind;
  final bool completed;

  bool get counts => completed && kind != 'warmup';
}

/// 重量(kg) × 次数。自重动作没有重量时按 0 计，但仍计入组数。
double volumeOf(Iterable<SetEntry> sets) => sets
    .where((s) => s.counts)
    .fold(0.0, (sum, s) => sum + (s.weightKg ?? 0) * (s.reps ?? 0));

int workingSetCount(Iterable<SetEntry> sets) => sets.where((s) => s.counts).length;

/// Epley 估算 1RM：重量 × (1 + 次数 ÷ 30)；单次即为重量本身。
double estimate1RM(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return 0;
  if (reps == 1) return weightKg;
  return weightKg * (1 + reps / 30);
}

/// 一个动作的历史最佳。
class ExerciseBest {
  const ExerciseBest({this.maxWeightKg = 0, this.maxReps = 0, this.max1RM = 0});

  final double maxWeightKg;
  final int maxReps;
  final double max1RM;

  static const none = ExerciseBest();

  ExerciseBest including(SetEntry s) {
    if (!s.counts) return this;
    final w = s.weightKg ?? 0;
    final r = s.reps ?? 0;
    return ExerciseBest(
      maxWeightKg: w > maxWeightKg ? w : maxWeightKg,
      maxReps: r > maxReps ? r : maxReps,
      max1RM: estimate1RM(w, r) > max1RM ? estimate1RM(w, r) : max1RM,
    );
  }

  static ExerciseBest of(Iterable<SetEntry> sets) =>
      sets.fold(none, (b, s) => b.including(s));
}

enum PrKind { weight, reps, oneRepMax }

/// 这一组是否打破了历史最佳。没有历史时（第一次练）不算 PR，避免满屏庆祝。
Set<PrKind> detectPr(ExerciseBest history, SetEntry s) {
  if (!s.counts) return const {};
  final hasHistory =
      history.maxWeightKg > 0 || history.maxReps > 0 || history.max1RM > 0;
  if (!hasHistory) return const {};
  final w = s.weightKg ?? 0;
  final r = s.reps ?? 0;
  return {
    if (w > history.maxWeightKg) PrKind.weight,
    // 自重动作（重量为 0）才看次数 PR，否则加重后次数变少会误报
    if (w == 0 && r > history.maxReps) PrKind.reps,
    if (w > 0 && estimate1RM(w, r) > history.max1RM) PrKind.oneRepMax,
  };
}

String formatWeight(double? kg) {
  if (kg == null) return '';
  return kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}
