// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:drift/drift.dart';

import 'package:my_fitness/core/db/app_database.dart';
import 'package:my_fitness/features/sync/sync_remote.dart';

/// 把 drift 数据类转成云端 JSON 时用：时间一律用 UTC 的 ISO 字符串（云端是 timestamptz）。
class _IsoSerializer extends ValueSerializer {
  const _IsoSerializer();

  @override
  T fromJson<T>(dynamic json) {
    if (json == null) return null as T;
    if (T == DateTime || T == _typeOf<DateTime?>()) {
      return DateTime.parse(json as String).toLocal() as T;
    }
    if ((T == double || T == _typeOf<double?>()) && json is num) {
      return json.toDouble() as T;
    }
    if ((T == int || T == _typeOf<int?>()) && json is num) {
      return json.toInt() as T;
    }
    return json as T;
  }

  @override
  dynamic toJson<T>(T value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value;
  }
}

Type _typeOf<X>() => X;

const _ser = _IsoSerializer();

String _snake(String camel) =>
    camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

String _camel(String snake) =>
    snake.replaceAllMapped(RegExp('_([a-z])'), (m) => m[1]!.toUpperCase());

/// 一张要同步的表。顺序即推送顺序：被外键引用的表排在前面。
class SyncTableSpec<T extends Table, D extends DataClass> {
  const SyncTableSpec(this.table, this.fromJson);
  final TableInfo<T, D> table;
  final D Function(Map<String, dynamic> json, {ValueSerializer? serializer}) fromJson;

  String get name => table.actualTableName;
}

class SyncReport {
  const SyncReport({this.pushed = 0, this.pulled = 0});
  final int pushed;
  final int pulled;
}

/// 本地优先的双向同步：先按游标拉取云端更新，再推送本地改动。
/// 冲突规则：同一行两边都改过时，修改时间较晚的一边获胜（云端的修改时间是它收到的时间）。
///
/// 本机数据库是按账号隔离的：每一行都带 user_id，拉取游标、上次同步时间也各记各的，
/// 推送只推当前账号自己的改动。换账号登录后，新账号从云端完整拉取自己的数据，
/// 不会看到、也不会上传上一个账号的内容。
class SyncService {
  SyncService(this._db, this._remote, {required String Function() userId, this.pageSize = 500})
      : _userId = userId;

  final AppDatabase _db;
  final SyncRemote _remote;
  final String Function() _userId;
  final int pageSize;
  Future<SyncReport>? _running;

  String get _lastSyncKey => 'last_sync:${_userId()}';
  String _cursorKey(SyncTableSpec t) => 'cursor:${_userId()}:${t.name}';

  late final List<SyncTableSpec> tables = [
    SyncTableSpec(_db.templates, Template.fromJson),
    SyncTableSpec(_db.templateExercises, TemplateExercise.fromJson),
    SyncTableSpec(_db.plans, Plan.fromJson),
    SyncTableSpec(_db.planDays, PlanDay.fromJson),
    SyncTableSpec(_db.workouts, Workout.fromJson),
    SyncTableSpec(_db.workoutExercises, WorkoutExercise.fromJson),
    SyncTableSpec(_db.workoutSets, WorkoutSet.fromJson),
    SyncTableSpec(_db.bodyMetrics, BodyMetric.fromJson),
    SyncTableSpec(_db.favoritePrograms, FavoriteProgram.fromJson),
    SyncTableSpec(_db.exercisePrefs, ExercisePref.fromJson),
  ];

  /// 同一时刻只跑一轮；重复调用直接复用正在进行的那一轮。
  Future<SyncReport> syncNow() => _running ??= _run().whenComplete(() => _running = null);

  Future<SyncReport> _run() async {
    var pushed = 0, pulled = 0;
    await _dropLegacyState();
    // 先拉后推：拉取时本地「更晚的未推送改动」会被保留，较旧的会被云端覆盖；
    // 如果先推，会把另一台设备较新的改动直接盖掉。
    for (final t in tables) {
      pulled += await _pull(t);
    }
    for (final t in tables) {
      pushed += await _push(t);
    }
    await _db.customStatement(
      'INSERT OR REPLACE INTO sync_states (key, value) VALUES (?, ?)',
      [_lastSyncKey, DateTime.now().toUtc().toIso8601String()],
    );
    return SyncReport(pushed: pushed, pulled: pulled);
  }

