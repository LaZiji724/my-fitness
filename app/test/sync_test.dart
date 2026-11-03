import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/exercises/exercise_prefs.dart';
import 'package:my_fitness/features/library/library_repository.dart';
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

  test('计划库：收藏、来源计划、热身组和时长目标都能同步到另一台设备', () async {
    final lib = ProgramLibraryRepository(dbA, userId: () => 'u1', now: () => clock);
    const programId = '11111111-1111-4111-8111-111111111111';
    await lib.setFavorite(programId, true);
    final planId = await plansA.createPlan('库计划', 7, sourceProgramId: programId);
    final t = await plansA.createTemplate('库计划·A');
    await plansA.addTemplateExercise(t, exId);
    final te = (await plansA.getTemplate(t))!.exercises.single.id;
    await plansA.updateTemplateExercise(te, warmupSets: 2, targetDurationSec: 45);
    await plansA.setPlanDay(planId, 0, t);

    expect(remote.tables['favorite_programs'], isNull);
    await syncA.syncNow();
    expect(remote.tables['favorite_programs']!.values.single['program_id'], programId);
    await syncB.syncNow();

    final favB = await dbB.select(dbB.favoritePrograms).get();
    expect(favB.single.programId, programId);
    final planB = (await dbB.select(dbB.plans).get()).single;
    expect(planB.sourceProgramId, programId);
    final teB = (await dbB.select(dbB.templateExercises).get()).single;
    expect(teB.warmupSets, 2);
    expect(teB.targetDurationSec, 45);

    // 取消收藏同样同步
    clock = clock.add(const Duration(hours: 1));
    remote.serverNow = DateTime.utc(2026, 11, 2, 10, 30);
    await lib.setFavorite(programId, false);
    await syncA.syncNow();
    await syncB.syncNow();
    expect((await dbB.select(dbB.favoritePrograms).get()).single.deletedAt, isNotNull);
  });

  test('次数 / 时间偏好与热身 / 放松分区会同步到另一台设备', () async {
    final prefsA = ExercisePrefsRepository(dbA, userId: () => 'u1', now: () => clock);
    final plank = Exercise(
      id: '22222222-2222-4222-8222-222222222222', slug: 'Plank', nameZh: '平板支撑', nameEn: null, bodyPart: BodyPart.core,
      primaryMuscles: const [], secondaryMuscles: const [], equipment: 'body only', trackingType: TrackingType.duration,
      instructionsZh: null, imageCount: 2,
    );
    await prefsA.setTracking(plank, TrackingType.bodyweightReps);
    final t = await plansA.createTemplate('带分区');
    await plansA.addTemplateExercise(t, plank.id);
    final te = (await plansA.getTemplate(t))!.exercises.single.id;
    await plansA.updateTemplateExercise(te, section: 'cooldown');

    await syncA.syncNow();
    expect(remote.tables['exercise_prefs']!.values.single['tracking_type'], 'bodyweight_reps');
    expect(remote.tables['template_exercises']!.values.single['section'], 'cooldown');
    await syncB.syncNow();
    final prefsB = ExercisePrefsRepository(dbB, userId: () => 'u1', now: () => clock);
    expect((await prefsB.watchAll().first)[plank.id], TrackingType.bodyweightReps);
    expect((await dbB.select(dbB.templateExercises).get()).single.section, 'cooldown');

    // 改回默认：偏好软删除，另一台设备同步后恢复默认
    clock = clock.add(const Duration(hours: 1));
    remote.serverNow = DateTime.utc(2026, 11, 2, 10, 30);
    await prefsA.setTracking(plank, TrackingType.duration);
    await syncA.syncNow();
    await syncB.syncNow();
    expect(await prefsB.watchAll().first, isEmpty);
  });

  group('账号隔离', () {
    // 同一部手机（同一个本机数据库）先后登录两个账号
    late AppDatabase phone;
    late SyncService asU1;
    late SyncService asU2;
    late WorkoutRepository w1;
    late WorkoutRepository w2;
    late PlanRepository p1;
    late PlanRepository p2;

    setUp(() {
      phone = AppDatabase.forTesting(NativeDatabase.memory());
      asU1 = SyncService(phone, remote, userId: () => 'u1');
      asU2 = SyncService(phone, remote, userId: () => 'u2');
      w1 = WorkoutRepository(phone, userId: () => 'u1', now: () => clock);
      w2 = WorkoutRepository(phone, userId: () => 'u2', now: () => clock);
      p1 = PlanRepository(phone, userId: () => 'u1', now: () => clock);
      p2 = PlanRepository(phone, userId: () => 'u2', now: () => clock);
    });
    tearDown(() => phone.close());

    test('换账号后拉取游标不串：新账号较旧的云端数据也能完整拉下来', () async {
      // u2 在云端有一个很早以前建的模板
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      clock = DateTime.utc(2026, 10, 1, 9);
      final t2 = await PlanRepository(other, userId: () => 'u2', now: () => clock).createTemplate('u2 的拉力日');
      await SyncService(other, remote, userId: () => 'u2').syncNow();

      // 手机上 u1 后来才建了东西并同步 → u1 的游标比 u2 的数据新
      clock = DateTime.utc(2026, 11, 2, 9);
      await p1.createTemplate('u1 的推日');
      await asU1.syncNow();

      // 换 u2 登录：必须拉到自己的旧模板
      final report = await asU2.syncNow();
      expect(report.pulled, 1);
      expect((await p2.getTemplate(t2))?.template.name, 'u2 的拉力日');
      expect((await p2.watchTemplates().first).map((t) => t.template.name), ['u2 的拉力日']);
    });

    test('每个账号各自的日程、计划、模板互不可见', () async {
      final t1 = await p1.createTemplate('u1 模板');
      final plan1 = await p1.createPlan('u1 计划', 7);
      await p1.activatePlan(plan1);
      await p2.createTemplate('u2 模板');
      final plan2 = await p2.createPlan('u2 计划', 7);
      await p2.activatePlan(plan2);
      await finishedWorkout(w1);

      expect((await p1.watchTemplates().first).map((t) => t.template.name), ['u1 模板']);
      expect((await p2.watchTemplates().first).map((t) => t.template.name), ['u2 模板']);
      expect((await p1.watchPlans().first).map((p) => p.plan.name), ['u1 计划']);
      expect((await p2.watchPlans().first).map((p) => p.plan.name), ['u2 计划']);
      expect(await w1.watchCompleted().first, hasLength(1));
      expect(await w2.watchCompleted().first, isEmpty);

      // u2 设为当前计划，不会把 u1 的当前计划取消
      expect((await p1.watchPlans().first).single.plan.isActive, isTrue);
      expect((await p2.watchPlans().first).single.plan.isActive, isTrue);
      expect(t1, isNotEmpty);
    });

    test('只推送当前账号自己的改动，别的账号没推上去的改动留在原地', () async {
      await p1.createTemplate('u1 离线时建的模板');
      await p2.createTemplate('u2 的模板');
      expect(await asU1.hasDirty(), isTrue);
      expect(await asU2.hasDirty(), isTrue);

      final report = await asU2.syncNow();
      expect(report.pushed, 1);
      expect(remote.tables['templates']!.values.map((r) => r['user_id']), ['u2']);
      expect(await asU2.hasDirty(), isFalse);
      expect(await asU1.hasDirty(), isTrue); // u1 的仍待同步，没被丢也没被错推

      await asU1.syncNow();
      expect(remote.tables['templates']!.values.map((r) => r['user_id']).toSet(), {'u1', 'u2'});
    });

    test('备份只导出当前账号的数据', () async {
      await p1.createTemplate('u1 模板');
      await p2.createTemplate('u2 模板');
      final out = await asU1.exportAll();
      final names = (out['tables'] as Map)['templates'] as List;
      expect(names.map((r) => (r as Map)['name']), ['u1 模板']);
    });

    test('旧版本不分账号的游标会被丢弃，之后按账号重新拉取', () async {
      await phone.customStatement("INSERT INTO sync_states (key, value) VALUES ('cursor:templates', '2099-01-01T00:00:00Z|zzz')");
      await phone.customStatement("INSERT INTO sync_states (key, value) VALUES ('last_sync', '2099-01-01T00:00:00Z')");
      await asU1.syncNow();
      final keys = (await phone.customSelect('SELECT key FROM sync_states').get()).map((r) => r.read<String>('key')).toSet();
      expect(keys, isNot(contains('cursor:templates')));
      expect(keys, isNot(contains('last_sync')));
      expect(keys, contains('last_sync:u1'));
    });

    test('退出前同步成功后清掉本账号本机数据，别的账号的数据不动，再登录能从云端拉回', () async {
      await finishedWorkout(w1);
      await p1.createTemplate('u1 模板');
      await p2.createTemplate('u2 还没同步的模板');

      expect(await asU1.flushBeforeSignOut(), isTrue);
      await asU1.clearLocalData();

      expect(await phone.select(phone.workouts).get(), isEmpty);
      expect((await phone.select(phone.templates).get()).map((t) => t.userId), ['u2']); // u2 的原样保留
      expect(await asU1.lastSyncAt(), isNull);
      expect(await asU2.hasDirty(), isTrue);

      // u1 再次登录：云端数据完整回来
      final report = await asU1.syncNow();
      expect(report.pulled, 6 + 1);
      expect(await w1.watchCompleted().first, hasLength(1));
      expect((await p1.watchTemplates().first).map((t) => t.template.name), ['u1 模板']);
    });

    test('退出前没能同步（没网）时返回 false，本机数据保留不丢', () async {
      await p1.createTemplate('u1 模板');
      remote.failNextUpsert = true;
      expect(await asU1.flushBeforeSignOut(), isFalse);
      expect(await asU1.hasDirty(), isTrue);
      expect(await phone.select(phone.templates).get(), hasLength(1));

      // 网络恢复后，同一账号重新登录会把它推上去
      await asU1.syncNow();
      expect(remote.tables['templates']!.values, hasLength(1));
    });
  });
}
