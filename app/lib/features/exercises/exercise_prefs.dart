// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/core/db/database_provider.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/exercises/exercise.dart';

/// 每个动作的「按次数 / 按时间」偏好。只存和默认不一样的那些；改回默认就软删除这一行。
class ExercisePrefsRepository {
  ExercisePrefsRepository(
    this._db, {
    required String Function() userId,
    DateTime Function()? now,
  })  : _userId = userId,
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final String Function() _userId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  /// id 由「用户 + 动作」决定：多台设备给同一个动作设置偏好也只会有一行。
  String prefId(String exerciseId) =>
      _uuid.v5(Namespace.url.value, 'my-fitness/exercise-pref/${_userId()}/$exerciseId');

  Stream<Map<String, TrackingType>> watchAll() {
    final q = _db.select(_db.exercisePrefs)
      ..where((p) => p.deletedAt.isNull() & p.userId.equals(_userId()));
    return q.watch().map((rows) => {
          for (final r in rows) r.exerciseId: TrackingType.fromKey(r.trackingType),
        });
  }

  /// 设置某个动作的记录方式。[tracking] 等于动作默认值时清除偏好。
  Future<void> setTracking(Exercise exercise, TrackingType tracking) async {
    final t = _now();
    final id = prefId(exercise.id);
    final existing =
        await (_db.select(_db.exercisePrefs)..where((p) => p.id.equals(id))).getSingleOrNull();
    final reset = tracking == exercise.defaultTrackingType;
    if (existing == null) {
      if (reset) return;
      await _db.into(_db.exercisePrefs).insert(ExercisePrefsCompanion.insert(
            id: id,
            createdAt: t,
            updatedAt: t,
            userId: _userId(),
            exerciseId: exercise.id,
            trackingType: tracking.key,
          ));
    } else {
      await (_db.update(_db.exercisePrefs)..where((p) => p.id.equals(id))).write(
        ExercisePrefsCompanion(
          trackingType: Value(tracking.key),
          deletedAt: Value(reset ? t : null),
          updatedAt: Value(t),
          dirty: const Value(true),
        ),
      );
    }
  }
}

final exercisePrefsRepositoryProvider = Provider<ExercisePrefsRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return ExercisePrefsRepository(
    ref.watch(appDatabaseProvider),
    userId: () => uid,
  );
});

/// 动作 id → 用户选的记录方式。数据库不可用时（如部分界面测试）当作没有偏好。
final exercisePrefsProvider = StreamProvider<Map<String, TrackingType>>((ref) {
  try {
    return ref.watch(exercisePrefsRepositoryProvider).watchAll();
  } catch (_) {
    return Stream.value(const <String, TrackingType>{});
  }
});
