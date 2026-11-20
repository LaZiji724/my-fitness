import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 本地通知（计时结束提醒）需要把通知中心的代理交给应用
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var bellPlayer: BellPlayer?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 前台提示音：走媒体通道，静音开关下也能响，并压低正在放的音乐
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BellPlayer") {
      bellPlayer = BellPlayer.register(with: registrar.messenger())
    }
  }
}

/// 应用在前台时放组间休息 / 动作计时结束的铃声。
/// 走「播放」音频会话：无视侧边静音开关也能听到，音量跟媒体音量，比平时小一点点；
/// 用 duckOthers：正在放的音乐只是被压低，铃声放完后恢复，不会被打断。
final class BellPlayer: NSObject, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?
  private let volume: Float = 0.75

  static func register(with messenger: FlutterBinaryMessenger) -> BellPlayer {
    let bell = BellPlayer()
    let channel = FlutterMethodChannel(name: "com.hotchicken.my_fitness/bell", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "ring": result(bell.ring())
      default: result(FlutterMethodNotImplemented)
      }
    }
    return bell
  }

  func ring() -> Bool {
    guard let url = Bundle.main.url(forResource: "rest_bell", withExtension: "wav") else { return false }
    do {
      player?.stop()
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.duckOthers])
      try session.setActive(true)
      let p = try AVAudioPlayer(contentsOf: url)
      p.delegate = self
      p.volume = volume
      p.prepareToPlay()
      player = p
      return p.play()
    } catch {
      return false
    }
  }

  func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
    if player === p { player = nil }
    // 释放会话并通知其他应用：被压低的音乐恢复原音量
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
