//
//  TwinskaraokeWatchAppUITests.swift
//  TwinskaraokeWatchAppUITests
//
//  Created by xiaoyuan on 2026/4/19.
//
import XCTest

final class Twinskaraoke_Watch_AppUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }
  override func tearDownWithError() throws {
  }
  @MainActor
  func testExample() throws {
    let app = XCUIApplication()
    app.launch()
  }
  @MainActor
  func testLaunchPerformance() throws {
    measure(metrics: [XCTApplicationLaunchMetric()]) {
      XCUIApplication().launch()
    }
  }
}
