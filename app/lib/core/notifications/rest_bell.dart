import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用开着时，组间休息结束「叮」一声。退到后台 / 熄屏时由带铃声的定时通知来响。
/// 抽成接口是为了测试里换成假的。
abstract class RestBell {
  /// 这台设备需不需要应用自己放铃声。
  /// iPhone 不需要：休息结束的通知一开始倒数就登记好，前台也会放通知自带的铃声，自己再放就响两遍。
  bool get ringsInApp;

  /// 放一次铃声。失败不报错（铃声是锦上添花，不能影响训练）。
  Future<void> ring();
}

/// 安卓：原生代码用「闹钟」音频通道放 res/raw/rest_bell，手机静音 / 振动模式下也会响。
class MethodChannelRestBell implements RestBell {
  static const _channel = MethodChannel('com.hotchicken.my_fitness/bell');

  @override
  bool get ringsInApp => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> ring() async {
    if (!ringsInApp) return;
    try {
      await _channel.invokeMethod<bool>('ring');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('休息结束铃声没放出来：${e.message}');
    }
  }
}

final restBellProvider = Provider<RestBell>((ref) => MethodChannelRestBell());
