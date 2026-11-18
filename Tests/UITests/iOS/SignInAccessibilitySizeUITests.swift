import UIKit
import XCTest

/// The sign-in sheet at the largest accessibility text size: its fields and
/// buttons had fixed heights, so the text grew past them and was clipped.
@MainActor
final class SignInAccessibilitySizeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func lineHeight(_ style: UIFont.TextStyle) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        return UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).lineHeight
    }

    func testSignInControlsGrowWithTheText() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestMode", "1", "-nk.language", "en",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        defer { app.terminate() }

        let account = app.buttons["AccountToolbarButton"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 10))
        account.tap()
        let openSignIn = app.buttons["Sign In"].firstMatch
        XCTAssertTrue(openSignIn.waitForExistence(timeout: 8))
        openSignIn.tap()

        let username = app.textFields["Username"]
        let password = app.secureTextFields["Password"]
        XCTAssertTrue(username.waitForExistence(timeout: 8))
        XCTAssertTrue(password.exists)
        // Each field is as tall as a line of body text; in fixed 52pt rows the
        // two overlapped.
        XCTAssertLessThanOrEqual(
            username.frame.maxY, password.frame.minY + 0.5,
            "Username \(username.frame) overlaps password \(password.frame)"
        )

        // The sheet's own button: the Account row behind it has the same label.
        let signIn = app.buttons.matching(identifier: "Sign In").allElementsBoundByIndex
            .filter { $0.frame.minY > username.frame.maxY }
        let button = try XCTUnwrap(signIn.first, "No Sign In button below the fields.")
        // Taller than its label, with room around it; at a fixed 50pt the label
        // ran past the button's edges.
        XCTAssertGreaterThanOrEqual(
            button.frame.height, lineHeight(.headline) + 8, "Sign In button \(button.frame)"
        )
    }
}
