import 'package:flutter/material.dart';

import 'package:my_fitness/core/theme/app_theme.dart';

/// 里程碑未做到的页面先放一个占位，保证 5 个分栏能完整切换。
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s32),
          child: Text(hint,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: c.text2)),
        ),
      ),
    );
  }
}
