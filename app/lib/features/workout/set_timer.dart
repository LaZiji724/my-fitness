import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/features/workout/workout_providers.dart';

/// 一个正在倒数的「按时间计时的组」。只存结束时刻，界面自行刷新，
/// 所以退到后台再回来时间也是准的。
class SetTimerState {
  const SetTimerState({
    required this.setId,
    required this.label,
    required this.totalSec,
    required this.endsAt,
    required this.restSec,
  });

  final String setId;

  /// 用于通知文字，例如「平板支撑 第 2 组」。
  final String label;
  final int totalSec;
  final DateTime endsAt;

  /// 这一组结束后接着开始的组间休息秒数。
  final int restSec;

  int remainingSec(DateTime now) {
    final ms = endsAt.difference(now).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }
}

/// 动作计时：点「开始」后固定时长倒数，归零自动把这一组打勾并开始组间休息。
/// 同一时间只跑一个。
class SetTimerNotifier extends Notifier<SetTimerState?> {
  Timer? _timer;
  bool _finishing = false;

  @override
  SetTimerState? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  DateTime _now() => ref.read(clockProvider)();

  void start({
    required String setId,
    required String label,
    required int seconds,
    required int restSec,
  }) {
    _timer?.cancel();
    // 开始新的一组了，上一组的休息就不用再等
    ref.read(restTimerProvider.notifier).skip();
    state = SetTimerState(
      setId: setId,
      label: label,
      totalSec: seconds,
      endsAt: _now().add(Duration(seconds: seconds)),
      restSec: restSec,
    );
    _arm();
  }

  /// 停止计时（不打勾）。传 [setId] 时只停这一组的。
  void cancel({String? setId}) {
    final s = state;
    if (s == null || (setId != null && s.setId != setId)) return;
    _timer?.cancel();
    state = null;
  }

  void _arm() {
    _timer?.cancel();
    final s = state;
    if (s == null) return;
    final left = s.endsAt.difference(_now());
    _timer = Timer(left.isNegative ? Duration.zero : left, finishIfDue);
  }

  /// 到点了就把这一组打勾并开始休息；没到点就重新排期。
  /// 从后台回到前台时也会调用，补上后台期间错过的结束。
  Future<void> finishIfDue() async {
    final s = state;
    if (s == null || _finishing) return;
    if (s.endsAt.isAfter(_now())) {
      _arm();
      return;
    }
    _finishing = true;
    try {
      _timer?.cancel();
      HapticFeedback.vibrate();
      await ref.read(workoutRepositoryProvider).setCompleted(s.setId, true);
      // 休息从倒数结束的那一刻算起，哪怕是后台回来才处理的
      ref.read(restTimerProvider.notifier).start(s.restSec, now: s.endsAt);
      if (state?.setId == s.setId) state = null;
    } finally {
      _finishing = false;
    }
  }
}

final setTimerProvider =
    NotifierProvider<SetTimerNotifier, SetTimerState?>(SetTimerNotifier.new);
