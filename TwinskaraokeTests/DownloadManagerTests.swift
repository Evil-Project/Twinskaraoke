import Foundation
import Testing
@testable import Twinskaraoke

@Suite("Download validation")
struct DownloadManagerTests {
    @Test("Catalog rounding and longer files are accepted")
    func durationAcceptsHealthyFiles() {
        #expect(
            DownloadManager.durationAppearsComplete(
                actualDuration: 198,
                expectedDuration: 200
            )
        )
        #expect(
            DownloadManager.durationAppearsComplete(
                actualDuration: 205,
                expectedDuration: 200
            )
        )
        #expect(
            DownloadManager.durationAppearsComplete(
                actualDuration: 180,
                expectedDuration: nil
            )
        )
    }

    @Test("Truncated and unreadable files are rejected")
    func durationRejectsBrokenFiles() {
        #expect(
            !DownloadManager.durationAppearsComplete(
                actualDuration: 120,
                expectedDuration: 200
            )
        )
        #expect(
            !DownloadManager.durationAppearsComplete(
                actualDuration: 0,
                expectedDuration: 200
            )
        )
    }
}
