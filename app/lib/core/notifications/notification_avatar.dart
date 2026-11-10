import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 给系统通知用的头像：取到图片后裁成圆形的小 PNG。
/// 内置头像读 App 里的图，自己上传的头像从云端下载；失败返回 null，通知照常发（只是没有头像）。
class NotificationAvatar {
  NotificationAvatar._();

  static const double size = 192;
  static final Map<String, Uint8List> _cache = {};

  static Future<Uint8List?> circlePng(String kind, String ref) async {
    final key = '$kind:$ref';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final raw = await _raw(kind, ref);
      if (raw == null) return null;
      final png = await _toCircle(raw);
      if (_cache.length > 40) _cache.clear();
      return _cache[key] = png;
    } catch (e) {
      debugPrint('通知头像准备失败：$e');
      return null;
    }
  }

  static Future<Uint8List?> _raw(String kind, String ref) async {
    if (kind != 'custom') {
      final data = await rootBundle.load('assets/avatars/$ref.png');
      return data.buffer.asUint8List();
    }
    final url = Supabase.instance.client.storage.from('avatars').getPublicUrl(ref);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 8))) {
        builder.add(chunk);
        if (builder.length > 4 * 1024 * 1024) return null;
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static Future<Uint8List> _toCircle(Uint8List raw) async {
    final codec = await ui.instantiateImageCodec(raw, targetWidth: size.toInt(), targetHeight: size.toInt());
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const rect = ui.Rect.fromLTWH(0, 0, size, size);
    canvas.clipPath(ui.Path()..addOval(rect));
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      rect,
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(size.toInt(), size.toInt());
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    src.dispose();
    out.dispose();
    picture.dispose();
    codec.dispose();
    return data!.buffer.asUint8List();
  }

  /// iOS 的通知附件必须是磁盘上的文件：把头像写进临时目录，返回路径。
  static Future<String?> asFile(String kind, String ref, Uint8List png) async {
    try {
      final dir = await getTemporaryDirectory();
      final name = 'chat_avatar_${(kind + ref).hashCode & 0x7fffffff}.png';
      final f = File('${dir.path}/$name');
      if (!await f.exists()) await f.writeAsBytes(png);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}
