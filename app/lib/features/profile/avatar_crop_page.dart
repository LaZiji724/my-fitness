import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';

/// 头像裁切：照片自动铺满一个圆，可以拖动、双指缩放来调整，点「使用」得到裁好的正方形 PNG
/// （显示头像的地方会再切成圆形）。
///
/// 返回 [Uint8List]（384×384 的 PNG）；点返回或取消返回 null。
class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  /// 输出边长（像素）
  static const outputSize = 384;

  static Future<Uint8List?> open(BuildContext context, Uint8List bytes) =>
      Navigator.of(context).push<Uint8List>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => AvatarCropPage(imageBytes: bytes)));

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final _boundary = GlobalKey();
  final _controller = TransformationController();
  Size? _imageSize;
  bool _failed = false;
  bool _saving = false;
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final size = Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      codec.dispose();
      if (mounted) setState(() => _imageSize = size);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 把图片按「短边正好填满取景框」的大小摆好，并居中。
  Size _fitSize(Size image, double viewport) {
    final scale = viewport / (image.width < image.height ? image.width : image.height);
    return Size(image.width * scale, image.height * scale);
  }

  void _center(Size fit, double viewport) {
    final dx = (viewport - fit.width) / 2;
    final dy = (viewport - fit.height) / 2;
    _controller.value = Matrix4.identity()..setTranslationRaw(dx, dy, 0);
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ratio = AvatarCropPage.outputSize / boundary.size.width;
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted) return;
      Navigator.of(context).pop(data!.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('裁切失败，换一张照片试试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.hero,
      appBar: AppBar(
        backgroundColor: c.hero,
        foregroundColor: c.onHero,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(icon: Icon(AppIcons.close, color: c.onHero), tooltip: '取消', onPressed: () => Navigator.of(context).pop()),
        title: Text('调整头像', style: AppText.titleSmall.copyWith(color: c.onHero)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final viewport = (box.biggest.shortestSide - AppSpace.pageGutter * 2).clamp(160.0, 420.0);
                    final image = _imageSize;
                    if (_failed) {
                      return Text('这张图片打不开，换一张试试', style: AppText.body.copyWith(color: c.onHero2));
                    }
                    if (image == null) return const CircularProgressIndicator(strokeWidth: 2);
                    final fit = _fitSize(image, viewport);
                    if (_viewport != viewport) {
                      _viewport = viewport;
                      _center(fit, viewport);
                    }
                    return SizedBox.square(
                      dimension: viewport,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 被截取的区域：拖动、缩放
                          RepaintBoundary(
                            key: _boundary,
                            child: ColoredBox(
                              color: c.hero,
                              child: InteractiveViewer(
                                transformationController: _controller,
                                constrained: false,
                                minScale: 1,
                                maxScale: 5,
                                boundaryMargin: EdgeInsets.zero,
                                child: Image.memory(
                                  widget.imageBytes,
                                  width: fit.width,
                                  height: fit.height,
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high,
                                  // 大照片没必要整张解码
                                  cacheWidth: fit.width >= fit.height ? null : 1400,
                                  cacheHeight: fit.width >= fit.height ? 1400 : null,
                                ),
                              ),
                            ),
                          ),
                          // 圆形取景框：圈外压暗，圈上一道细橙线
                          IgnorePointer(child: CustomPaint(painter: _CircleMaskPainter(shade: c.hero.withValues(alpha: 0.62), ring: c.accent))),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s8),
              child: Text('拖动、双指缩放，让脸落在圆圈里', style: AppText.label.copyWith(color: c.onHero2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.pageGutter, AppSpace.s8, AppSpace.pageGutter, AppSpace.s16),
              child: PressScale(
                child: FilledButton(
                  onPressed: (_imageSize == null || _saving) ? null : _confirm,
                  style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.button))),
                  child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('使用这张'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleMaskPainter extends CustomPainter {
  const _CircleMaskPainter({required this.shade, required this.ring});

  final Color shade;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final circle = Path()..addOval(rect);
    final outside = Path.combine(PathOperation.difference, Path()..addRect(rect), circle);
    canvas.drawPath(outside, Paint()..color = shade);
    canvas.drawOval(
      rect.deflate(1),
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CircleMaskPainter old) => old.shade != shade || old.ring != ring;
}
