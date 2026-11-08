import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_fitness/features/update/update_models.dart';
import 'package:my_fitness/features/update/update_service.dart';

/// 本地起一个小服务器，模拟各种好的、坏的下载线路，真正跑一遍下载、断点续传、换线路。
void main() {
  late HttpServer server;
  late Directory tmp;
  late Uint8List data; // 3 MB 的假安装包
  late String sha;
  late String base;
  final hits = <String>[]; // 服务器收到的请求："路径 Range头"

  setUpAll(() {
    HttpOverrides.global = null; // 不要被 flutter_test 的假网络拦住
    data = Uint8List.fromList(List.generate(3 * 1024 * 1024, (i) => (i * 31 + i ~/ 7) & 0xff));
    sha = sha256.convert(data).toString();
  });

  setUp(() async {
    hits.clear();
    tmp = await Directory.systemTemp.createTemp('upd');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      final range = req.headers.value('range') ?? '';
      hits.add('${req.uri.path} $range');
      final res = req.response;
      Future<void> serve(Uint8List bytes, {bool honorRange = true, int? dropAfter}) async {
        var start = 0;
        final m = RegExp(r'bytes=(\d+)-').firstMatch(range);
        if (honorRange && m != null) start = int.parse(m.group(1)!);
        res.statusCode = start > 0 ? 206 : 200;
        if (start > 0) res.headers.set('content-range', 'bytes $start-${bytes.length - 1}/${bytes.length}');
        res.contentLength = bytes.length - start;
        final body = bytes.sublist(start);
        if (dropAfter != null && dropAfter < body.length) {
          final socket = await res.detachSocket();
          socket.add(body.sublist(0, dropAfter));
          await socket.flush();
          socket.destroy();
          return;
        }
        res.add(body);
        await res.close();
      }

      final path = req.uri.path;
      if (path == '/ok') return serve(data);
      if (path == '/norange') return serve(data, honorRange: false);
      if (path == '/drop') return serve(data, dropAfter: 1024 * 1024);
      if (path == '/stuck') {
        // 只能下到第 1 MB，再往后（带 Range 要后面的部分）就一直报错
        if (range.isNotEmpty) {
          res.statusCode = 500;
          return res.close();
        }
        return serve(data, dropAfter: 1024 * 1024);
      }
      if (path == '/dropOnce') {
        return serve(data, dropAfter: hits.where((h) => h.startsWith('/dropOnce')).length == 1 ? 1024 * 1024 : null);
      }
      if (path == '/corrupt') return serve(Uint8List.fromList(data.map((b) => b ^ 0xff).toList()));
      if (path == '/html') {
        res.statusCode = 200;
        res.write('<html>blocked</html>');
        return res.close();
      }
      if (path.startsWith('/seg')) {
        final i = int.parse(path.substring(4));
        final cut = [0, 1000000, 2000000, data.length];
        return serve(Uint8List.sublistView(data, cut[i], cut[i + 1]));
      }
      res.statusCode = 500;
      await res.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  UpdateService svc() => UpdateService(
        tempDir: () async => tmp,
        retryDelay: Duration.zero,
        stallTimeout: const Duration(seconds: 3),
        connectTimeout: const Duration(seconds: 2),
        storageBase: '$base/storage',
      );

  AppUpdate update(String path, {DownloadSource? storage, String? shaOverride, int? size}) => AppUpdate(
        version: '9.9.9',
        notes: '',
        pageUrl: '$base/page',
        assetName: 'my-fitness-9.9.9.apk',
        assetUrl: '$base$path',
        assetSize: size ?? data.length,
        sha256: shaOverride ?? sha,
        storage: storage,
        mirrors: const [],
      );

  final segs = DownloadSource('备用服务器', [
    for (final (i, n) in [1000000, 1000000, 3 * 1024 * 1024 - 2000000].indexed) DownloadSegment('SERVER/seg$i', n),
  ]);
  DownloadSource storage() => DownloadSource(segs.label, [for (final s in segs.segments) DownloadSegment(s.url.replaceFirst('SERVER', base), s.size)]);

  Future<File> run(AppUpdate u, {DownloadCancel? cancel, List<String>? statuses}) =>
      svc().download(u, (_, _) {}, cancel ?? DownloadCancel(), onStatus: statuses?.add);

  test('正常下载：一条线路下完，校验通过', () async {
    final f = await run(update('/ok'));
    expect(await f.readAsBytes(), data);
    expect(f.path.endsWith('my-fitness-9.9.9.apk'), isTrue);
    expect(File('${f.path}.part').existsSync(), isFalse);
  });

  test('第一条线路返回 500，自动换到下一条', () async {
    final statuses = <String>[];
    final f = await run(update('/ok', storage: DownloadSource('备用服务器', [DownloadSegment('$base/nothing', data.length)])), statuses: statuses);
    expect(await f.readAsBytes(), data);
    expect(statuses.any((s) => s.contains('线路 1/2：备用服务器')), isTrue);
    expect(statuses.any((s) => s.contains('线路 2/2：GitHub 官方')), isTrue);
  });

  test('备用服务器分三段，拼起来就是完整安装包', () async {
    final f = await run(update('/nothing', storage: storage()));
    expect(await f.readAsBytes(), data);
    expect(hits.where((h) => h.startsWith('/seg')).length, 3);
    expect(hits.where((h) => h.startsWith('/nothing')).length, 0);
  });

  test('中途断线：下一条线路从断点继续（带 Range），不重新下', () async {
    final f = await run(update('/ok', storage: DownloadSource('备用服务器', [DownloadSegment('$base/drop', data.length)])));
    expect(await f.readAsBytes(), data);
    expect(hits.any((h) => h.startsWith('/ok bytes=1048576-')), isTrue, reason: hits.join('\n'));
  });

  test('同一条线路断线后，下一轮继续用它也能从断点接上', () async {
    final f = await run(update('/dropOnce'));
    expect(await f.readAsBytes(), data);
    expect(hits.any((h) => h.startsWith('/dropOnce bytes=1048576-')), isTrue, reason: hits.join('\n'));
  });

  test('服务器不支持断点续传（回 200）：丢掉重复的前半段，结果仍然正确', () async {
    final f = await run(update('/norange', storage: DownloadSource('备用服务器', [DownloadSegment('$base/drop', data.length)])));
    expect(await f.readAsBytes(), data);
  });

  test('上次没下完留下的 .part 会接着下', () async {
    final dir = Directory('${tmp.path}/update')..createSync();
    File('${dir.path}/my-fitness-9.9.9.apk.part').writeAsBytesSync(data.sublist(0, 2 * 1024 * 1024));
    final f = await run(update('/ok'));
    expect(await f.readAsBytes(), data);
    expect(hits.where((h) => h.startsWith('/ok')), ['/ok bytes=2097152-']);
  });

  test('代理返回内容被篡改（校验值不对）：丢掉并换线路', () async {
    final f = await run(update('/ok', storage: DownloadSource('备用服务器', [DownloadSegment('$base/corrupt', data.length)])));
    expect(await f.readAsBytes(), data);
  });

  test('代理返回一页网页提示（长度不对）：换线路', () async {
    final f = await run(update('/ok', storage: DownloadSource('备用服务器', [DownloadSegment('$base/html', data.length)])));
    expect(await f.readAsBytes(), data);
    expect(hits.where((h) => h.startsWith('/ok')), ['/ok ']); // 网页提示不会混进文件，GitHub 线路从头下，不是接着下
  });

  test('已经下好的安装包不再重复下载', () async {
    await run(update('/ok'));
    hits.clear();
    final f = await run(update('/ok'));
    expect(await f.readAsBytes(), data);
    expect(hits, isEmpty);
  });

  test('所有线路都失败：给出中文说明，并保留已下载的部分', () async {
    final u = update('/stuck', storage: DownloadSource('备用服务器', [DownloadSegment('$base/nothing', data.length)]));
    await expectLater(
      run(u),
      throwsA(isA<UpdateException>().having((e) => e.message, 'message', allOf(contains('所有下载线路都失败了'), contains('备用服务器：服务器返回 500'), contains('GitHub 官方')))),
    );
    final part = File('${tmp.path}/update/my-fitness-9.9.9.apk.part');
    expect(part.existsSync(), isTrue);
    expect(part.lengthSync(), 1024 * 1024);
  });

  test('取消下载', () async {
    final cancel = DownloadCancel();
    final u = update('/ok');
    final future = svc().download(u, (got, _) => cancel.cancelled = true, cancel);
    await expectLater(future, throwsA(isA<UpdateException>().having((e) => e.message, 'message', '已取消')));
  });

  group('查版本', () {
    Future<List<dynamic>> failReleases() async => throw const SocketException('Failed host lookup');
    Future<String> failAtom() async => throw TimeoutException('x');
    final manifest = {
      'version': '9.9.9',
      'notes': '新东西',
      'asset': {'name': 'my-fitness-9.9.9.apk', 'size': 3145728, 'sha256': 'a' * 64},
      'parts': [
        {'path': 'android/9.9.9/a.part0', 'size': 2097152},
        {'path': 'android/9.9.9/a.part1', 'size': 1048576},
      ],
    };
    final releases = [
      {
        'tag_name': 'v9.9.9',
        'body': 'GitHub 说明',
        'html_url': 'https://github.com/x/y/releases/tag/v9.9.9',
        'assets': [
          {'name': 'my-fitness-9.9.9.apk', 'browser_download_url': 'https://github.com/x/y/a.apk', 'size': 3145728, 'digest': 'sha256:${'b' * 64}'},
        ],
      }
    ];

    test('GitHub API 和备用服务器都连不上，靠 releases.atom 也能发现新版', () async {
      final s = UpdateService(
        fetchReleases: failReleases,
        fetchManifest: (_) async => throw TimeoutException('x'),
        fetchAtom: () async => '<entry><link rel="alternate" href="https://github.com/$kRepo/releases/tag/v9.9.9"/></entry>'
            '<entry><link href="https://github.com/$kRepo/releases/tag/v1.0.0"/></entry>',
      );
      final u = await s.check(current: '2.5.0', ios: false);
      expect(u?.version, '9.9.9');
      expect(u?.assetUrl, 'https://github.com/$kRepo/releases/download/v9.9.9/my-fitness-9.9.9.apk');
      expect(u?.storage, isNull);
    });

    test('备用服务器信息最全：带分段与校验值；GitHub 的说明/校验值补进来', () async {
      final s = UpdateService(
        fetchReleases: () async => releases,
        fetchManifest: (_) async => manifest,
        fetchAtom: failAtom,
        storageBase: 'https://s.example/storage',
      );
      final u = (await s.check(current: '2.5.0', ios: false))!;
      expect(u.storage?.segments.map((e) => e.url), [
        'https://s.example/storage/app-releases/android/9.9.9/a.part0',
        'https://s.example/storage/app-releases/android/9.9.9/a.part1',
      ]);
      expect(u.sha256, 'a' * 64);
      expect(u.notes, '新东西');
      expect(u.sources.map((e) => e.label), ['备用服务器', 'GitHub 官方', '加速线路一', '加速线路二']);
    });

    test('只有 GitHub API 通：照常发现新版，并带上 GitHub 给的校验值', () async {
      final s = UpdateService(
        fetchReleases: () async => releases,
        fetchManifest: (_) async => throw TimeoutException('x'),
        fetchAtom: failAtom,
      );
      final u = (await s.check(current: '2.5.0', ios: false))!;
      expect(u.sha256, 'b' * 64);
      expect(u.storage, isNull);
    });

    test('已是最新版：返回 null；全部连不上：抛中文错误', () async {
      final latest = UpdateService(fetchReleases: () async => releases, fetchManifest: (_) async => manifest, fetchAtom: failAtom);
      expect(await latest.check(current: '9.9.9', ios: false), isNull);
      final dead = UpdateService(fetchReleases: failReleases, fetchManifest: (_) async => throw TimeoutException('x'), fetchAtom: failAtom);
      await expectLater(
        dead.check(current: '2.5.0', ios: false),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message', allOf(contains('连不上更新服务器'), contains('域名解析失败')))),
      );
    });
  });

  group('manifest 解析', () {
    String url(String p) => 'https://s/$p';
    test('分段大小之和对不上总大小时不使用备用线路', () {
      final u = updateFromManifest({
        'version': '3.0.0',
        'asset': {'name': 'a.apk', 'size': 100},
        'parts': [
          {'path': 'p0', 'size': 40},
          {'path': 'p1', 'size': 40},
        ],
      }, ios: false, current: '2.0.0', fileUrl: url);
      expect(u?.storage, isNull);
    });

    test('下发的加速代理列表会补上结尾斜杠，只收 https', () {
      final u = updateFromManifest({
        'version': '3.0.0',
        'mirrors': ['https://m1.example', 'http://bad.example/', 'https://m2.example/'],
      }, ios: true, current: '2.0.0', fileUrl: url);
      expect(u?.mirrors, ['https://m1.example/', 'https://m2.example/']);
      expect(u?.assetName, 'my-fitness-ios-3.0.0-unsigned.ipa');
      expect(u?.assetUrl, 'https://github.com/$kRepo/releases/download/ios-v3.0.0/my-fitness-ios-3.0.0-unsigned.ipa');
    });

    test('版本不比当前新就是 null', () {
      expect(updateFromManifest({'version': '2.0.0'}, ios: false, current: '2.0.0', fileUrl: url), isNull);
      expect(jsonEncode(null), 'null');
    });
  });
}
