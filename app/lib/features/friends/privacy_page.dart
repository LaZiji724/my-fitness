import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';

/// 隐私设置：好友能看到我的哪些运动数据。每一项单独选「仅自己」或「好友可见」。
class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});

  Future<void> _save(BuildContext context, WidgetRef ref, PrivacySettings next) async {
    try {
      await ref.read(privacyControllerProvider.notifier).save(next);
    } catch (e) {
      if (context.mounted) showFriendError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final async = ref.watch(privacyControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('隐私设置')),
      body: async.when(
        loading: () => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => Center(
          child: EmptyState(
            icon: AppIcons.cloudOff,
            title: '设置没加载出来',
            hint: '检查一下网络',
            action: SmallNeutralButton(label: '再试一次', onPressed: () => ref.invalidate(privacyControllerProvider)),
          ),
        ),
        data: (s) {
          Future<void> set(PrivacySettings next) => _save(context, ref, next);
          final workoutsOff = !s.showWorkouts;
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '只有你的好友能看到，陌生人什么都看不到。\n每一项都可以随时改，改完立即生效。',
                  style: AppText.label.copyWith(color: c.text2, height: 1.6),
                ),
              ),
              const SizedBox(height: AppSpace.s20),
              const SectionTitle('训练数据'),
              const SizedBox(height: AppSpace.s12),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _VisibilityRow(
                      icon: AppIcons.calendarOk,
                      title: '训练记录',
                      hint: '哪天练了、练的是什么',
                      value: s.showWorkouts,
                      onChanged: (v) => set(s.copyWith(showWorkouts: v)),
                    ),
                    const HairDivider(indent: 50),
                    _VisibilityRow(
                      icon: AppIcons.timer,
                      title: '训练时长',
                      hint: '每次练了多久',
                      value: s.showDuration,
                      enabled: !workoutsOff,
                      onChanged: (v) => set(s.copyWith(showDuration: v)),
                    ),
                    const HairDivider(indent: 50),
                    _VisibilityRow(
                      icon: AppIcons.barbell,
                      title: '训练动作',
                      hint: '每次练了哪些动作',
                      value: s.showExercises,
                      enabled: !workoutsOff,
                      onChanged: (v) => set(s.copyWith(showExercises: v)),
                    ),
                    const HairDivider(indent: 50),
                    _VisibilityRow(
                      icon: AppIcons.listDetail,
                      title: '具体运动量',
                      hint: '组数、每组的重量和次数、总容量',
                      value: s.showVolume,
                      enabled: !workoutsOff,
                      onChanged: (v) => set(s.copyWith(showVolume: v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.s24),
              const SectionTitle('身体数据'),
              const SizedBox(height: AppSpace.s12),
              AppCard(
                padding: EdgeInsets.zero,
                child: _VisibilityRow(
                  icon: AppIcons.scale,
                  title: '体重',
                  hint: '体重记录和变化',
                  value: s.showBodyWeight,
                  onChanged: (v) => set(s.copyWith(showBodyWeight: v)),
                ),
              ),
              const SizedBox(height: AppSpace.s24),
              const SectionTitle('可查看的时间范围'),
              const SizedBox(height: AppSpace.s12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('好友最多能往前看多久的记录', style: AppText.label.copyWith(color: c.text2)),
                    const SizedBox(height: AppSpace.s12),
                    AppSegmented<int>(
                      values: PrivacySettings.dayOptions,
                      labels: [for (final d in PrivacySettings.dayOptions) d == 0 ? '全部' : '近 $d 天'],
                      selected: s.historyDays,
                      onChanged: (v) => set(s.copyWith(historyDays: v)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.s16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  workoutsOff ? '训练记录已设为仅自己可见，好友看不到你的任何训练。' : '没有改过的话，训练相关默认好友可见，体重默认仅自己可见。',
                  style: AppText.caption.copyWith(color: c.text3, height: 1.6),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 一项设置：图标、名称、一句说明，下面是「仅自己 / 好友可见」二选一。
class _VisibilityRow extends StatelessWidget {
  const _VisibilityRow({
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String hint;

  /// true = 好友可见
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.cardPadding, AppSpace.s12, AppSpace.cardPadding, AppSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: c.text2),
                const SizedBox(width: AppSpace.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                      Text(hint, style: AppText.caption.copyWith(color: c.text3)),
                    ],
                  ),
                ),
                Icon(value ? AppIcons.eyeSmall : AppIcons.lockSmall, size: 16, color: value ? c.accentText : c.text3),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            AppSegmented<bool>(
              height: 40,
              enabled: enabled,
              values: const [false, true],
              labels: const ['仅自己可见', '好友可见'],
              selected: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