  /// 旧版本不分账号的游标（`cursor:表名`、`last_sync`）：不知道属于谁，直接丢弃，
  /// 换成按账号记录的新游标（代价只是第一次多拉一遍自己的数据）。
  Future<void> _dropLegacyState() => _db.customStatement(
      "DELETE FROM sync_states WHERE key = 'last_sync' OR (key LIKE 'cursor:%' AND key NOT LIKE 'cursor:%:%')");

  /// 当前账号是否还有没推送的本地改动。
  Future<bool> hasDirty() async {
    for (final t in tables) {
      final r = await _db
          .customSelect('SELECT 1 AS x FROM ${t.name} WHERE dirty = 1 AND user_id = ? LIMIT 1',
              variables: [Variable<String>(_userId())], readsFrom: {t.table})
          .get();
      if (r.isNotEmpty) return true;
    }
    return false;
  }

  Future<DateTime?> lastSyncAt() async {
    final r = await _db.customSelect('SELECT value FROM sync_states WHERE key = ?',
        variables: [Variable<String>(_lastSyncKey)]).get();
    return r.isEmpty ? null : DateTime.tryParse(r.first.read<String>('value'))?.toLocal();
  }

  // ------------------------------------------------------------------ 推送

  Future<int> _push(SyncTableSpec t) async {
    var total = 0;
    while (true) {
      final rows = await _db
          .customSelect(
              'SELECT * FROM ${t.name} WHERE dirty = 1 AND user_id = ? ORDER BY updated_at, id LIMIT $pageSize',
              variables: [Variable<String>(_userId())],
              readsFrom: {t.table})
          .get();
      if (rows.isEmpty) return total;
      final datas = [for (final r in rows) t.table.map(r.data) as DataClass];
      final json = [
        for (final d in datas)
          {
            for (final e in d.toJson(serializer: _ser).entries)
              if (e.key != 'dirty') _snake(e.key): e.value,
          },
      ];
      await _remote.upsert(t.name, json);
      // 只把「推送期间没再被改动」的行标记为已同步，期间的新改动留到下一轮。
      for (final r in rows) {
        await _db.customUpdate(
          'UPDATE ${t.name} SET dirty = 0 WHERE id = ? AND updated_at = ?',
          variables: [Variable<String>(r.read<String>('id')), Variable<int>(r.read<int>('updated_at'))],
          updates: {t.table},
          updateKind: UpdateKind.update,
        );
      }
      total += rows.length;
      if (rows.length < pageSize) return total;
    }
  }

  // ------------------------------------------------------------------ 拉取

  Future<int> _pull(SyncTableSpec t) async {
    final key = _cursorKey(t);
    final saved = await _db.customSelect('SELECT value FROM sync_states WHERE key = ?', variables: [Variable<String>(key)]).get();
    var cursor = SyncCursor.decode(saved.isEmpty ? null : saved.first.read<String>('value'));
    var total = 0;
    while (true) {
      final rows = await _remote.fetchAfter(t.name, userId: _userId(), cursor: cursor, limit: pageSize);
      if (rows.isEmpty) return total;
      await _db.transaction(() async {
        for (final remote in rows) {
          await _apply(t, remote);
        }
      });
      final last = rows.last;
      cursor = SyncCursor(last['updated_at'] as String, last['id'] as String);
      await _db.customStatement(
        'INSERT OR REPLACE INTO sync_states (key, value) VALUES (?, ?)',
        [key, cursor.encode()],
      );
      total += rows.length;
      if (rows.length < pageSize) return total;
    }
  }

