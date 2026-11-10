import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/calendar/calendar_math.dart';
import 'package:my_fitness/features/exercises/exercise.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';
import 'package:my_fitness/features/plan/part_colors.dart';
import 'package:my_fitness/features/workout/workout_math.dart' show formatWeight;
import 'package:my_fitness/features/workout/workout_summary_page.dart' show formatVolume;

/// 好友最近的运动记录。对方设为「仅自己可见」的部分不会出现，只显示一句说明。
class FriendActivityPage extends ConsumerWidget {
  const FriendActivityPage({super.key, required this.friendId, this.cameFrom});
  final String friendId;

  /// 是从哪一页来的（从好友列表进来为 null）
  final FriendPage? cameFrom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final entry = ref.watch(friendsControllerProvider).byUser(friendId);
    final activity = ref.watch(friendActivityProvider(friendId));
    final name = entry?.user.displayName;

    return Scaffold(
      appBar: AppBar(title: Text(name == null ? '最近运动' : '$name 的运动')),
      body: activity.when(
        loading: () => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => Center(
          child: EmptyState(
            icon: AppIcons.cloudOff,
            title: '没加载出来',
            hint: '检查一下网络，或者你们已经不是好友了',
            action: SmallNeutralButton(label: '再试一次', onPressed: () => ref.invalidate(friendActivityProvider(friendId))),
          ),
        ),
        data: (a) => RefreshIndicator(
          onRefresh: () async => ref.refresh(friendActivityProvider(friendId).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s32),
            children: [
              if (entry != null) ...[
                Row(
                  children: [
                    UserAvatar(entry.user, size: 48, ring: true),
                    const SizedBox(width: AppSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.user.displayName,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleSmall.copyWith(color: c.text)),
                          Text(metaLine(['@${entry.user.username}', '可看${a.settings.historyDays == 0 ? '全部' : '近 ${a.settings.historyDays} 天'}记录']),
                              style: AppText.label.copyWith(color: c.text3)),
                        ],
                      ),
                    ),
                    PressScale(
                      child: FilledButton(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(72, AppSize.buttonSmall + 4)),
                          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpace.s16)),
                        ),
                        onPressed: () => switchFriendPage(context, friendId, from: FriendPage.activity, cameFrom: cameFrom),
                        child: const Text('聊天'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.s20),
              ],
              ..._sections(context, a),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, FriendActivity a) {
    final workouts = a.workouts;
    if (workouts == null && a.bodyWeight == null) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: 32),
          child: EmptyState(icon: AppIcons.lockSmall, title: '对方没有公开运动记录', hint: '对方在「好友 → 隐私设置」里可以改'),
        ),
      ];
    }
    return [
      if (workouts != null) ...[
        _Summary(workouts: workouts, showVolume: a.settings.showVolume, showDuration: a.settings.showDuration),
        const SizedBox(height: AppSpace.s24),
      ],
      if (a.bodyWeight != null) ...[
        const SectionTitle('体重'),
        const SizedBox(height: AppSpace.s12),
        _WeightCard(points: a.bodyWeight!),
        const SizedBox(height: AppSpace.s24),
      ] else ...[
        const _HiddenNote('体重对方没有公开'),
        const SizedBox(height: AppSpace.s24),
      ],
      if (workouts != null) ...[
        SectionTitle('训练记录', trailing: Text('${workouts.length} 次', style: AppText.label.copyWith(color: context.colors.text3))),
        const SizedBox(height: AppSpace.s12),
        if (workouts.isEmpty)
          const AppCard(child: EmptyState(icon: AppIcons.calendarOff, title: '这段时间没有训练', compact: true))
        else
          for (final w in workouts) ...[
            _WorkoutCard(workout: w),
            const SizedBox(height: AppSpace.s12),
          ],
        if (!a.settings.showExercises) const _HiddenNote('具体动作对方没有公开'),
        if (a.settings.showExercises && !a.settings.showVolume) const _HiddenNote('具体运动量对方没有公开'),
      ] else
        const _HiddenNote('训练记录对方没有公开'),
    ];
  }
}

class _HiddenNote extends StatelessWidget {
  const _HiddenNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Icon(AppIcons.lockSmall, size: 14, color: c.text3),
          const SizedBox(width: AppSpace.s8),
          Text(text, style: AppText.label.copyWith(color: c.text3)),
        ],
      ),
    );
  }
}

/// 顶部三个数：训练几天、几次、总容量。
class _Summary extends StatelessWidget {
  const _Summary({required this.workouts, required this.showVolume, required this.showDuration});

