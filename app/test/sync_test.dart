import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/plan/plan_repository.dart';
import 'package:my_fitness/features/stats/body_repository.dart';
import 'package:my_fitness/features/sync/sync_remote.dart';
import 'package:my_fitness/features/sync/sync_service.dart';
import 'package:my_fitness/features/workout/workout_repository.dart';

/// 内存里的假云端：upsert 时模拟 Postgres 触发器（更新会把 updated_at 改成服务器当前时间）。
class FakeRemote implements SyncRemote {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  DateTime serverNow = DateTime.utc(2026, 11, 2, 12);
  int upsertCalls = 0;
  bool failNextUpsert = false;

  String _fmt(DateTime t) => t.toIso8601String().replaceFirst('Z', '+00:00');

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (failNextUpsert) {
      failNextUpsert = false;
      throw Exception('network down');
    }
    upsertCalls++;
    final t = tables.putIfAbsent(table, () => {});
    for (final r in rows) {
      final id = r['id'] as String;
      final row = Map<String, dynamic>.from(r);
      row['updated_at'] = t.containsKey(id) ? _fmt(serverNow) : _fmt(DateTime.parse(r['updated_at'] as String));
      t[id] = row;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAfter(String table,
      {required String userId, SyncCursor? cursor, int limit = 500}) async {
    final all = (tables[table]?.values ?? const <Map<String, dynamic>>[])
        .where((r) => r['user_id'] == userId)
        .toList()
      ..sort((a, b) {
        final c = DateTime.parse(a['updated_at'] as String).compareTo(DateTime.parse(b['updated_at'] as String));
        return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
      });
    final after = cursor == null
        ? all
        : all.where((r) {
            final c = DateTime.parse(r['updated_at'] as String).compareTo(DateTime.parse(cursor.updatedAt));
            return c > 0 || (c == 0 && (r['id'] as String).compareTo(cursor.id) > 0);
          }).toList();
    return after.take(limit).map(Map<String, dynamic>.from).toList();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true; // 测试里模拟两台设备
  late FakeRemote remote;
  late AppDatabase dbA;
  late AppDatabase dbB;
  late SyncService syncA;
  late SyncService syncB;
  late WorkoutRepository workoutsA;
  late WorkoutRepository workoutsB;
  late PlanRepository plansA;
  late DateTime clock;

  setUp(() {
    remote = FakeRemote();
    clock = DateTime.utc(2026, 11, 2, 9);
    dbA = AppDatabase.forTesting(NativeDatabase.memory());
    dbB = AppDatabase.forTesting(NativeDatabase.memory());
    syncA = SyncService(dbA, remote, userId: () => 'u1');
    syncB = SyncService(dbB, remote, userId: () => 'u1', pageSize: 3);
    workoutsA = WorkoutRepository(dbA, userId: () => 'u1', now: () => clock);
    workoutsB = WorkoutRepository(dbB, userId: () => 'u1', now: () => clock);
    plansA = PlanRepository(dbA, userId: () => 'u1', now: () => clock);
  });
  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  const exId = '378a864f-f8d0-5178-9e5e-6fa9bc25d173';

  Future<String> finishedWorkout(WorkoutRepository repo, {double kg = 60}) async {
    final w = await repo.startWorkout(name: '推日');
    final we = await repo.addExercise(w.id, exId, defaultSets: 0);
    for (var i = 0; i < 4; i++) {
      final s = await repo.addSet(we);
      await repo.updateSet(s, weightKg: kg, reps: 8);
      await repo.setCompleted(s, true);
    }
    clock = clock.add(const Duration(minutes: 50));
    await repo.finishWorkout(w.id);
    return w.id;
  }

  test('本地改动推到云端，字段名和时间格式符合云端表结构', () async {
    final id = await finishedWorkout(workoutsA);
    expect(await syncA.hasDirty(), isTrue);
    final report = await syncA.syncNow();
    expect(report.pushed, 1 + 1 + 4); // 训练 + 动作 + 4 组
    expect(await syncA.hasDirty(), isFalse);

    final w = remote.tables['workouts']![id]!;
    expect(w['user_id'], 'u1');
    expect(w['local_date'], '2026-11-02');
    expect(w['started_at'], endsWith('Z')); // UTC ISO
    expect(w.containsKey('dirty'), isFalse);
    expect(w.containsKey('startedAt'), isFalse);
    final set = remote.tables['workout_sets']!.values.first;
    expect(set['weight_kg'], 60.0);
    expect(set['workout_exercise_id'], isNotNull);
    expect(set['completed'], true);
  });

  test('另一台设备拉取后得到相同数据，之后不会再有脏数据', () async {
    final id = await finishedWorkout(workoutsA, kg: 62.5);
    await syncA.syncNow();
    final report = await syncB.syncNow();
    expect(report.pulled, 6);
    expect(await syncB.hasDirty(), isFalse);

    final view = (await workoutsB.loadWorkout(id))!;
    expect(view.workout.name, '推日');
    expect(view.workout.endedAt, isNotNull);
    expect(view.exercises.single.sets, hasLength(4));
    expect(view.exercises.single.sets.first.weightKg, 62.5);
    expect(view.volume, 62.5 * 8 * 4);

    // 再同步一次：没有新东西
    final again = await syncB.syncNow();
    expect(again.pushed, 0);
    expect(again.pulled, 0);
  });

  test('分页：同一时刻写入的多行也不会在页边界丢失（pageSize=3）', () async {
    for (var i = 0; i < 4; i++) {
      await plansA.createTemplate('模板$i'); // 同一 clock → 同一 updated_at
    }
    await syncA.syncNow();
    final report = await syncB.syncNow();
    expect(report.pulled, 4);
    expect((await dbB.select(dbB.templates).get()).map((t) => t.name).toSet(), {'模板0', '模板1', '模板2', '模板3'});
  });

  test('软删除会同步过去', () async {
    final t = await plansA.createTemplate('腿日');
    await syncA.syncNow();
    await syncB.syncNow();
    expect((await dbB.select(dbB.templates).get()).single.deletedAt, isNull);

    clock = clock.add(const Duration(hours: 1));
    remote.serverNow = DateTime.utc(2026, 11, 2, 13);
    await plansA.deleteTemplate(t);
    await syncA.syncNow();
    await syncB.syncNow();
    expect((await dbB.select(dbB.templates).get()).single.deletedAt, isNotNull);
  });

  test('冲突：两边都改了同一行，较晚的获胜', () async {
    final t = await plansA.createTemplate('原名');
    await syncA.syncNow();
    await syncB.syncNow();

    // B 先改（早），A 后改（晚）；B 还没同步
    clock = DateTime.utc(2026, 11, 2, 10);
    await PlanRepository(dbB, userId: () => 'u1', now: () => clock).renameTemplate(t, 'B的名字');
    clock = DateTime.utc(2026, 11, 2, 11);
    await plansA.renameTemplate(t, 'A的名字');
    remote.serverNow = DateTime.utc(2026, 11, 2, 11, 5);
    await syncA.syncNow(); // 云端 = A的名字，updated_at=11:05（服务器时间）

    // B 同步：它的本地修改（10:00）比云端旧 → 云端获胜
    remote.serverNow = DateTime.utc(2026, 11, 2, 11, 10);
    await syncB.syncNow();
    expect((await dbB.select(dbB.templates).get()).single.name, 'A的名字');
    expect(await syncB.hasDirty(), isFalse);
  });

  test('冲突：本地更新更晚的未推送改动不会被旧的云端数据覆盖', () async {
    final t = await plansA.createTemplate('原名');
    await syncA.syncNow();
    await syncB.syncNow();

    clock = DateTime.utc(2026, 11, 2, 10);
    remote.serverNow = DateTime.utc(2026, 11, 2, 10, 5);
    await plansA.renameTemplate(t, 'A的名字');
    await syncA.syncNow();

    // B 在更晚的时间改名，然后同步：先推（云端更新时间变成 serverNow），再拉回自己
    clock = DateTime.utc(2026, 11, 2, 12);
    remote.serverNow = DateTime.utc(2026, 11, 2, 12, 5);
    await PlanRepository(dbB, userId: () => 'u1', now: () => clock).renameTemplate(t, 'B的名字');
    await syncB.syncNow();
    await syncA.syncNow();
    expect((await dbA.select(dbA.templates).get()).single.name, 'B的名字');
    expect((await dbB.select(dbB.templates).get()).single.name, 'B的名字');
  });

  test('推送失败：改动仍保留为待同步，下次重试成功', () async {
    await finishedWorkout(workoutsA);
    remote.failNextUpsert = true;
    await expectLater(syncA.syncNow(), throwsException);
    expect(await syncA.hasDirty(), isTrue);

    final report = await syncA.syncNow();
    expect(report.pushed, greaterThan(0));
    expect(await syncA.hasDirty(), isFalse);
  });

  test('同步后再次修改：重新变为待同步，下一轮推送最新值', () async {
    final w = await workoutsA.startWorkout();
    final we = await workoutsA.addExercise(w.id, exId, defaultSets: 0);
    final s = await workoutsA.addSet(we);
    await syncA.syncNow();
    expect(await syncA.hasDirty(), isFalse);

    // 模拟：读出脏数据之后、标记之前又被改动 → 直接构造「updated_at 不同」的情形
    clock = clock.add(const Duration(seconds: 30));
    await workoutsA.updateSet(s, weightKg: 80, reps: 5);
    expect(await syncA.hasDirty(), isTrue);
    await syncA.syncNow();
    expect(remote.tables['workout_sets']![s]!['weight_kg'], 80.0);
    expect(await syncA.hasDirty(), isFalse);
  });

  test('体重与计划也会同步', () async {
    final t = await plansA.createTemplate('推日');
    final p = await plansA.createPlan('推拉腿', 3, startDate: DateTime(2026, 11, 2));
    await plansA.setPlanDay(p, 0, t);
    await BodyRepository(dbA, userId: () => 'u1', now: () => clock).setWeight(DateTime(2026, 11, 2), 72.4);
    await syncA.syncNow();
    await syncB.syncNow();

    final plans = await dbB.select(dbB.plans).get();
    expect(plans.single.startDate, '2026-11-02');
    expect(plans.single.isActive, isTrue);
    expect((await dbB.select(dbB.planDays).get()).single.templateId, t);
    expect((await dbB.select(dbB.bodyMetrics).get()).single.weightKg, 72.4);
  });

  test('last_sync 记录同步完成时间；并发调用复用同一轮', () async {
    expect(await syncA.lastSyncAt(), isNull);
    await finishedWorkout(workoutsA);
    final f1 = syncA.syncNow();
    final f2 = syncA.syncNow();
    await Future.wait([f1, f2]);
    expect(remote.upsertCalls, 3); // 训练 / 动作 / 组 各一次，没有被重复推两遍
    expect(await syncA.lastSyncAt(), isNotNull);
  });

  group('备份', () {
    test('导出再导入到全新的数据库，数据一致且待同步', () async {
      final id = await finishedWorkout(workoutsA, kg: 62.5);
      final t = await plansA.createTemplate('推日');
      await plansA.addTemplateExercise(t, exId);
      await BodyRepository(dbA, userId: () => 'u1', now: () => clock).setWeight(DateTime(2026, 11, 2), 72.4);
      final backup = await syncA.exportAll();
      expect(backup['format'], 'my-fitness-backup');
      expect((backup['tables'] as Map)['workout_sets'], hasLength(4));

      await syncB.importAll(backup);
      expect(await syncB.hasDirty(), isTrue); // 导入的数据会同步上云
      final view = (await workoutsB.loadWorkout(id))!;
      expect(view.volume, 62.5 * 8 * 4);
      expect((await dbB.select(dbB.templates).get()).single.name, '推日');
      expect((await dbB.select(dbB.bodyMetrics).get()).single.weightKg, 72.4);
    });

    test('已删除的数据不进备份；重复导入不会产生重复行', () async {
      final t = await plansA.createTemplate('要删的');
      await plansA.createTemplate('留下的');
      await plansA.deleteTemplate(t);
      final backup = await syncA.exportAll();
      expect(((backup['tables'] as Map)['templates'] as List).map((r) => (r as Map)['name']), ['留下的']);
      await syncB.importAll(backup);
      await syncB.importAll(backup);
      expect(await dbB.select(dbB.templates).get(), hasLength(1));
    });

    test('格式不对的文件会被拒绝', () async {
      await expectLater(syncB.importAll({'format': 'other'}), throwsFormatException);
      await expectLater(syncB.importAll({'format': 'my-fitness-backup', 'version': 99, 'tables': {}}), throwsFormatException);
      await expectLater(syncB.importAll({'format': 'my-fitness-backup', 'version': 1}), throwsFormatException);
    });
  });
}
