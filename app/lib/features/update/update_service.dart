import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:my_fitness/core/config/env.dart';
import 'package:my_fitness/features/update/update_models.dart';

const kReleasesApi = 'https://api.github.com/repos/$kRepo/releases?per_page=30';
const kReleasesAtom = 'https://github.com/$kRepo/releases.atom';
const kReleasesPage = 'https://github.com/$kRepo/releases';

/// Supabase 存储里放更新信息和备用安装包的桶（公开可读，由发布流程上传）。
const kStorageBucket = 'app-releases';

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

class _Cancelled implements Exception {}

class _TooSlow implements Exception {}

/// 检查并下载更新。
///
/// 国内网络访问 GitHub 很不稳定（api.github.com、下载用的 githubusercontent.com 时好时坏），
/// 所以这里做了多条后路：
/// - 查版本：Supabase 上的 manifest、GitHub API、GitHub 的 releases.atom，三路同时问，谁先给出新版就用谁；
/// - 下载：Supabase 备用服务器 → GitHub 官方 → 各加速代理，一条失败自动换下一条，
///   整体最多轮 3 圈，已下载的部分保留，换线路后从断点继续（Range）；
/// - 下载完校验大小和 SHA-256，不对就换线路重来。
class UpdateService {
  UpdateService({
    Future<List<dynamic>> Function()? fetchReleases,
    Future<Map<dynamic, dynamic>> Function(bool ios)? fetchManifest,
    Future<String> Function()? fetchAtom,
    Future<Directory> Function()? tempDir,
    String? storageBase,
    this.retryDelay = const Duration(seconds: 3),
    this.stallTimeout = const Duration(seconds: 20),
    this.slowCheckAfter = const Duration(seconds: 15),
    this.slowBytesPerSecond = 30 * 1024,
    this.connectTimeout = const Duration(seconds: 8),
  })  : _fetchReleases = fetchReleases ?? (() async => _jsonList(await _getText(kReleasesApi, headers: _githubHeaders))),
        _fetchAtom = fetchAtom ?? (() => _getText(kReleasesAtom)),
        _tempDir = tempDir ?? getTemporaryDirectory,
        _storageBase = storageBase ?? (Env.supabaseUrl.isEmpty ? '' : '${Env.supabaseUrl}/storage/v1/object/public') {
    _fetchManifest = fetchManifest ?? _defaultManifest;
  }

  final Future<List<dynamic>> Function() _fetchReleases;
  final Future<String> Function() _fetchAtom;
  late final Future<Map<dynamic, dynamic>> Function(bool ios) _fetchManifest;
  final Future<Directory> Function() _tempDir;
  final String _storageBase;

  /// 下面几项在测试里调小。
  final Duration retryDelay;
  final Duration stallTimeout;
  final Duration slowCheckAfter;
  final int slowBytesPerSecond;
  final Duration connectTimeout;

  static const _rounds = 3;

  static const _githubHeaders = {
    HttpHeaders.acceptHeader: 'application/vnd.github+json',
  };

  static List<dynamic> _jsonList(String body) {
    final json = jsonDecode(body);
    if (json is! List) throw UpdateException('GitHub 返回的内容不对');
    return json;
  }