  Future<void> _apply(SyncTableSpec t, Map<String, dynamic> remote) async {
    final id = remote['id'] as String;
    final remoteUpdated = DateTime.parse(remote['updated_at'] as String);
    final local = await _db
        .customSelect('SELECT updated_at, dirty FROM ${t.name} WHERE id = ?',
            variables: [Variable<String>(id)], readsFrom: {t.table})
        .getSingleOrNull();
    if (local != null && local.read<int>('dirty') == 1) {
      final localUpdated = DateTime.fromMillisecondsSinceEpoch(local.read<int>('updated_at') * 1000, isUtc: true);
      // 本地有未推送的改动，且不比云端旧 → 保留本地，等下一轮推上去
      if (!remoteUpdated.isAfter(localUpdated)) return;
    }
    final json = <String, dynamic>{
      for (final e in remote.entries) _camel(e.key): e.value,
      'dirty': false,
    };
    final data = t.fromJson(json, serializer: _ser);
    await _db.into(t.table).insertOnConflictUpdate(data as Insertable<DataClass>);
  }

  // ------------------------------------------------------------------ 退出登录

  /// 退出登录前先把当前账号的改动推到云端。返回 true 表示已全部同步（可以放心清掉本机副本）。
  Future<bool> flushBeforeSignOut({Duration timeout = const Duration(seconds: 12)}) async {
    try {
      await syncNow().timeout(timeout);
    } catch (_) {
      // 没网等原因：下面按「还有没有待推送改动」判断
    }
    return !await hasDirty();
  }

  /// 清掉当前账号在本机的全部数据与同步记录（云端不受影响，再次登录会重新拉回来）。
  /// 只动当前账号的行：别的账号留在本机、还没推上去的改动不会被误删。
  Future<void> clearLocalData() async {
    final uid = _userId();
    await _db.transaction(() async {
      for (final t in tables) {
        await _db.customUpdate('DELETE FROM ${t.name} WHERE user_id = ?',
            variables: [Variable<String>(uid)], updates: {t.table}, updateKind: UpdateKind.delete);
      }
      await _db.customStatement(
        'DELETE FROM sync_states WHERE key = ? OR key LIKE ?',
        [_lastSyncKey, 'cursor:$uid:%'],
      );
    });
  }

  // ------------------------------------------------------------------ 备份

  static const backupFormat = 'my-fitness-backup';
  static const backupVersion = 1;

  /// 导出全部（未删除的）数据。字段名与云端一致，文件可以直接读懂。
  Future<Map<String, dynamic>> exportAll() async {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final t in tables) {
      final rows = await _db
          .customSelect('SELECT * FROM ${t.name} WHERE deleted_at IS NULL AND user_id = ? ORDER BY created_at, id',
              variables: [Variable<String>(_userId())], readsFrom: {t.table})
          .get();
      out[t.name] = [
        for (final r in rows)
          {
            for (final e in (t.table.map(r.data) as DataClass).toJson(serializer: _ser).entries)
              if (e.key != 'dirty') _snake(e.key): e.value,
          },
      ];
    }
    return {
      'format': backupFormat,
      'version': backupVersion,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'tables': out,
    };
  }

  /// 导入备份：同 id 的行被备份里的内容覆盖，全部标记为待同步。返回导入的行数。
  Future<int> importAll(Map<String, dynamic> backup) async {
    if (backup['format'] != backupFormat) {
      throw const FormatException('这不是「我的健身」的备份文件');
    }
    final v = backup['version'];
    if (v is! int || v > backupVersion) {
      throw const FormatException('备份文件来自更新的版本，请先升级 App');
    }
    final data = backup['tables'];
    if (data is! Map) throw const FormatException('备份文件已损坏');
    var count = 0;
    await _db.transaction(() async {
      for (final t in tables) {
        final rows = data[t.name];
        if (rows is! List) continue;
        for (final raw in rows) {
          final json = <String, dynamic>{
            for (final e in (raw as Map<String, dynamic>).entries) _camel(e.key): e.value,
            'userId': _userId(),
            'dirty': true,
          };
          await _db.into(t.table).insertOnConflictUpdate(t.fromJson(json, serializer: _ser) as Insertable<DataClass>);
          count++;
        }
      }
    });
    return count;
  }
}
