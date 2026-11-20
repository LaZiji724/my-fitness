import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/notifications/reminder_scheduler.dart';
import 'package:my_fitness/core/notifications/rest_bell.dart';
import 'package:my_fitness/features/workout/set_timer.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';

/// 把「动作计时」「组间休息」和系统通知接起来，包在整个应用外面。
///
/// 规则：应用在前台时一律不弹通知（界面里自己有读秒和震动）；
/// 退到后台或熄屏后，时间到了手机会准时弹窗，即使应用被系统冻结。
/// - 安卓：退到后台那一刻才把还在倒数的计时登记成定时通知，回前台就取消。
/// - iOS：一开始倒数就登记（通知自带「前台不显示」），不依赖退后台那一瞬间
///   能不能来得及登记；停止/结束/跳过时取消。
/// 回到前台时还会补上后台期间已经结束的动作计时。
///
/// 组间休息结束、动作计时（按时间记的动作）结束，都一定响铃（同一个铃声）：
/// - 应用在前台（在哪个页面都一样）：应用自己用「媒体」通道放铃声（安卓、iPhone 一样）：
///   音量跟媒体音量，静音也能听到，比平时小一点点；正在放的音乐只会被压低，不会被打断。
///   iPhone 提前登记的通知在前台不出声，免得响两遍。
/// - 退到后台或熄屏：到点弹出的通知自带同一个铃声（安卓用媒体用途的渠道；
///   iPhone 的通知声音由系统控制，会受静音开关影响）。
class ReminderHost extends ConsumerStatefulWidget {
  const ReminderHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReminderHost> createState() => _ReminderHostState();
}

class _ReminderHostState extends ConsumerState<ReminderHost> with WidgetsBindingObserver {
  bool _background = false;
  bool _asked = false;
  Timer? _bellTimer;
  DateTime? _rungFor; // 已经响过铃的那次休息（按结束时刻区分），免得重复响
  Timer? _setBellTimer;
  DateTime? _setBellEndsAt; // 当前给哪一次动作计时定了铃
  DateTime? _setRungFor; // 已经响过铃的那次动作计时

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _bellTimer?.cancel();
    _setBellTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime _now() => ref.read(clockProvider)();

  /// 应用在前台时，按当前休息的结束时刻定一个闹钟，到点响铃。
  /// 已经过了结束时刻的不补响（多半是在后台结束的，通知已经响过了）。
  void _armBell() {
    _bellTimer?.cancel();
    _bellTimer = null;
    final rest = ref.read(restTimerProvider);
    if (_background || rest == null || _rungFor == rest.endsAt) return;
    if (!ref.read(restBellProvider).ringsInApp) return;
    final left = rest.endsAt.difference(_now());
    if (left.isNegative) return;
    _bellTimer = Timer(left, _ringIfDue);
  }

  void _ringIfDue() {
    final rest = ref.read(restTimerProvider);
    if (!mounted || _background || rest == null || _rungFor == rest.endsAt) return;
    if (rest.endsAt.isAfter(_now())) {
      _armBell(); // 休息被加时了，重新定
      return;
    }
    _rungFor = rest.endsAt;
    ref.read(restBellProvider).ring();
  }

  /// 动作计时（按时间记的动作）：应用在前台时，到点响铃。
  /// 计时到点后状态会立刻被清掉（这一组打勾、转入休息），所以铃声按定闹钟时记下的结束时刻来响，
  /// 不再回头看状态；只有计时被手动停止（还没到点）才取消。
  void _armSetBell() {
    final set = ref.read(setTimerProvider);
    if (set == null) {
      final ends = _setBellEndsAt;
      // 没到点就没了 = 手动停止，不响；到点时留给已经定好的闹钟去响
      if (ends != null && ends.isAfter(_now())) _cancelSetBell();
      return;
    }
    if (_setBellEndsAt == set.endsAt) return;
    _cancelSetBell();
    if (_background || _setRungFor == set.endsAt) return;
    if (!ref.read(restBellProvider).ringsInApp) return;
    final left = set.endsAt.difference(_now());
    if (left.isNegative) return;
    _setBellEndsAt = set.endsAt;
    _setBellTimer = Timer(left, () => _ringSetIfDue(set.endsAt));
  }

  void _cancelSetBell() {
    _setBellTimer?.cancel();
    _setBellTimer = null;
    _setBellEndsAt = null;
  }

  void _ringSetIfDue(DateTime endsAt) {
    if (!mounted || _background || _setBellEndsAt != endsAt || _setRungFor == endsAt) return;
    if (endsAt.isAfter(_now())) {
      _setBellTimer = Timer(endsAt.difference(_now()), () => _ringSetIfDue(endsAt));
      return;
    }
    _setRungFor = endsAt;
    _setBellEndsAt = null;
    _setBellTimer = null;
    ref.read(restBellProvider).ring();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!_background) {
          _background = true;
          _bellTimer?.cancel(); // 后台交给带铃声的通知
          _cancelSetBell();
          _sync();
        }
      case AppLifecycleState.resumed:
        if (_background) {
          _background = false;
          ref.read(reminderSchedulerProvider).cancelAll();
          ref.read(setTimerProvider.notifier).finishIfDue();
          _sync(); // iOS：还在倒数的要重新登记
          _armBell();
          _armSetBell();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// 登记提醒。已经结束的不用管（通知已经发出，不要再去撤销它）。
  void _sync() {
    final eager = defaultTargetPlatform == TargetPlatform.iOS;
    if (!_background && !eager) return;
    final now = _now();
    final scheduler = ref.read(reminderSchedulerProvider);

    void apply(int id, DateTime? endsAt, String title, String body, {bool bell = false}) {
      if (endsAt != null && endsAt.isAfter(now)) {
        scheduler.schedule(id: id, at: endsAt, title: title, body: body, bell: bell);
      } else if (!_background) {
        // 前台：计时已经停止或结束，撤掉之前登记的（后台时不动，免得撤掉已弹出的）
        scheduler.cancel(id);
      }
    }

    final set = ref.read(setTimerProvider);
    apply(kSetTimerReminderId, set?.endsAt, '计时结束',
        set == null ? '' : '${set.label} 完成了，休息一下',
        bell: true);
    final rest = ref.read(restTimerProvider);
    apply(kRestReminderId, rest?.endsAt, '休息结束', '该开始下一组了', bell: true);
  }

  /// 第一次开始计时时问一次通知权限；被拒绝则记下来，训练页给出提示。
  Future<void> _askPermission() async {
    if (_asked) return;
    _asked = true;
    final granted = await ref.read(reminderSchedulerProvider).requestPermission();
    if (!mounted) return;
    ref.read(reminderPermissionProvider.notifier).set(granted);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(setTimerProvider, (prev, next) {
      if (prev == null && next != null) _askPermission();
      _sync();
      _armSetBell();
    });
    ref.listen(restTimerProvider, (prev, next) {
      if (prev == null && next != null) _askPermission();
      _sync();
      _armBell();
    });
    return widget.child;
  }
}
