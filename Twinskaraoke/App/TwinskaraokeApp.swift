import SwiftUI
#if canImport(UIKit)
  import UIKit
#endif

@main
struct TwinskaraokeApp: App {
  init() {
    ImageCacheConfig.applyLimits()
    #if canImport(UIKit)
      let accent = UIColor(red: 0.99, green: 0.19, blue: 0.35, alpha: 1)
      UIView.appearance().tintColor = accent
      UIWindow.appearance().tintColor = accent
      UINavigationBar.appearance().tintColor = accent
      UITabBar.appearance().tintColor = accent
      UISwitch.appearance().onTintColor = accent
    #endif
  }
  var body: some Scene {
    WindowGroup {
      ContentView()
        .preferredColorScheme(.dark)
        .tint(.appAccent)
    }
  }
}
