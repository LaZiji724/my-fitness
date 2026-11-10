import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/friends/friend_models.dart';
import 'package:my_fitness/features/friends/friend_widgets.dart';
import 'package:my_fitness/features/friends/friends_providers.dart';
import 'package:my_fitness/features/friends/friends_repository.dart';
import 'package:my_fitness/features/workout/workout_providers.dart' show clockProvider;

/// 取景画面。抽成可替换的，测试和截图里不去碰相机。
typedef ScannerBuilder = Widget Function({
  required ValueChanged<String> onCode,
  required bool torch,
  required bool paused,
});

final scannerBuilderProvider = Provider<ScannerBuilder>(
  (ref) => ({required onCode, required torch, required paused}) => CameraScanner(onCode: onCode, torch: torch, paused: paused),
);

/// 真正的相机取景 + 识别二维码。
class CameraScanner extends StatefulWidget {
  const CameraScanner({super.key, required this.onCode, required this.torch, required this.paused});

  final ValueChanged<String> onCode;
  final bool torch;
  final bool paused;

  @override
  State<CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<CameraScanner> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _torchOn = false;

  @override
  void didUpdateWidget(CameraScanner old) {
    super.didUpdateWidget(old);
    if (widget.torch != _torchOn) {
      _torchOn = widget.torch;
      _controller.toggleTorch().catchError((_) {});
    }
    if (widget.paused != old.paused) {
      (widget.paused ? _controller.stop() : _controller.start()).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      fit: BoxFit.cover,
      onDetect: (capture) {
        for (final b in capture.barcodes) {
          final raw = b.rawValue;
          if (raw != null && raw.isNotEmpty) {
            widget.onCode(raw);
            return;
          }
        }
      },
      errorBuilder: (context, error) {
        final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
        return _ScannerMessage(
          icon: AppIcons.cameraOff,
          title: denied ? '没有相机权限' : '相机打不开',
          hint: denied ? '到手机「设置」里允许「我的健身」使用相机，再回来扫一扫' : '关掉其他正在用相机的应用后再试',
        );
      },
    );
  }
}

