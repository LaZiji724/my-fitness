// ignore_for_file: prefer_initializing_formals
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

/// 体重记录：每天最多一条，重复记录覆盖当天的值。
class BodyRepository {
  BodyRepository(
    this._db, {
    required String Function() userId,
    DateTime Function()? now,
  })  : _userId = userId,
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final String Function() _userId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  Stream<List<BodyMetric>> watchAll() {
    final q = _db.select(_db.bodyMetrics)
      ..where((m) => m.deletedAt.isNull() & m.userId.equals(_userId()) & m.weightKg.isNotNull())
      ..orderBy([(m) => OrderingTerm.asc(m.date)]);
    return q.watch();
  }

  Future<List<BodyMetric>> all() => (_db.select(_db.bodyMetrics)
        ..where((m) => m.deletedAt.isNull() & m.userId.equals(_userId()) & m.weightKg.isNotNull())
        ..orderBy([(m) => OrderingTerm.asc(m.date)]))
      .get();

  Future<void> setWeight(DateTime day, double kg) async {
    final t = _now();
    final key = WorkoutRepository.dateKey(day);
    final existing = await (_db.select(_db.bodyMetrics)
          ..where((m) => m.date.equals(key) & m.userId.equals(_userId()) & m.deletedAt.isNull()))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.update(_db.bodyMetrics)..where((m) => m.id.equals(existing.id))).write(
          BodyMetricsCompanion(weightKg: Value(kg), updatedAt: Value(t), dirty: const Value(true)));
    } else {
      await _db.into(_db.bodyMetrics).insert(BodyMetricsCompanion.insert(
            id: _uuid.v4(),
            createdAt: t,
            updatedAt: t,
            userId: _userId(),
            date: key,
            weightKg: Value(kg),
          ));
    }
  }

  Future<void> remove(String id) async {
    final t = _now();
    await (_db.update(_db.bodyMetrics)..where((m) => m.id.equals(id)))
        .write(BodyMetricsCompanion(deletedAt: Value(t), updatedAt: Value(t), dirty: const Value(true)));
  }
}
