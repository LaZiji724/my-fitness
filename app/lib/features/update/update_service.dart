import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:my_fitness/features/update/update_models.dart';

const kReleasesApi = 'https://api.github.com/repos/LaZiji724/my-fitness/releases?per_page=30';

/// 取消下载用的小开关。
class DownloadCancel {
  bool cancelled = false;
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 检查并下载更新。仓库是公开的，读 Release 不需要任何密钥。
class UpdateService {
  UpdateService({Future<List<dynamic>> Function()? fetchReleases, Future<Directory> Function()? tempDir})
      : _fetchReleases = fetchReleases ?? _defaultFetch,
        _tempDir = tempDir ?? getTemporaryDirectory;

  final Future<List<dynamic>> Function() _fetchReleases;
  final Future<Directory> Function() _tempDir;

  static Future<List<dynamic>> _defaultFetch() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(kReleasesApi));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'my-fitness-app');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw UpdateException('检查更新失败（${res.statusCode}）');
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      final json = jsonDecode(body);
      if (json is! List) throw UpdateException('检查更新失败');
      return json;
    } finally {
      client.close(force: true);
    }
  }

  /// 有新版本返回它，已经是最新返回 null；网络问题抛 [UpdateException] 或其它异常。
  Future<AppUpdate?> check({required String current, required bool ios}) async {
    final releases = await _fetchReleases();
    return findUpdate(releases: releases, ios: ios, current: current);
  }

  /// 下载安装包到临时目录，返回文件。进度回调给界面画进度条。
  Future<File> download(AppUpdate update, void Function(int received, int total) onProgress, DownloadCancel cancel) async {
    final dir = Directory('${(await _tempDir()).path}/update');
    if (await dir.exists()) await dir.delete(recursive: true); // 清掉旧的安装包
    await dir.create(recursive: true);
    final target = File('${dir.path}/${update.assetName}');
    final part = File('${target.path}.part');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(update.assetUrl)); // 会自动跟随 GitHub 的跳转
      req.headers.set(HttpHeaders.userAgentHeader, 'my-fitness-app');
      final res = await req.close();
      if (res.statusCode != 200) throw UpdateException('下载失败（${res.statusCode}）');
      final total = res.contentLength > 0 ? res.contentLength : update.assetSize;
      final sink = part.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          if (cancel.cancelled) throw UpdateException('已取消');
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
      if (update.assetSize > 0 && received != update.assetSize) {
        throw UpdateException('下载不完整，请重试');
      }
      await part.rename(target.path);
      return target;
    } on TimeoutException {
      throw UpdateException('网络太慢，下载中断了，请重试');
    } finally {
      client.close(force: true);
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }
}

/// 安卓：调起系统安装器覆盖安装（见 MainActivity.kt）。
abstract class ApkInstaller {
  Future<bool> canInstall();
  Future<void> openInstallSettings();
  Future<void> install(String path);
}

class ChannelApkInstaller implements ApkInstaller {
  static const _channel = MethodChannel('com.hotchicken.my_fitness/installer');

  @override
  Future<bool> canInstall() async => await _channel.invokeMethod<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallSettings() => _channel.invokeMethod<void>('openInstallSettings');

  @override
  Future<void> install(String path) => _channel.invokeMethod<void>('install', {'path': path});
}

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
final apkInstallerProvider = Provider<ApkInstaller>((ref) => ChannelApkInstaller());

/// 本机当前版本号，如 2.3.0。
final currentVersionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

/// 是否启动时自动检查更新（测试里关掉，免得去连网）。
final autoUpdateCheckProvider = Provider<bool>((ref) => !Platform.environment.containsKey('FLUTTER_TEST'));

bool get isIosPlatform => defaultTargetPlatform == TargetPlatform.iOS;