class _ScannerMessage extends StatelessWidget {
  const _ScannerMessage({required this.icon, required this.title, required this.hint});
  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _ScanColors.ink,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: _ScanColors.paper2),
              const SizedBox(height: AppSpace.s16),
              Text(title, style: AppText.titleSmall.copyWith(color: _ScanColors.paper)),
              const SizedBox(height: AppSpace.s4),
              Text(hint, textAlign: TextAlign.center, style: AppText.label.copyWith(color: _ScanColors.paper2, height: 1.6)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 取景页永远是深色的（底下是相机画面），不跟随主题。
abstract final class _ScanColors {
  static const ink = Color(0xFF0B0B0C);
  static const paper = Color(0xFFF4F3F0);
  static const paper2 = Color(0xFFA5A4AA);
  static const veil = Color(0x99000000);
}

/// 扫一扫：扫对方的好友二维码，确认后直接成为好友。
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});

  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  bool _torch = false;
  bool _handling = false;
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void _hint(String text) {
    _quietUntil = ref.read(clockProvider)().add(const Duration(seconds: 3));
    showFriendToast(context, text);
  }

  Future<void> _onCode(String raw) async {
    if (_handling || ref.read(clockProvider)().isBefore(_quietUntil)) return;
    final code = FriendCode.parse(raw);
    if (code == null) {
      _hint('这不是「我的健身」的好友二维码');
      return;
    }
    setState(() => _handling = true);
    HapticFeedback.mediumImpact();
    try {
      final user = await ref.read(friendsRepositoryProvider).lookupCode(code);
      if (!mounted) return;
      final added = await showModalBottomSheet<bool>(
        context: context,
        builder: (_) => _ScanResultSheet(user: user, code: code),
      );
      if (!mounted) return;
      if (added == true) {
        final router = GoRouter.of(context);
        showFriendToast(context, '已和 ${user.displayName} 成为好友');
        router.pop();
        return;
      }
    } catch (e) {
      if (mounted) _hint(SupabaseFriendsRepository.translate(e).message);
    }
    if (mounted) setState(() => _handling = false);
  }

  @override
  Widget build(BuildContext context) {
    final build = ref.watch(scannerBuilderProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _ScanColors.ink,
        body: Stack(
          fit: StackFit.expand,
          children: [
            build(onCode: _onCode, torch: _torch, paused: _handling),
            const IgnorePointer(child: CustomPaint(painter: _FinderPainter())),
            SafeArea(
              child: Column(
                children: [
                  SizedBox(
                    height: AppSize.pageHeader,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12),
                      child: Row(
                        children: [
                          _GlassButton(icon: AppIcons.back, tooltip: '返回', onPressed: () => context.pop()),
                          const Spacer(),
                          Text('扫一扫', style: AppText.titleSmall.copyWith(color: _ScanColors.paper)),
                          const Spacer(),
                          _GlassButton(
                            icon: _torch ? AppIcons.flashlightOn : AppIcons.flashlight,
                            tooltip: _torch ? '关闭手电筒' : '打开手电筒',
                            onPressed: () => setState(() => _torch = !_torch),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.s24, 0, AppSpace.s24, AppSpace.s24),
                    child: Column(
                      children: [
                        Text('把对方的好友二维码放进框里',
                            textAlign: TextAlign.center, style: AppText.label.copyWith(color: _ScanColors.paper)),
                        const SizedBox(height: AppSpace.s20),
                        PressScale(
                          scale: PressScale.chipScale,
                          child: Material(
                            color: const Color(0x29FFFFFF),
                            shape: const StadiumBorder(side: BorderSide(color: Color(0x29FFFFFF), width: AppStroke.hairline)),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => context.pushReplacement('/friends/qr'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s20, vertical: AppSpace.s12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(AppIcons.qrCode, size: 20, color: _ScanColors.paper),
                                    const SizedBox(width: AppSpace.s8),
                                    Text('我的二维码',
                                        style: AppText.label.copyWith(color: _ScanColors.paper, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: PressScale.smallScale,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: const Color(0x29FFFFFF),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(dimension: 40, child: Icon(icon, size: 20, color: _ScanColors.paper)),
          ),
        ),
      ),
    );
  }
}

/// 取景框：四周压暗，中间留一个圆角方孔，四个角各一段白色折线。
class _FinderPainter extends CustomPainter {
  const _FinderPainter();

  static Rect holeFor(Size size) {
    final side = (size.width - 96).clamp(200.0, 300.0);
    return Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.44), width: side, height: side);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(holeFor(size), const Radius.circular(AppRadius.lg));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = _ScanColors.veil,
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33FFFFFF),
    );
    // 四个角：把完整的圆角框裁成四段
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = _ScanColors.paper;
    const arm = 28.0;
    final r = hole.outerRect;
    canvas.save();
    canvas.clipPath(Path()
      ..addRect(Rect.fromLTWH(r.left - 4, r.top - 4, arm + 4, arm + 4))
      ..addRect(Rect.fromLTWH(r.right - arm, r.top - 4, arm + 4, arm + 4))
      ..addRect(Rect.fromLTWH(r.left - 4, r.bottom - arm, arm + 4, arm + 4))
      ..addRect(Rect.fromLTWH(r.right - arm, r.bottom - arm, arm + 4, arm + 4)));
    canvas.drawRRect(hole, corner);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FinderPainter old) => false;
}

/// 扫到之后弹出：对方是谁 + 「加为好友」。
class _ScanResultSheet extends ConsumerStatefulWidget {
  const _ScanResultSheet({required this.user, required this.code});
  final UserCard user;
  final String code;

  @override
  ConsumerState<_ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends ConsumerState<_ScanResultSheet> {
  bool _busy = false;

  Future<void> _add() async {
    setState(() => _busy = true);
    try {
      await ref.read(friendsControllerProvider.notifier).addByCode(widget.code);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showFriendError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = widget.user;
    final (String? note, Widget action) = switch (u.relation) {
      FriendRelation.self => (
          '这是你自己的二维码',
          PressScale(child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))),
        ),
      FriendRelation.friend => (
          '你们已经是好友了',
          PressScale(
            child: FilledButton(
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.pop(context);
                router.pushReplacement('/friends/chat/${u.id}');
              },
              child: const Text('去聊天'),
            ),
          ),
        ),
      _ => (
          null,
          PressScale(
            child: FilledButton(
              style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.buttonLarge))),
              onPressed: _busy ? null : _add,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('加为好友'),
            ),
          ),
        ),
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s20, AppSpace.s4, AppSpace.s20, AppSpace.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: UserAvatar(u, size: 72, ring: true)),
            const SizedBox(height: AppSpace.s12),
            Text(u.displayName,
                textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.titleMedium.copyWith(color: c.text)),
            const SizedBox(height: 2),
            Text(note ?? '@${u.username}', textAlign: TextAlign.center, style: AppText.label.copyWith(color: c.text3)),
            const SizedBox(height: AppSpace.s24),
            action,
          ],
        ),
      ),
    );
  }
}
