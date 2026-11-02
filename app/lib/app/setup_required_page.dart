import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';

/// 没有注入 Supabase 配置时显示，提示如何配置，而不是白屏崩溃。
class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.pageGutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('还没有配置后端', style: AppText.titleLarge.copyWith(color: c.text)),
              const SizedBox(height: AppSpace.s12),
              Text(
                '请复制 env.example.json 为 env.json，填入 Supabase 的 Project URL 和 anon key，'
                '然后用 flutter run --dart-define-from-file=env.json 启动。',
                style: AppText.body.copyWith(color: c.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
