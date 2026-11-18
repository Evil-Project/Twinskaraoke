import Foundation

/// Installation-local metadata only. Answers and handshake IDs never enter this record.
nonisolated struct SplashWebsiteProgress: Codable, Equatable {
    enum Status: String, Codable { case pending, completed, canceled, closed }
    var announcementID: String
    var fingerprint: String
    var slideID: String
    var status: Status = .pending

    func matches(announcementID: String, fingerprint: String, slideID: String) -> Bool {
        self.announcementID == announcementID && self.fingerprint == fingerprint && self.slideID == slideID
    }
}
