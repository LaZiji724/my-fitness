import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/db/app_database.dart';

/// 本机 SQLite 数据库（单例）。所有业务数据先写这里，再由同步引擎推到云端。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
