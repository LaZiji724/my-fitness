import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:my_fitness/app/app.dart';
import 'package:my_fitness/core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.isConfigured) {
    // 会话（access/refresh token）由 SDK 自动保存在本机并在启动时恢复，
    // 所以登录一次后这台手机会一直保持登录。
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }
  runApp(const ProviderScope(child: MyFitnessApp()));
}