  /// 普通 GET 取文本。每一步都有超时，不会一直卡着。
  static Future<String> _getText(String url, {Map<String, String> headers = const {}, Duration connect = const Duration(seconds: 8)}) async {
    final client = HttpClient()..connectionTimeout = connect;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.userAgentHeader, 'my-fitness-app');
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateException('服务器返回 ${res.statusCode}');
      }
      return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    } finally {
      client.close(force: true);
    }
  }

  String _storageUrl(String path) => '$_storageBase/$kStorageBucket/$path';

  Future<Map<dynamic, dynamic>> _defaultManifest(bool ios) async {
    if (_storageBase.isEmpty) throw UpdateException('没有配置备用服务器');
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 60000; // 每分钟换一次，避开缓存
    final body = await _getText(_storageUrl('${ios ? 'ios' : 'android'}.json?t=$stamp'));
    final json = jsonDecode(body);
    if (json is! Map) throw UpdateException('更新信息格式不对');
    return json;
  }

  /// 有新版本返回它，已经是最新返回 null；三路都连不上抛 [UpdateException]。
  ///
  /// 三路同时发出：Supabase 备用服务器（最稳，带分段安装包和校验值）、GitHub API、GitHub releases.atom。
  /// 只要有一路给出新版就用，再多等一小会儿让信息更全的那路也有机会回来。
  Future<AppUpdate?> check({required String current, required bool ios}) async {
    final candidates = <(int, AppUpdate)>[]; // (优先级，越小越好; 版本)
    final errors = <String>[];
    var pending = 3;
    var anySucceeded = false;
    final done = Completer<void>();
    Timer? grace;

    void finishOne() {
      pending--;
      if (pending == 0 && !done.isCompleted) done.complete();
    }

    void run(int priority, String label, Future<AppUpdate?> Function() job) {
      job().timeout(const Duration(seconds: 25)).then((update) {
        anySucceeded = true;
        if (update != null) {
          candidates.add((priority, update));
          // 第一个新版出现后再等 1.5 秒，让信息更全的线路也有机会
          grace ??= Timer(const Duration(milliseconds: 1500), () {
            if (!done.isCompleted) done.complete();
          });
        }
      }).catchError((Object e) {
        errors.add('$label：${describeNetworkError(e)}');
      }).whenComplete(finishOne);
    }

    run(0, '备用服务器', () async {
      final json = await _fetchManifest(ios);
      return updateFromManifest(json, ios: ios, current: current, fileUrl: _storageUrl);
    });
    run(1, 'GitHub', () async => findUpdate(releases: await _fetchReleases(), ios: ios, current: current));
    run(2, 'GitHub 备用', () async => findUpdateFromAtom(atom: await _fetchAtom(), ios: ios, current: current));

    await done.future;
    grace?.cancel();

    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final byVersion = compareVersions(parseVersion(b.$2.version)!, parseVersion(a.$2.version)!);
        return byVersion != 0 ? byVersion : a.$1.compareTo(b.$1);
      });
      var best = candidates.first.$2;
      // 信息更全的合并进来：备用服务器的分段和校验值、GitHub 的校验值与说明
      for (final c in candidates.skip(1)) {
        if (c.$2.version != best.version) continue;
        best = AppUpdate(
          version: best.version,
          notes: best.notes.isNotEmpty ? best.notes : c.$2.notes,
          pageUrl: best.pageUrl,
          assetName: best.assetName,
          assetUrl: best.assetUrl,
          assetSize: best.assetSize > 0 ? best.assetSize : c.$2.assetSize,
          sha256: best.sha256 ?? c.$2.sha256,
          storage: best.storage ?? c.$2.storage,
          mirrors: best.mirrors,
        );
      }
      return best;
    }
    if (anySucceeded) return null;
    throw UpdateException('连不上更新服务器：${errors.join('；')}');
  }

  /// 查版本时没拿到备用服务器的信息（比如当时连不上），下载前再补问一次。
  Future<AppUpdate> _withStorage(AppUpdate update) async {
    if (update.storage != null || _storageBase.isEmpty) return update;
    try {
      final ios = update.assetName.toLowerCase().endsWith('.ipa');
      final json = await _fetchManifest(ios).timeout(const Duration(seconds: 8));
      final m = updateFromManifest(json, ios: ios, current: '0.0.0', fileUrl: _storageUrl);
      if (m == null || m.version != update.version) return update;
      return update.copyWith(
        storage: m.storage,
        sha256: update.sha256 ?? m.sha256,
        mirrors: m.mirrors,
      );
    } catch (_) {
      return update;
    }
  }

  /// 下载安装包到临时目录，返回文件。进度回调给界面画进度条，[onStatus] 报告当前走的线路。
  ///
  /// 已下载的部分（.part）会保留：点「重试」、换线路、甚至下次重新打开更新窗口，都从断点继续。
  Future<File> download(
    AppUpdate update,
    void Function(int received, int total) onProgress,
    DownloadCancel cancel, {
    void Function(String status)? onStatus,
  }) async {
    final dir = Directory('${(await _tempDir()).path}/update');
    await dir.create(recursive: true);
    final target = File('${dir.path}/${update.assetName}');
    final part = File('${target.path}.part');
    // 清掉别的版本留下的旧文件，只保留这个版本的成品和断点
    await for (final e in dir.list()) {
      if (e is File && e.path != target.path && e.path != part.path) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
    if (await target.exists()) {
      if (await _verify(target, update)) {
        final n = await target.length();
        onProgress(n, n);
        return target;
      }
      await target.delete();
    }

    onStatus?.call('正在连接…');
    final withStorage = await _withStorage(update);
    if (cancel.cancelled) throw UpdateException('已取消');
    final sources = withStorage.sources;
    final failures = <String>[];

    for (var round = 0; round < _rounds; round++) {
      for (var i = 0; i < sources.length; i++) {
        final source = sources[i];
        onStatus?.call('线路 ${i + 1}/${sources.length}：${source.label}${round > 0 ? '（第 ${round + 1} 轮）' : ''}');
        try {
          await _fetchFrom(
            source,
            part,
            withStorage,
            onProgress,
            cancel,
            fast: round == 0 && sources.length > 1, // 第一轮：太慢就换线路；之后哪怕慢也坚持下完
          );
          if (!await _verify(part, withStorage)) {
            try {
              await part.delete();
            } catch (_) {}
            failures.add('${source.label}：下载的文件校验不通过，已换线路重新下');
            continue;
          }
          await part.rename(target.path);
          return target;
        } on _Cancelled {
          throw UpdateException('已取消');
        } catch (e) {
          if (cancel.cancelled) throw UpdateException('已取消');
          failures.add('${source.label}：${describeNetworkError(e)}');
          if (_isDiskFull(e)) throw UpdateException('手机存储空间不足，清理一下再试');
        }
      }
      if (round < _rounds - 1) {
        onStatus?.call('网络不太好，稍后重试…');
        await _sleep(retryDelay, cancel);
      }
    }
    throw UpdateException('所有下载线路都失败了。${failures.join('\n')}');
  }

  Future<void> _sleep(Duration d, DownloadCancel cancel) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      if (cancel.cancelled) throw _Cancelled();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// 大小对、（有校验值时）SHA-256 对，才算下载完整。
  Future<bool> _verify(File file, AppUpdate u) async {
    final len = await file.length();
    if (u.assetSize > 0 && len != u.assetSize) return false;
    final want = u.sha256;
    if (want == null) return true;
    final got = (await sha256.bind(file.openRead()).first).toString();
    return got == want;
  }

  /// 从一条线路接着下（.part 已经有多少字节就从多少字节处继续），下满为止；中途出错抛异常，已写入的保留。
  Future<void> _fetchFrom(
    DownloadSource source,
    File part,
    AppUpdate update,
    void Function(int received, int total) onProgress,
    DownloadCancel cancel, {
    required bool fast,
  }) async {
    final total = source.total > 0 ? source.total : update.assetSize;
    var pos = await part.exists() ? await part.length() : 0;
    if (total > 0 && pos > total) {
      await part.writeAsBytes(const [], flush: true); // 比应有的还大，肯定坏了，从头来
      pos = 0;
    }
    if (total > 0 && pos == total) return; // 已经下满，交给校验
    onProgress(pos, total);

    final sink = part.openWrite(mode: FileMode.append);
    int? rollbackTo; // 服务器说完了却没给够：这段内容不可信（多半是网页提示），写进去的要撤回
    final client = HttpClient()
      ..connectionTimeout = fast ? connectTimeout : connectTimeout * 2
      ..autoUncompress = false;
    try {
      var segStart = 0;
      for (final seg in source.segments) {
        final known = seg.size > 0;
        final segEnd = known ? segStart + seg.size : (1 << 62);
        if (pos < segEnd) {
          final skip = pos - segStart;
          final req = await client.getUrl(Uri.parse(seg.url));
          req.headers
            ..set(HttpHeaders.userAgentHeader, 'my-fitness-app')
            ..set(HttpHeaders.acceptEncodingHeader, 'identity');
          if (skip > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$skip-');
          final res = await req.close().timeout(stallTimeout);
          if (res.statusCode != 200 && res.statusCode != 206) {
            await res.drain<void>().catchError((Object _) {});
            throw UpdateException('服务器返回 ${res.statusCode}');
          }
          // 先核对服务器说的长度/类型：代理出错时常返回一页网页提示，不能把它当安装包写进去
          final type = res.headers.contentType?.mimeType ?? '';
          if (type == 'text/html') throw UpdateException('返回的是网页，不是安装包');
          if (known && res.contentLength >= 0) {
            final expected = res.statusCode == 206 ? seg.size - skip : seg.size;
            if (res.contentLength != expected) throw UpdateException('服务器给的文件大小不对');
          }
          // 服务器不支持断点（直接回 200）就丢掉前面已有的那部分；回 206 要确认起点对得上
          var discard = 0;
          if (skip > 0) {
            if (res.statusCode == 200) {
              discard = skip;
            } else {
              final range = res.headers.value(HttpHeaders.contentRangeHeader) ?? '';
              if (!range.startsWith('bytes $skip-')) throw UpdateException('服务器的断点续传不对');
            }
          }
          final segPos = pos;
          final dataStart = DateTime.now();
          final posAtStart = pos;
          var sinceFlush = 0;
          var segGot = skip;
          await for (final chunk in res.timeout(stallTimeout)) {
            if (cancel.cancelled) throw _Cancelled();
            var data = chunk;
            if (discard > 0) {
              if (data.length <= discard) {
                discard -= data.length;
                continue;
              }
              data = data.sublist(discard);
              discard = 0;
            }
            if (known && segGot + data.length > seg.size) data = data.sublist(0, seg.size - segGot);
            sink.add(data);
            segGot += data.length;
            pos += data.length;
            sinceFlush += data.length;
            if (sinceFlush >= 512 * 1024) {
              sinceFlush = 0;
              await sink.flush();
            }
            onProgress(pos, total);
            if (fast) {
              final secs = DateTime.now().difference(dataStart);
              if (secs >= slowCheckAfter && (pos - posAtStart) * 1000 / secs.inMilliseconds < slowBytesPerSecond) throw _TooSlow();
            }
            if (known && segGot >= seg.size) break;
          }
          await sink.flush();
          if (known && segGot < seg.size) {
            rollbackTo = segPos;
            throw UpdateException('服务器没有给够内容');
          }
        }
        segStart = known ? segEnd : segStart;
      }
    } finally {
      try {
        await sink.close();
      } catch (_) {}
      client.close(force: true);
      if (rollbackTo != null) {
        final raf = await part.open(mode: FileMode.append);
        try {
          await raf.truncate(rollbackTo);
        } finally {
          await raf.close();
        }
      }
    }
  }
}

bool _isDiskFull(Object e) => e is FileSystemException && (e.osError?.errorCode == 28 || e.message.contains('No space'));

/// 把各种网络异常翻成一句看得懂的中文。
String describeNetworkError(Object e) {
  if (e is UpdateException) return e.message;
  if (e is _TooSlow) return '速度太慢，换线路';
  if (e is TimeoutException) return '连接超时';
  if (e is HandshakeException || e is TlsException) return '安全连接失败';
  if (e is SocketException) {
    final text = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    if (text.contains('lookup') || text.contains('resolve') || text.contains('nodename')) return '域名解析失败（可能被屏蔽）';
    if (text.contains('refused')) return '连接被拒绝';
    if (text.contains('reset')) return '连接被中断（可能被屏蔽）';
    return '网络连接失败';
  }
  if (e is HttpException) return '服务器响应异常';
  if (e is FormatException) return '返回的内容不对';
  if (e is FileSystemException) return _isDiskFull(e) ? '手机存储空间不足' : '写入文件失败';
  return '出错了';
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
