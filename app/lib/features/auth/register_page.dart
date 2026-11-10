import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:my_fitness/core/theme/app_icons.dart';
import 'package:my_fitness/core/theme/app_theme.dart';
import 'package:my_fitness/core/widgets/press_scale.dart';
import 'package:my_fitness/features/auth/auth_providers.dart';
import 'package:my_fitness/features/auth/auth_service.dart';
import 'package:my_fitness/features/auth/avatar_picker.dart';
import 'package:my_fitness/features/auth/avatars.dart';
import 'package:my_fitness/features/auth/validators.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  String _avatar = kDefaultAvatarRef;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
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
      await ref.read(authServiceProvider).signUp(
            username: _username.text,
            password: _password.text,
            displayName: _displayName.text,
            avatarRef: _avatar,
          );
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
      appBar: AppBar(
        leading: PressScale(
          scale: PressScale.smallScale,
          child: IconButton(
            tooltip: '返回登录',
            icon: const Icon(AppIcons.back),
            onPressed: _busy ? null : () => context.go('/login'),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s24, AppSpace.s8, AppSpace.s24, AppSpace.s24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('创建账号', style: AppText.titleLarge.copyWith(color: c.text)),
                const SizedBox(height: AppSpace.s24),
                Text('选一个头像', style: AppText.titleSmall.copyWith(color: c.text)),
                const SizedBox(height: 2),
                Text('以后在「我的」里随时更换',
                    style: AppText.caption.copyWith(color: c.text3)),
                const SizedBox(height: AppSpace.s12),
                AvatarPicker(selected: _avatar, onChanged: (v) => setState(() => _avatar = v)),
                const SizedBox(height: AppSpace.s24),
                TextFormField(
                  controller: _username,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.newUsername],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '用户名（用于登录）',
                    helperText: '3–20 位小写字母、数字或下划线',
                  ),
                  validator: AuthValidators.username,
                ),
                const SizedBox(height: AppSpace.s12),
                TextFormField(
                  controller: _displayName,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: '昵称（显示用，可写中文）'),
                  validator: AuthValidators.displayName,
                ),
                const SizedBox(height: AppSpace.s12),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '密码（至少 8 位）',
                    suffixIcon: PressScale(
                      scale: PressScale.smallScale,
                      child: IconButton(
                        tooltip: _obscure ? '显示密码' : '隐藏密码',
                        icon: Icon(_obscure ? AppIcons.eye : AppIcons.eyeOff, size: 20),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  validator: AuthValidators.newPassword,
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
                        : const Text('注册并开始'),
                  ),
                ),
                const SizedBox(height: AppSpace.s16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('已有账号？', style: AppText.label.copyWith(color: c.text2)),
                    PressScale(
                      child: TextButton(
                        onPressed: _busy ? null : () => context.go('/login'),
                        child: const Text('去登录'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
