import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/sync/backup_actions.dart';
import 'package:my_fitness/features/sync/sync_chip.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';

/// 「我的」：账号信息、云同步状态、数据备份与退出登录。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后需要重新输入用户名和密码。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) await ref.read(authServiceProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final profile = ref.watch(profileSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.pageGutter),
        children: [
          Center(
            child: AvatarView(
              kind: profile?.avatarKind ?? 'preset',
              avatarRef: profile?.avatarRef ?? 'avatar_01',
              size: 88,
            ),
          ),
          const SizedBox(height: AppSpace.s12),
          Center(
            child: Text(profile?.displayName ?? '',
                style: AppText.titleMedium.copyWith(color: c.text)),
          ),
          Center(
            child: Text('@${profile?.username ?? ''}',
                style: AppText.label.copyWith(color: c.text3)),
          ),
          const SizedBox(height: AppSpace.s24),
          const _SyncSection(),
          const SizedBox(height: AppSpace.s24),
          ElevatedButton(
            onPressed: () => _confirmSignOut(context, ref),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}

class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(syncControllerProvider);
    final syncing = s.phase == SyncPhase.syncing;
    final subtitle = switch (s.phase) {
      SyncPhase.syncing => '正在同步…',
      SyncPhase.error => s.error ?? '同步失败，稍后会重试',
      _ => s.lastSync == null ? '还没有同步过' : '上次同步：${formatAgo(s.lastSync!, DateTime.now())}${s.pending ? '，还有改动待上传' : ''}',
    };
    Widget row(IconData icon, String title, String? sub, VoidCallback? onTap, {Widget? trailing}) => ListTile(
          leading: Icon(icon, color: c.text2),
          title: Text(title, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub, style: AppText.label.copyWith(color: s.phase == SyncPhase.error && title == '云同步' ? c.danger : c.text2)),
          trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: c.text3),
          onTap: onTap,
        );
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: AppRadius.card),
      child: Column(
        children: [
          row(
            Icons.cloud_sync_outlined,
            '云同步',
            subtitle,
            syncing ? null : () => ref.read(syncControllerProvider.notifier).requestSync(),
            trailing: syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('立即同步', style: AppText.label.copyWith(color: c.accentText, fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          row(Icons.ios_share_rounded, '导出备份', '把全部训练数据保存成一个文件', () => exportBackup(context, ref)),
          const Divider(height: 1, indent: 16, endIndent: 16),
          row(Icons.file_open_outlined, '导入备份', '从备份文件恢复数据', () => importBackup(context, ref)),
        ],
      ),
    );
  }
}
