import SwiftUI
import Testing
import UIKit
@testable import Twinskaraoke

/// The sign-in fields have to tell iOS what they hold, or Password AutoFill
/// and the keychain can't offer or save the account's credentials.
@MainActor
struct LoginSheetAutofillTests {
    private func textFields(in view: UIView) -> [UITextField] {
        view.subviews.flatMap { subview -> [UITextField] in
            let nested = textFields(in: subview)
            return (subview as? UITextField).map { [$0] + nested } ?? nested
        }
    }

    @Test func theUsernameAndPasswordFieldsDeclareTheirContentTypes() async throws {
        let auth = AuthManager(requestData: { _ in throw URLError(.notConnectedToInternet) })
        let window = makeTestWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UIHostingController(rootView: LoginSheet(auth: auth))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var fields: [UITextField] = []
        for _ in 0..<20 where fields.count < 2 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            fields = textFields(in: window)
        }

        let username = try #require(fields.first { !$0.isSecureTextEntry }, "No username field in \(fields)")
        let password = try #require(fields.first { $0.isSecureTextEntry }, "No password field in \(fields)")
        #expect(username.textContentType == .username)
        #expect(password.textContentType == .password)
        #expect(username.autocapitalizationType == .none)
        #expect(username.autocorrectionType == .no)
    }
}
