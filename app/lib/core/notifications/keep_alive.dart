import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 后台接收好友消息：安卓上用前台服务让应用退到后台后进程继续活着，
/// 新消息才能及时弹出系统通知。（iPhone 没有这种能力：系统会在应用退到后台不久后把它挂起。）
/// 抽成接口是为了测试里换成假的。
abstract class KeepAlive {
  /// 这台设备能不能做到后台保活（目前只有安卓）
  bool get supported;
  Future<void> start();
  Future<void> stop();
  Future<bool> isIgnoringBatteryOptimizations();
  Future<void> requestIgnoreBatteryOptimizations();
}

class MethodChannelKeepAlive implements KeepAlive {
  static const _channel = MethodChannel('com.hotchicken.my_fitness/keep_alive');

  @override
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<T?> _call<T>(String method) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('后台保活 $method 失败：${e.message}');
      return null;
    }
  }

  @override
  Future<void> start() => _call<bool>('start');

  @override
  Future<void> stop() => _call<bool>('stop');

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => await _call<bool>('isIgnoringBatteryOptimizations') ?? true;

  @override
  Future<void> requestIgnoreBatteryOptimizations() => _call<bool>('requestIgnoreBatteryOptimizations');
}

final keepAliveProvider = Provider<KeepAlive>((ref) => MethodChannelKeepAlive());

/// 「后台接收消息」开关，默认打开，记在本机。
class BackgroundMessagesNotifier extends AsyncNotifier<bool> {
  static const _key = 'background_messages';

  @override
  Future<bool> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> set(bool value) async {
    state = AsyncData(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}

final backgroundMessagesProvider = AsyncNotifierProvider<BackgroundMessagesNotifier, bool>(BackgroundMessagesNotifier.new);
