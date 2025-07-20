import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var poseDetectionChannelHandler: PoseDetectionChannelHandler?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Register pose detection platform channels
    let registrar = self.registrar(forPlugin: "PoseDetectionPlugin")!
    poseDetectionChannelHandler = PoseDetectionChannelHandler(registrar: registrar)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
