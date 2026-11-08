import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show UpdateKind, Variable;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/app/router.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/features/workout/set_timer.dart';
import 'package:my_fitness/features/workout/workout_providers.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

/// 忘记点「结束」时自动收尾（界面上没有任何设置，悄悄生效）。
///
/// - 所有动作都做完（含最后一组的休息结束）后，1 分钟没有任何操作 → 自动保存并结束；
/// - 还有动作没做完，2 分钟没有任何操作 → 同样自动结束；
/// - 一组都还没完成时放宽到 10 分钟（刚到健身房、在换衣服，不该被丢掉）。
/// 结束时刻记在「最后一次操作 / 最后一次休息结束」那一刻，多出来的空闲时间不计入时长。
const Duration kIdleAfterAllDone = Duration(minutes: 1);
const Duration kIdleUnfinished = Duration(minutes: 2);
const Duration kIdleNothingDone = Duration(minutes: 10);

/// 这次训练的空闲上限。
Duration idleLimitFor(WorkoutView view) {
  final sets = view.exercises.expand((b) => b.sets).toList();
  if (!sets.any((s) => s.completed)) return kIdleNothingDone;
  return sets.every((s) => s.completed) ? kIdleAfterAllDone : kIdleUnfinished;
}

/// 训练里数据库记录到的最近一次改动时间。
DateTime lastDbActivity(WorkoutView view) {
  var t = view.workout.updatedAt;
  for (final b in view.exercises) {
    if (b.exercise.updatedAt.isAfter(t)) t = b.exercise.updatedAt;
    for (final s in b.sets) {
      if (s.updatedAt.isAfter(t)) t = s.updatedAt;
      final c = s.completedAt;
      if (c != null && c.isAfter(t)) t = c;
    }
  }
  return t;
}

/// 该不该自动结束？该则返回应当记下的结束时刻，否则返回 null。
///
/// [lastTouch] 是最后一次点屏幕的时间；[holdUntil] 是仍在倒数的休息 / 动作计时的结束时刻
/// （计时没走完时不算空闲，走完那一刻起才开始计空闲）。
DateTime? autoEndAt({
  required WorkoutView view,
  required DateTime now,
  DateTime? lastTouch,
  DateTime? holdUntil,
}) {
  var idleStart = lastDbActivity(view);
  if (lastTouch != null && lastTouch.isAfter(idleStart)) idleStart = lastTouch;
  if (holdUntil != null && holdUntil.isAfter(idleStart)) idleStart = holdUntil;
  if (idleStart.isAfter(now)) return null; // 计时还没走完，或时钟被调过
  if (now.difference(idleStart) < idleLimitFor(view)) return null;
  final start = view.workout.startedAt;
  return idleStart.isBefore(start) ? start : idleStart;
}

/// 把「最后一次操作」存在本机，应用被系统杀掉后重新打开仍能按它结算。不上传。
class WorkoutActivityStore {
  WorkoutActivityStore(this._db);
  final AppDatabase _db;

  static String keyFor(String workoutId) => 'auto_end:$workoutId';

  Future<({DateTime? touch, DateTime? hold})> load(String workoutId) async {
    final rows = await _db
        .customSelect('SELECT value FROM sync_states WHERE key = ?',
            variables: [Variable<String>(keyFor(workoutId))], readsFrom: {_db.syncStates})
        .get();
    if (rows.isEmpty) return (touch: null, hold: null);
    try {
      final m = jsonDecode(rows.first.read<String>('value')) as Map<String, dynamic>;
      DateTime? at(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
      return (touch: at(m['t']), hold: at(m['h']));
    } catch (_) {
      return (touch: null, hold: null);
    }
  }

  Future<void> save(String workoutId, {DateTime? touch, DateTime? hold}) => _db.customInsert(
        'INSERT OR REPLACE INTO sync_states (key, value) VALUES (?, ?)',
        variables: [
          Variable<String>(keyFor(workoutId)),
          Variable<String>(jsonEncode({
            't': touch?.millisecondsSinceEpoch,
            'h': hold?.millisecondsSinceEpoch,
          })),
        ],
        updates: {_db.syncStates},
      );

  Future<void> clear(String workoutId) => _db.customUpdate(
        'DELETE FROM sync_states WHERE key = ?',
        variables: [Variable<String>(keyFor(workoutId))],
        updates: {_db.syncStates},
        updateKind: UpdateKind.delete,
      );
}

final workoutActivityStoreProvider =
    Provider<WorkoutActivityStore>((ref) => WorkoutActivityStore(ref.watch(appDatabaseProvider)));

/// 包在整个应用外面：记录最后一次操作，定时检查，并在回到前台 / 重新打开时补做检查。
class AutoEndHost extends ConsumerStatefulWidget {
  const AutoEndHost({super.key, required this.child, this.checkEvery = const Duration(seconds: 5)});
  final Widget child;
  final Duration checkEvery;

