import Foundation
import Testing
@testable import Twinskaraoke_Watch_App

@Suite("Watch session link")
struct WatchSessionLinkTests {
    @Test("Descriptor survives the round trip through an application context")
    func descriptorRoundTrips() {
        let descriptor = WatchSessionLink.Descriptor(
            isSignedIn: true,
            userID: "user-1",
            username: "kenneth",
            avatar: "https://example.invalid/a.png",
            generation: 7
        )

        let decoded = WatchSessionLink.decode(WatchSessionLink.encode(descriptor))

        #expect(decoded == descriptor)
    }

    @Test("Signed-out descriptor carries no identity")
    func signedOutOmitsIdentity() {
        let payload = WatchSessionLink.encode(.signedOut)

        #expect(payload[WatchSessionLink.ContextKey.isSignedIn] as? Bool == false)
        #expect(payload[WatchSessionLink.ContextKey.username] == nil)
        #expect(payload[WatchSessionLink.ContextKey.userID] == nil)
        #expect(payload[WatchSessionLink.ContextKey.avatar] == nil)
    }

    /// `updateApplicationContext` throws on anything that isn't a property
    /// list, which would strand the watch on a stale session.
    @Test("Encoded context is property-list safe")
    func encodedContextIsPropertyListSerializable() {
        let payload = WatchSessionLink.encode(
            WatchSessionLink.Descriptor(
                isSignedIn: true,
                userID: "user-1",
                username: "kenneth",
                avatar: nil,
                generation: 2
            )
        )

        #expect(PropertyListSerialization.propertyList(payload, isValidFor: .binary))
    }

    @Test("A payload without our sign-in flag is ignored rather than read as a sign-out")
    func foreignPayloadDecodesToNil() {
        #expect(WatchSessionLink.decode([:]) == nil)
        #expect(WatchSessionLink.decode(["someone.elses.key": "value"]) == nil)
    }

    /// The watch pulls a fresh token whenever the generation moves, so a
    /// sign-out and sign-in as the same user must not look like a replay.
    @Test("Generation defaults to zero when absent but is preserved when present")
    func generationDecoding() {
        let withoutGeneration: [String: Any] = [WatchSessionLink.ContextKey.isSignedIn: true]
        #expect(WatchSessionLink.decode(withoutGeneration)?.generation == 0)

        let withGeneration: [String: Any] = [
            WatchSessionLink.ContextKey.isSignedIn: true,
            WatchSessionLink.ContextKey.generation: 42,
        ]
        #expect(WatchSessionLink.decode(withGeneration)?.generation == 42)
    }
}
