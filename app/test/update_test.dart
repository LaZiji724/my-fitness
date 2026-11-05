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
  Future<File> download(AppUpdate update, void Function(int, int) onProgress, DownloadCancel cancel) async {
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
      await tester.tap(find.text('下载并安装'));
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
}
