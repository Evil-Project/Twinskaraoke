import Foundation

nonisolated enum AppRuntime {
  static var isUITestMode: Bool {
    ProcessInfo.processInfo.arguments.contains("-UITestMode")
  }
}
