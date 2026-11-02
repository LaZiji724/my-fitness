import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/features/workout/workout_math.dart';

SetEntry s(double w, int r, {String kind = 'normal', bool done = true}) =>
    SetEntry(weightKg: w, reps: r, kind: kind, completed: done);

void main() {
  test('容量只算已完成的非热身组', () {
    final sets = [s(100, 5), s(60, 10, kind: 'warmup'), s(80, 8, done: false), s(90, 6)];
    expect(volumeOf(sets), 100 * 5 + 90 * 6);
    expect(workingSetCount(sets), 2);
  });

  test('自重动作没有重量：容量为 0 但计组数', () {
    final sets = [const SetEntry(reps: 12, completed: true), const SetEntry(reps: 10, completed: true)];
    expect(volumeOf(sets), 0);
    expect(workingSetCount(sets), 2);
  });

  test('Epley 估算 1RM', () {
    expect(estimate1RM(100, 1), 100);
    expect(estimate1RM(100, 5), closeTo(116.67, 0.01));
    expect(estimate1RM(0, 5), 0);
    expect(estimate1RM(80, 0), 0);
  });

  group('PR 判定', () {
    final history = ExerciseBest.of([s(100, 5), s(90, 8)]);

    test('没有历史不算 PR', () {
      expect(detectPr(ExerciseBest.none, s(100, 5)), isEmpty);
    });
    test('重量更大 = 重量 PR', () {
      expect(detectPr(history, s(102.5, 3)), contains(PrKind.weight));
    });
    test('估算 1RM 更高 = 1RM PR', () {
      // 90kg×10 的 1RM = 120 > 历史最高 (100×5=116.67, 90×8=114)
      expect(detectPr(history, s(90, 10)), contains(PrKind.oneRepMax));
    });
    test('没有超过历史不算 PR；热身组与未完成组不算', () {
      expect(detectPr(history, s(80, 5)), isEmpty);
      expect(detectPr(history, s(200, 5, kind: 'warmup')), isEmpty);
      expect(detectPr(history, s(200, 5, done: false)), isEmpty);
    });
    test('自重动作看次数 PR', () {
      final h = ExerciseBest.of([const SetEntry(reps: 10, completed: true)]);
      expect(detectPr(h, const SetEntry(reps: 12, completed: true)), contains(PrKind.reps));
      expect(detectPr(h, const SetEntry(reps: 9, completed: true)), isEmpty);
    });
  });

  test('格式化', () {
    expect(formatWeight(82.5), '82.5');
    expect(formatWeight(80), '80');
    expect(formatWeight(null), '');
    expect(formatDuration(const Duration(minutes: 5, seconds: 7)), '5:07');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}
