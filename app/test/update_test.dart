import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/update/update_models.dart';
import 'package:my_fitness/features/update/update_service.dart';
import 'package:my_fitness/features/update/update_ui.dart';

Map<String, dynamic> release(String tag, String asset, {bool draft = false, bool pre = false}) => {
      'tag_name': tag,
      'draft': draft,
      'prerelease': pre,
      'body': '## 更新内容\n- **新功能**',
      'html_url': 'https://github.com/x/y/releases/tag/$tag',
      'assets': [
        {'name': asset, 'browser_download_url': 'https://example.com/$asset', 'size': 1048576},
      ],
    };

final releases = [
  release('v2.3.0', 'my-fitness-2.3.0.apk'),
  release('ios-v2.3.0', 'my-fitness-ios-2.3.0-unsigned.ipa'),
  release('v2.10.0', 'my-fitness-2.10.0.apk', draft: true),
  release('v2.2.3', 'my-fitness-2.2.3.apk'),
  release('ios-v2.2.3', 'my-fitness-ios-2.2.3-unsigned.ipa'),
];

class FakeService extends UpdateService {
  FakeService(this.result) : super(fetchReleases: () async => []);
  final AppUpdate? result;
  int downloads = 0;

  @override
  Future<AppUpdate?> check({required String current, required bool ios}) async => result;

  @override
  Future<File> download(AppUpdate update, void Function(int, int) onProgress, DownloadCancel cancel, {void Function(String)? onStatus}) async {
    downloads++;
    onProgress(50, 100);
    return File('/tmp/${update.assetName}');
  }
}

class FakeInstaller implements ApkInstaller {
  FakeInstaller(this.allowed);
  bool allowed;
  final calls = <String>[];

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> install(String path) async => calls.add('install:$path');

  @override
  Future<void> openInstallSettings() async => calls.add('settings');
}

void main() {
  test('版本号解析与比较', () {
    expect(parseVersion('v2.3.0'), [2, 3, 0]);
    expect(parseVersion('ios-v2.3.0'), [2, 3, 0]);
    expect(parseVersion('2.3.0+15'), [2, 3, 0]);
    expect(parseVersion('abc'), isNull);
    expect(compareVersions([2, 10, 0], [2, 9, 9]), greaterThan(0));
    expect(compareVersions([2, 3, 0], [2, 3, 0]), 0);
  });

  test('安卓只看 v 开头的 apk，苹果只看 ios-v 开头的 ipa，跳过草稿', () {
    final a = findUpdate(releases: releases, ios: false, current: '2.2.3');
    expect(a?.version, '2.3.0');
    expect(a?.assetName, 'my-fitness-2.3.0.apk');
    final i = findUpdate(releases: releases, ios: true, current: '2.2.3');
    expect(i?.assetName, 'my-fitness-ios-2.3.0-unsigned.ipa');
    expect(findUpdate(releases: releases, ios: false, current: '2.3.0'), isNull);
    expect(findUpdate(releases: releases, ios: true, current: '2.3.1'), isNull);
  });

  Future<void> pumpDialog(WidgetTester tester, FakeService svc, FakeInstaller inst) async {
    final update = findUpdate(releases: releases, ios: false, current: '2.2.3')!;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        updateServiceProvider.overrideWithValue(svc),
        apkInstallerProvider.overrideWithValue(inst),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(child: ElevatedButton(onPressed: () => showUpdateDialog(ctx, update, '2.2.3'), child: const Text('go'))),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('安卓：没授权时先去设置，授权后再点安装才装', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final svc = FakeService(null);
      final inst = FakeInstaller(false);
      await pumpDialog(tester, svc, inst);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.textContaining('2.3.0'), findsWidgets);
      await tester.tap(find.text('更新'));
      await tester.pumpAndSettle();
      expect(svc.downloads, 1);
      expect(inst.calls, ['settings']);
      expect(find.textContaining('允许安装应用'), findsOneWidget);
      inst.allowed = true;
      await tester.tap(find.text('安装'));
      await tester.pumpAndSettle();
      expect(inst.calls.last, 'install:/tmp/my-fitness-2.3.0.apk');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('下载失败：显示中文原因，可重试，也可以用浏览器下载（列出各条线路）', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final svc = FailingService();
      await pumpDialog(tester, svc, FakeInstaller(true));
      await tester.tap(find.text('更新'));
      await tester.pumpAndSettle();
      expect(find.textContaining('所有下载线路都失败了'), findsOneWidget);
      expect(find.textContaining('已下载的部分会保留'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      await tester.tap(find.text('用浏览器下载'));
      await tester.pumpAndSettle();
      expect(find.text('加速线路一'), findsOneWidget);
      expect(find.text('GitHub 官方'), findsOneWidget);
      expect(find.text('Release 页面'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('启动自动检查：有新版就弹窗，点「暂不更新」关掉；再次进入软件（切回前台）仍会提示', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      resetUpdateAutoCheckThrottle();
      final update = findUpdate(releases: releases, ios: false, current: '2.2.3')!;
      var checks = 0;
      final svc = CountingService(update, () => checks++);
      Future<void> pumpShell() async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            updateServiceProvider.overrideWithValue(svc),
            apkInstallerProvider.overrideWithValue(FakeInstaller(true)),
            currentVersionProvider.overrideWith((ref) async => '2.2.3'),
            autoUpdateCheckProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const UpdateAutoCheck(child: Scaffold(body: Text('首页'))),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pumpShell();
      expect(checks, 1);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('暂不更新'), findsOneWidget);
      expect(find.text('更新'), findsOneWidget);

      await tester.tap(find.text('暂不更新'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本'), findsNothing);

      // 刚检查过不久，马上切回来不重复打扰
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(checks, 1);
      expect(find.text('发现新版本'), findsNothing);

      // 隔了一阵再回到软件：还没更新就再次提示
      resetUpdateAutoCheckThrottle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(checks, 2);
      expect(find.text('发现新版本'), findsOneWidget);
      await tester.tap(find.text('暂不更新'));
      await tester.pumpAndSettle();

      // 重新启动软件（新进程）= 一定会检查
      await tester.pumpWidget(const SizedBox());
      resetUpdateAutoCheckThrottle();
      await pumpShell();
      expect(checks, 3);
      expect(find.text('发现新版本'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('已是最新版：自动检查不弹窗', (tester) async {
    resetUpdateAutoCheckThrottle();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        updateServiceProvider.overrideWithValue(FakeService(null)),
        currentVersionProvider.overrideWith((ref) async => '2.3.0'),
        autoUpdateCheckProvider.overrideWithValue(true),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const UpdateAutoCheck(child: Scaffold(body: Text('首页')))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本'), findsNothing);
  });
}

class FailingService extends FakeService {
  FailingService() : super(null);

  @override
  Future<File> download(AppUpdate update, void Function(int, int) onProgress, DownloadCancel cancel, {void Function(String)? onStatus}) async {
    onStatus?.call('线路 1/4：备用服务器');
    throw UpdateException('所有下载线路都失败了。备用服务器：连接超时');
  }
}

class CountingService extends FakeService {
  CountingService(super.result, this.onCheck);
  final void Function() onCheck;

  @override
  Future<AppUpdate?> check({required String current, required bool ios}) async {
    onCheck();
    return result;
  }
}
