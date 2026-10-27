import SwiftUI

extension Color {
  static let appDefaultAccent = Color(red: 0.98, green: 0.12, blue: 0.22)

  // iOS follows the theme picker; see AppThemePalette.swift.
  #if !os(iOS)
    static let appAccent = appDefaultAccent
  #endif
}