  @override
  ConsumerState<AutoEndHost> createState() => _AutoEndHostState();
}

class _AutoEndHostState extends ConsumerState<AutoEndHost> with WidgetsBindingObserver {
  Timer? _timer;
  String? _workoutId; // 当前跟踪的进行中训练
  DateTime? _touch;
  DateTime? _hold;
  bool _dirty = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.checkEvery, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _flush();
      case AppLifecycleState.resumed:
        _check();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  DateTime _now() => ref.read(clockProvider)();

  /// 仍在倒数的休息 / 动作计时的结束时刻（都没有则为 null）。
  DateTime? _timersEnd() {
    final rest = ref.read(restTimerProvider)?.endsAt;
    final set = ref.read(setTimerProvider)?.endsAt;
    if (rest == null) return set;
    if (set == null) return rest;
    return rest.isAfter(set) ? rest : set;
  }

  void _onTouch() {
    if (_workoutId == null) return;
    _touch = _now();
    _dirty = true;
  }

  void _onTimersChanged() {
    if (_workoutId == null) return;
    _hold = _timersEnd();
    _touch = _now(); // 点了完成 / 跳过 / 加减休息，本身就是一次操作
    _dirty = true;
    _flush();
  }

  Future<void> _flush() async {
    final id = _workoutId;
    if (id == null || !_dirty) return;
    _dirty = false;
    try {
      await ref.read(workoutActivityStoreProvider).save(id, touch: _touch, hold: _hold);
    } catch (_) {
      _dirty = true;
    }
  }

  /// 切到另一次训练（或没有训练）时，读回上次记下的最后操作时间。
  Future<void> _track(String? id) async {
    _workoutId = id;
    _touch = null;
    _hold = null;
    _dirty = false;
    if (id == null) return;
    try {
      final saved = await ref.read(workoutActivityStoreProvider).load(id);
      if (_workoutId != id) return;
      _touch = saved.touch;
      _hold = _timersEnd() ?? saved.hold;
    } catch (_) {}
    _check();
  }

  Future<void> _tick() async {
    final id = ref.read(activeWorkoutProvider).value?.workout.id;
    if (id != _workoutId) {
      await _track(id);
      return;
    }
    await _flush();
    await _check();
  }

  Future<void> _check() async {
    if (_busy || !mounted) return;
    final view = ref.read(activeWorkoutProvider).value;
    if (view == null || view.workout.id != _workoutId) return;
    final end = autoEndAt(view: view, now: _now(), lastTouch: _touch, holdUntil: _hold ?? _timersEnd());
    if (end == null) return;

    _busy = true;
    final id = view.workout.id;
    _workoutId = null; // 先停止记录，免得下面取消计时又把旧记录写回去
    try {
      final router = ref.read(routerProvider);
      final onWorkoutPage = router.routerDelegate.currentConfiguration.uri.path.startsWith('/workout');
      ref.read(restTimerProvider.notifier).skip();
      ref.read(setTimerProvider.notifier).cancel();
      final summary = await ref.read(workoutRepositoryProvider).finishWorkout(id, endedAt: end, auto: true);
      await ref.read(workoutActivityStoreProvider).clear(id);
      if (onWorkoutPage && mounted) {
        if (summary == null) {
          router.go('/today');
        } else {
          router.go('/workout/summary', extra: summary);
        }
      }
    } catch (_) {
      // 这次没成功，下次检查再试
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = ref.watch(activeWorkoutProvider).value?.workout.id;
    if (id != _workoutId) {
      scheduleMicrotask(() {
        if (mounted && id != _workoutId && ref.read(activeWorkoutProvider).value?.workout.id == id) _track(id);
      });
    }
    ref.listen(restTimerProvider, (_, _) => _onTimersChanged());
    ref.listen(setTimerProvider, (_, _) => _onTimersChanged());
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onTouch(),
      child: widget.child,
    );
  }
}
