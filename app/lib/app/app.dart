import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:my_fitness/app/router.dart';
import 'package:my_fitness/app/setup_required_page.dart';
import 'package:my_fitness/core/config/env.dart';
import 'package:my_fitness/core/notifications/reminder_host.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/features/sync/sync_providers.dart';
import 'package:my_fitness/features/workout/auto_end.dart';

class MyFitnessApp extends ConsumerWidget {
  const MyFitnessApp({super.key});

  static const _locale = Locale('zh', 'CN');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final common = (
      title: '我的健身',
      locale: _locale,
      supportedLocales: const [_locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );

    if (!Env.isConfigured) {
      return MaterialApp(
        title: common.title,
        locale: common.locale,
        supportedLocales: common.supportedLocales,
        localizationsDelegates: common.localizationsDelegates,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const SetupRequiredPage(),
      );
    }

    // 保持自动同步一直在后台运行
    ref.watch(syncControllerProvider);

    final router = MaterialApp.router(
      title: common.title,
      locale: common.locale,
      supportedLocales: common.supportedLocales,
      localizationsDelegates: common.localizationsDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
    // 计时结束的系统通知提醒（只在退到后台/熄屏时才弹）
    // 忘记点「结束」时自动收尾（无界面，悄悄生效）
    return AutoEndHost(child: ReminderHost(child: router));
  }
}
