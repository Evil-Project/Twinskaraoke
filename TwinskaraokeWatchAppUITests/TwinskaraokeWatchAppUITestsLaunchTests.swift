//
//  TwinskaraokeWatchAppUITestsLaunchTests.swift
//  TwinskaraokeWatchAppUITests
//
//  Created by xiaoyuan on 2026/4/19.
//
import XCTest

final class Twinskaraoke_Watch_AppUITestsLaunchTests: XCTestCase {
  override class var runsForEachTargetApplicationUIConfiguration: Bool {
    true
  }
  override func setUpWithError() throws {
    continueAfterFailure = false
  }
  @MainActor
  func testLaunch() throws {
    let app = XCUIApplication()
    app.launch()
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Launch Screen"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
