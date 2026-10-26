import Photos
import Testing
import UIKit
@testable import Twinskaraoke

@MainActor
struct ImageSaverTests {
    @Test func photoCreationChangeRunsOnBackgroundQueue() async {
        let image = UIImage()
        let result = await withCheckedContinuation { continuation in
            // Exercise the production change block on a Photos-like queue,
            // replacing only the asset mutation so this needs no permission.
            let change = ImageSaver.photoCreationChange(for: image) { @Sendable receivedImage in
                continuation.resume(returning: (!Thread.isMainThread, receivedImage === image))
            }
            DispatchQueue(label: "ImageSaverTests.photos-changes").async(execute: change)
        }
        #expect(result.0)
        #expect(result.1)
    }

    @Test(arguments: [PHAuthorizationStatus.denied, .restricted, .notDetermined])
    func deniedAuthorizationNeverWrites(status: PHAuthorizationStatus) async {
        var writes = 0
        let saver = ImageSaver(requestAuthorization: { status }, writeImage: { _ in writes += 1 })
        let result = await withCheckedContinuation { continuation in
            saver.save(image: UIImage()) { continuation.resume(returning: $0) }
        }
        guard case let .failure(error) = result else {
            Issue.record("An unauthorized save must fail")
            return
        }
        #expect((error as NSError).domain == PHPhotosErrorDomain)
        #expect((error as NSError).code == PHPhotosError.Code.accessUserDenied.rawValue)
        #expect(writes == 0)
    }

    @Test func queuedSavesContinueAfterFailureAndReentrantCompletion() async {
        enum WriteFailure: Error { case failed }
        var events: [String] = []
        var writes = 0
        let saver = ImageSaver(requestAuthorization: { .authorized }, writeImage: { _ in
            writes += 1
            events.append("write\(writes)")
            await Task.yield()
            if writes == 1 { throw WriteFailure.failed }
        })
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            saver.save(image: UIImage()) { result in
                if case .success = result { Issue.record("The first write should fail") }
                events.append("completion1")
                saver.save(image: UIImage()) { result in
                    if case .failure = result { Issue.record("The third write should succeed") }
                    events.append("completion3")
                    done.resume()
                }
            }
            saver.save(image: UIImage()) { result in
                if case .failure = result { Issue.record("The second write should succeed") }
                events.append("completion2")
            }
        }
        #expect(events == ["write1", "completion1", "write2", "completion2", "write3", "completion3"])
    }

    @Test func authorizationIsRecheckedForEverySave() async {
        var authorizations = 0
        var writes = 0
        let saver = ImageSaver(requestAuthorization: {
            authorizations += 1
            return authorizations == 1 ? .authorized : .denied
        }, writeImage: { _ in writes += 1 })
        for index in 0..<2 {
            let result = await withCheckedContinuation { continuation in
                saver.save(image: UIImage()) { continuation.resume(returning: $0) }
            }
            switch result {
            case .success: #expect(index == 0)
            case .failure: #expect(index == 1)
            }
        }
        #expect(writes == 1)
        #expect(authorizations == 2)
    }
}
