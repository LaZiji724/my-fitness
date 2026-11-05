import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/notifications/reminder_scheduler.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/sync/backup_actions.dart';
import 'package:my_fitness/features/sync/sync_chip.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:my_fitness/features/update/update_service.dart';
import 'package:my_fitness/features/update/update_ui.dart';

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
          PressScale(child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消'))),
          PressScale(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: context.colors.danger),
              child: const Text('退出'),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    // 先把这个账号的改动推到云端，再退出并清掉本机副本，
    // 这样换账号登录后本机只有新账号自己的数据（云端的数据不受影响）。
    final service = ref.read(syncServiceProvider);
    final auth = ref.read(authServiceProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
            SizedBox(width: 16),
            Text('正在同步数据…'),
          ]),
        ),
      ),
    );
    final synced = await service.flushBeforeSignOut();
    navigator.pop();
    if (!synced) {
      if (!context.mounted) return;
      final force = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('有改动还没同步'),
          content: const Text('可能是网络不好。现在退出的话，这些改动会先留在这台手机上，'
              '用同一个账号重新登录后会自动同步；换成别的账号则看不到它们。'),
          actions: [
            PressScale(child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('先不退出'))),
            PressScale(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: context.colors.danger),
                child: const Text('仍要退出'),
              ),
            ),
          ],
        ),
      );
      if (force != true) return;
    }
    await auth.signOut();
    if (synced) await service.clearLocalData();
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
          const SizedBox(height: AppSpace.s8),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.surface, width: 4)),
              child: AvatarView(
                kind: profile?.avatarKind ?? 'preset',
                avatarRef: profile?.avatarRef ?? 'avatar_01',
                size: 88,
              ),
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
          const SizedBox(height: AppSpace.s32),
          Padding(
            padding: const EdgeInsets.only(left: AppSpace.s4, bottom: AppSpace.s8),
            child: Text('数据与同步', style: AppText.label.copyWith(color: c.text2, fontWeight: FontWeight.w700)),
          ),
          const _SyncSection(),
          const SizedBox(height: AppSpace.s24),
          PressScale(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(foregroundColor: c.danger, backgroundColor: c.surface),
              onPressed: () => _confirmSignOut(context, ref),
              child: const Text('退出登录'),
            ),
          ),
          const SizedBox(height: AppSpace.s12),
          Center(child: Text('我的健身 · 数据保存在本机，并自动同步到你的账号', style: AppText.caption.copyWith(color: c.text3))),
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
    Widget row(IconData icon, String title, String? sub, VoidCallback? onTap, {Widget? trailing}) => PressScale(
      scale: PressScale.cardScale,
      child: ListTile(
            leading: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Icon(icon, size: 20, color: c.text2),
            ),
            title: Text(title, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
            subtitle: sub == null ? null : Text(sub, style: AppText.label.copyWith(color: s.phase == SyncPhase.error && title == '云同步' ? c.danger : c.text2)),
            trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: c.text3),
            onTap: onTap,
          ),
    );
    // 用 Material 而不是 DecoratedBox 做卡片底，点按时的水波纹才看得见
    return Material(
      color: c.surface,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
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
          const Divider(height: 1, indent: 68, endIndent: 16),
          row(Icons.ios_share_rounded, '导出备份', '把全部训练数据保存成一个文件', () => exportBackup(context, ref)),
          const Divider(height: 1, indent: 68, endIndent: 16),
          row(Icons.file_open_outlined, '导入备份', '从备份文件恢复数据', () => importBackup(context, ref)),
          const Divider(height: 1, indent: 68, endIndent: 16),
          row(Icons.notifications_active_outlined, '测试提醒', '10 秒后弹一条通知，检查计时提醒能不能用', () async {
            final msg = await runReminderSelfTest(ref.read(reminderSchedulerProvider), DateTime.now());
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 8)));
          }),
          const Divider(height: 1, indent: 68, endIndent: 16),
          row(
            Icons.system_update_alt_rounded,
            '检查更新',
            '当前版本 ${ref.watch(currentVersionProvider).value ?? ''}',
            () => checkForUpdateManually(context, ref),
          ),
        ],
      ),
    );
  }
}
