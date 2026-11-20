import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 应用开着时，组间休息 / 动作计时结束「叮」一声。退到后台 / 熄屏时由带铃声的定时通知来响。
/// 抽成接口是为了测试里换成假的。
abstract class RestBell {
  /// 这台设备需不需要应用自己放铃声（安卓、iPhone 都由应用在前台自己放；
  /// iPhone 提前登记的通知在前台不出声，免得和应用自己放的重复）。
  bool get ringsInApp;

  /// 放一次铃声。失败不报错（铃声是锦上添花，不能影响训练）。
  Future<void> ring();
}

/// 原生代码用「媒体」音频通道放铃声（安卓 res/raw/rest_bell，iPhone 包里的 rest_bell.wav）：
/// 音量跟媒体音量，比平时小一点点；静音 / 振动模式下也能听到。
/// 正在放的音乐不会被打断，只会被临时压低，铃声放完自动恢复。
class MethodChannelRestBell implements RestBell {
  static const _channel = MethodChannel('com.hotchicken.my_fitness/bell');

  @override
  bool get ringsInApp =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

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
