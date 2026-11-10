import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';

/// 「刚刚 / 5 分钟前 / 今天 18:30 / 10月28日」这类相对时间。
String formatAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 60) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  String two(int v) => v.toString().padLeft(2, '0');
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  if (sameDay) return '今天 ${two(t.hour)}:${two(t.minute)}';
  return '${t.month}月${t.day}日 ${two(t.hour)}:${two(t.minute)}';
}

/// 首页右上角的同步状态小标签；点一下立即同步。
class SyncChip extends ConsumerWidget {
  const SyncChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = ref.watch(syncControllerProvider);
    final (text, color, icon) = switch (s.phase) {
      SyncPhase.syncing => ('同步中', c.text2, AppIcons.syncing),
      SyncPhase.error => ('同步失败', c.danger, AppIcons.cloudOff),
      SyncPhase.idle when s.pending => ('待同步', c.text2, AppIcons.cloudUp),
      SyncPhase.idle => (s.lastSync == null ? '未同步' : '已同步', c.text2, AppIcons.cloudDone),
    };
    return PressScale(
      scale: PressScale.chipScale,
      child: Semantics(
        button: true,
        label: '同步状态：$text，点击立即同步',
        child: GestureDetector(
          onTap: () => ref.read(syncControllerProvider.notifier).requestSync(),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: c.border, width: AppStroke.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(text, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
