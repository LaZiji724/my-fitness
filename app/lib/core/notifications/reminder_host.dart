import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/notifications/reminder_scheduler.dart';
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
class ReminderHost extends ConsumerStatefulWidget {
  const ReminderHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReminderHost> createState() => _ReminderHostState();
}

class _ReminderHostState extends ConsumerState<ReminderHost> with WidgetsBindingObserver {
  bool _background = false;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!_background) {
          _background = true;
          _sync();
        }
      case AppLifecycleState.resumed:
        if (_background) {
          _background = false;
          ref.read(reminderSchedulerProvider).cancelAll();
          ref.read(setTimerProvider.notifier).finishIfDue();
          _sync(); // iOS：还在倒数的要重新登记
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
    final now = ref.read(clockProvider)();
    final scheduler = ref.read(reminderSchedulerProvider);

    void apply(int id, DateTime? endsAt, String title, String body) {
      if (endsAt != null && endsAt.isAfter(now)) {
        scheduler.schedule(id: id, at: endsAt, title: title, body: body);
      } else if (!_background) {
        // 前台：计时已经停止或结束，撤掉之前登记的（后台时不动，免得撤掉已弹出的）
        scheduler.cancel(id);
      }
    }

    final set = ref.read(setTimerProvider);
    apply(kSetTimerReminderId, set?.endsAt, '计时结束',
        set == null ? '' : '${set.label} 完成了，休息一下');
    final rest = ref.read(restTimerProvider);
    apply(kRestReminderId, rest?.endsAt, '休息结束', '该开始下一组了');
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
    });
    ref.listen(restTimerProvider, (prev, next) {
      if (prev == null && next != null) _askPermission();
      _sync();
    });
    return widget.child;
  }
}
