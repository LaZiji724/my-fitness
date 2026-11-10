import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/app_ui.dart';
import 'package:my_fitness/core/widgets/avatar_view.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';
import 'package:my_fitness/features/friends/friends_repository.dart';
import 'package:my_fitness/features/workout/workout_providers.dart' show clockProvider;

/// 二维码一共有效多久（和数据库里的 10 分钟一致，只用来画进度条）。
const kFriendCodeLife = Duration(minutes: 10);

/// 我的二维码：一个随机码，10 分钟有效，到期自动换新的。对方扫了就直接成为好友。
class MyQrPage extends ConsumerStatefulWidget {
  const MyQrPage({super.key});

  @override
  ConsumerState<MyQrPage> createState() => _MyQrPageState();
}

class _MyQrPageState extends ConsumerState<MyQrPage> {
  FriendCode? _code;
  String? _error;
  bool _loading = false;
  Timer? _tick;
  late DateTime _now;

  /// 打开这页时已有的好友，用来发现「刚刚有人扫了我」
  Set<String>? _friendIds;

  @override
  void initState() {
    super.initState();
    _now = ref.read(clockProvider)();
    _generate();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = ref.read(clockProvider)());
      final code = _code;
      if (code != null && !_loading && !_now.isBefore(code.expiresAt)) _generate();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final code = await ref.read(friendsRepositoryProvider).createCode();
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
        _now = ref.read(clockProvider)();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _code = null;
        _error = SupabaseFriendsRepository.translate(e).message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final profile = ref.watch(profileSummaryProvider);

    // 有人扫了我的码：提示一下
    ref.listen(friendsControllerProvider, (prev, next) {
      if (!next.loaded) return;
      final ids = next.friends.map((e) => e.user.id).toSet();
      final known = _friendIds;
      _friendIds = ids;
      if (known == null) return;
      final added = next.friends.where((e) => !known.contains(e.user.id)).toList();
      if (added.isNotEmpty) showFriendToast(context, '已和 ${added.first.user.displayName} 成为好友');
    });
    _friendIds ??= () {
      final s = ref.read(friendsControllerProvider);
      return s.loaded ? s.friends.map((e) => e.user.id).toSet() : null;
    }();

    final code = _code;
    final left = code == null ? Duration.zero : code.expiresAt.difference(_now);
    final seconds = left.isNegative ? 0 : left.inSeconds;
    final progress = (seconds / kFriendCodeLife.inSeconds).clamp(0.0, 1.0);
    final clock = '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('我的二维码')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s32),
        children: [
          HeroCard(
            padding: const EdgeInsets.all(AppSpace.s24),
            child: Column(
              children: [
                Row(
                  children: [
                    AvatarView(kind: profile?.avatarKind ?? 'preset', avatarRef: profile?.avatarRef ?? 'avatar_01', size: 48),
                    const SizedBox(width: AppSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(profile?.displayName ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleSmall.copyWith(color: c.onHero)),
                          Text('@${profile?.username ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label.copyWith(color: c.onHero2)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.s24),
                // 二维码永远是白底黑码，深色模式下也一样，保证好扫
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpace.s20),
                    decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(AppRadius.md)),
                    child: _QrBody(code: code, loading: _loading, error: _error, onRetry: _generate),
                  ),
                ),
                const SizedBox(height: AppSpace.s20),
                Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
                    const SizedBox(width: AppSpace.s8),
                    Text(code == null ? '正在生成' : '有效时间还剩', style: AppText.label.copyWith(color: c.onHero2)),
                    const Spacer(),
                    Text(code == null ? '--:--' : clock, style: AppText.numMedium.copyWith(color: c.onHero, height: 1)),
                  ],
                ),
                const SizedBox(height: AppSpace.s12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: c.onHero.withValues(alpha: 0.12)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: code == null ? 0 : progress,
                          child: ColoredBox(color: c.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.s16),
          Text(
            '对方用「我的健身」扫一扫，你们就直接成为好友。\n二维码每 10 分钟自动更换，旧的立即失效。',
            textAlign: TextAlign.center,
            style: AppText.label.copyWith(color: c.text2, height: 1.6),
          ),
          const SizedBox(height: AppSpace.s24),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  child: ElevatedButton(onPressed: _loading ? null : _generate, child: const Text('换一个')),
                ),
              ),
              const SizedBox(width: AppSpace.s12),
              Expanded(
                child: PressScale(
                  child: ElevatedButton(
                    onPressed: () => context.pushReplacement('/friends/scan'),
                    child: const Text('扫一扫'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QrBody extends StatelessWidget {
  const _QrBody({required this.code, required this.loading, required this.error, required this.onRetry});

  final FriendCode? code;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  // 白底上的固定墨色，不跟随主题
  static const _ink = Color(0xFF121214);
  static const _inkSoft = Color(0xFF55545A);

  @override
  Widget build(BuildContext context) {
    final code = this.code;
    if (code != null) {
      return AnimatedOpacity(
        opacity: loading ? 0.25 : 1,
        duration: AppMotion.standard,
        child: QrImageView(
          data: code.payload,
          padding: EdgeInsets.zero,
          backgroundColor: const Color(0xFFFFFFFF),
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: _ink),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: _ink),
          semanticsLabel: '我的好友二维码',
        ),
      );
    }
    if (error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(AppIcons.cloudOff, size: 28, color: _inkSoft),
          const SizedBox(height: AppSpace.s12),
          Text(error!, textAlign: TextAlign.center, style: AppText.label.copyWith(color: _inkSoft)),
          const SizedBox(height: AppSpace.s12),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: _ink, textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700)),
            child: const Text('再试一次'),
          ),
        ],
      );
    }
    return const Center(
      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _ink)),
    );
  }
}
