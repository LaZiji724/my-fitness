import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:my_fitness/features/plan/plan_widgets.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';

String backupFileName(DateTime now) =>
    'my-fitness-backup-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';

/// 导出备份：写成 JSON 文件后调起系统分享（可存到「文件」、网盘或发给自己）。
Future<void> exportBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final data = await ref.read(syncServiceProvider).exportAll();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${backupFileName(DateTime.now())}');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: '我的健身 数据备份',
    ));
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('导出失败，请稍后重试')));
  }
}

/// 导入备份：选一个备份文件，确认后合并进当前数据（同一条记录以备份为准）。
Future<void> importBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final picked = await FilePicker.pickFile(type: FileType.any);
  if (picked == null) return;
  final bytes = await picked.readAsBytes();
  if (!context.mounted) return;
  final ok = await confirmDialog(
    context,
    title: '导入备份？',
    message: '备份里的记录会合并进当前数据，相同的记录以备份为准，其余数据不会被删除。',
    confirm: '导入',
  );
  if (!ok) return;
  try {
    final json = jsonDecode(utf8.decode(bytes));
    final n = await ref.read(syncServiceProvider).importAll(json as Map<String, dynamic>);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已导入 $n 条记录，稍后会自动同步到云端')));
    await ref.read(syncControllerProvider.notifier).requestSync();
  } on FormatException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('导入失败：文件无法读取')));
  }
}
