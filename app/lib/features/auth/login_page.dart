import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/auth/auth_service.dart';
import 'package:my_fitness/features/auth/validators.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .signIn(username: _username.text, password: _password.text);
      // 成功后路由会因登录状态变化自动跳转到首页
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s24, AppSpace.s40, AppSpace.s24, AppSpace.s24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.hero, borderRadius: BorderRadius.circular(AppRadius.md)),
                      child: Icon(AppIcons.navTrainOn, size: 22, color: c.accent),
                    ),
                    const SizedBox(width: AppSpace.s12),
                    Text('我的健身', style: AppText.titleSmall.copyWith(color: c.text)),
                  ],
                ),
                const SizedBox(height: AppSpace.s40),
                Text('欢迎回来，\n今天也练一点。', style: AppText.titleLarge.copyWith(color: c.text)),
                const SizedBox(height: AppSpace.s32),
                TextFormField(
                  controller: _username,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: '用户名'),
                  validator: AuthValidators.username,
                ),
                const SizedBox(height: AppSpace.s12),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '密码',
                    suffixIcon: PressScale(
                      scale: PressScale.smallScale,
                      child: IconButton(
                        tooltip: _obscure ? '显示密码' : '隐藏密码',
                        icon: Icon(_obscure ? AppIcons.eye : AppIcons.eyeOff, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  validator: AuthValidators.loginPassword,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpace.s12),
                  Text(_error!, style: AppText.label.copyWith(color: c.danger)),
                ],
                const SizedBox(height: AppSpace.s24),
                PressScale(
                  child: FilledButton(
                    style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSize.buttonLarge))),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('登录'),
                  ),
                ),
                const SizedBox(height: AppSpace.s16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('还没有账号？', style: AppText.label.copyWith(color: c.text2)),
                    PressScale(
                      child: TextButton(
                        onPressed: _busy ? null : () => context.go('/register'),
                        child: const Text('注册一个'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.s8),
                Center(
                  child: Text('登录一次后，这台手机会一直保持登录',
                      style: AppText.caption.copyWith(color: c.text3)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
