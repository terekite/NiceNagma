// Scene lifecycle entry point (Flutter 3.44+ UIScene support). The
// FlutterViewController is created here when the scene connects, so this is
// where we attach the native LoopPlayer to its binary messenger — not in
// AppDelegate, where the window/rootViewController don't exist yet.
//
// `bootstrap.sh` copies this over the generated SceneDelegate.swift; the
// generated stub is an empty `FlutterSceneDelegate` subclass, so overwriting it
// needs no Xcode project changes.

import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var loopPlayer: LoopPlayer?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      loopPlayer = LoopPlayer(messenger: controller.binaryMessenger)
    }
  }
}