  final List<FriendWorkout> workouts;
  final bool showVolume;
  final bool showDuration;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = workouts.map((w) => w.localDate).toSet().length;
    final volume = workouts.fold<double>(0, (s, w) => s + (w.volumeKg ?? 0));
    final minutes = workouts.fold<int>(0, (s, w) => s + (w.durationMin ?? 0));
    final stats = <(String, String)>[
      ('$days', '天有训练'),
      ('${workouts.length}', '次训练'),
      if (showVolume) (volume >= 1000 ? (volume / 1000).toStringAsFixed(1) : volume.round().toString(), volume >= 1000 ? '吨总容量' : 'kg 总容量'),
      if (!showVolume && showDuration) ('$minutes', '分钟'),
    ];
    return HeroCard(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 20), color: c.onHero.withValues(alpha: 0.12)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stats[i].$1, style: AppText.numLarge.copyWith(color: c.onHero, height: 1)),
                  const SizedBox(height: 4),
                  Text(stats[i].$2, style: AppText.caption.copyWith(color: c.onHero2)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.points});
  final List<WeightPoint> points;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (points.isEmpty) {
      return const AppCard(child: EmptyState(icon: AppIcons.scale, title: '这段时间没有体重记录', compact: true));
    }
    final latest = points.first; // 最新的在前
    final oldest = points.last;
    final diff = latest.weightKg - oldest.weightKg;
    final up = diff > 0.04;
    final down = diff < -0.04;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatWeight(latest.weightKg), style: AppText.numLarge.copyWith(color: c.text, height: 1)),
          const SizedBox(width: 4),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('kg', style: AppText.label.copyWith(color: c.text2))),
          const Spacer(),
          if (points.length > 1)
            AppTag(
              '${up ? '+' : ''}${diff.toStringAsFixed(1)} kg',
              icon: up ? AppIcons.arrowUp : (down ? AppIcons.arrowDown : AppIcons.minus),
              color: c.text2,
            ),
          const SizedBox(width: AppSpace.s8),
          Text('${latest.date.month}月${latest.date.day}日', style: AppText.label.copyWith(color: c.text3)),
        ],
      ),
    );
  }
}

class _WorkoutCard extends StatefulWidget {
  const _WorkoutCard({required this.workout});
  final FriendWorkout workout;

  @override
  State<_WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends State<_WorkoutCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = widget.workout;
    final d = w.date;
    final exercises = w.exercises;
    final canOpen = exercises != null && exercises.isNotEmpty;
    final meta = metaLine([
      if (w.durationMin != null) '${w.durationMin} 分钟',
      if (w.volumeKg != null) formatVolume(w.volumeKg!),
      if (w.setCount != null) '${w.setCount} 组',
    ]);
    // 没公开动作和运动量时，至少说一下练了哪天
    final fallback = meta.isEmpty && !canOpen ? weekdayNames[d.weekday - 1] : meta;

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: canOpen ? () => setState(() => _open = !_open) : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.cardPadding),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Column(
                    children: [
                      Text('${d.day}', style: AppText.numMedium.copyWith(color: c.text, height: 1.1)),
                      Text('${d.month}月', style: AppText.caption.copyWith(color: c.text3)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.name ?? '自由训练',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body.copyWith(color: c.text, fontWeight: FontWeight.w600)),
                      if (fallback.isNotEmpty) Text(fallback, style: AppText.label.copyWith(color: c.text2)),
                    ],
                  ),
                ),
                if (canOpen)
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: AppMotion.standard,
                    curve: AppMotion.curve,
                    child: Icon(AppIcons.chevronRight, size: 14, color: c.text3),
                  ),
              ],
            ),
          ),
          if (canOpen)
            AnimatedSize(
              duration: AppMotion.standard,
              curve: AppMotion.curve,
              alignment: Alignment.topCenter,
              child: _open
                  ? Column(
                      children: [
                        const HairDivider(),
                        for (var i = 0; i < exercises.length; i++) ...[
                          if (i > 0) const HairDivider(indent: AppSpace.cardPadding),
                          _ExerciseRow(exercise: exercises[i]),
                        ],
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.exercise});
  final FriendExercise exercise;

  String _setText(FriendSet s) {
    if (s.durationSec != null && (s.weightKg == null && s.reps == null)) {
      final m = s.durationSec! ~/ 60;
      final sec = s.durationSec! % 60;
      return m > 0 ? '$m分${sec > 0 ? '$sec秒' : ''}' : '$sec秒';
    }
    if (s.weightKg != null && s.weightKg! > 0) return '${formatWeight(s.weightKg)}×${s.reps ?? 0}';
    return '${s.reps ?? 0}次';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final part = BodyPart.fromKey(exercise.bodyPart);
    final sets = exercise.sets;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.cardPadding, vertical: AppSpace.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: partColor(c, part), shape: BoxShape.circle)),
              const SizedBox(width: AppSpace.s8),
              Expanded(
                child: Text(exercise.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.text, fontWeight: FontWeight.w600)),
              ),
              if (sets != null) Text('${sets.where((s) => s.kind != 'warmup').length} 组', style: AppText.label.copyWith(color: c.text3)),
            ],
          ),
          if (sets != null && sets.isNotEmpty) ...[
            const SizedBox(height: AppSpace.s8),
            Wrap(
              spacing: AppSpace.s8,
              runSpacing: AppSpace.s8,
              children: [
                for (final s in sets)
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.kind == 'warmup' ? c.warmupBg : c.sunken,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      s.kind == 'warmup' ? '热 ${_setText(s)}' : _setText(s),
                      style: AppText.numSmall.copyWith(fontSize: 14, height: 1, color: s.kind == 'warmup' ? c.warmupFg : c.text),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
