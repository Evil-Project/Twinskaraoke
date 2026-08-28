import SwiftUI
import Testing
@testable import Twinskaraoke

@Suite("Adaptive layout breakpoints")
struct AppLayoutTests {
    @Test("A 13-inch iPad detail column keeps the wide content layout")
    func wideDetailCanvas() {
        #expect(AM.Layout.usesWideCanvas(horizontalSizeClass: .regular, availableWidth: 1_046))
        #expect(!AM.Layout.usesWideCanvas(horizontalSizeClass: .regular, availableWidth: 900))
        #expect(!AM.Layout.usesWideCanvas(horizontalSizeClass: .compact, availableWidth: 1_376))
    }

    @Test("The sidebar retains a wider activation threshold than content")
    func sidebarCanvas() {
        #expect(AM.Layout.usesSidebarCanvas(horizontalSizeClass: .regular, availableWidth: 1_376))
        #expect(!AM.Layout.usesSidebarCanvas(horizontalSizeClass: .regular, availableWidth: 1_046))
        #expect(!AM.Layout.usesSidebarCanvas(horizontalSizeClass: .compact, availableWidth: 1_376))
    }
}
