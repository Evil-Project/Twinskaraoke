#if canImport(UIKit)
    import Photos
    import UIKit

    @MainActor
    final class ImageSaver {
        static let shared = ImageSaver()

        private struct SaveRequest {
            let image: UIImage
            let completion: @MainActor (Result<Void, Error>) -> Void
        }

        private let requestAuthorization: @MainActor () async -> PHAuthorizationStatus
        private let writeImage: @MainActor (UIImage) async throws -> Void
        private var pendingRequests: [SaveRequest] = []
        private var isSaving = false

        init(
            requestAuthorization: @escaping @MainActor () async -> PHAuthorizationStatus = {
                await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            },
            writeImage: @escaping @MainActor (UIImage) async throws -> Void = { image in
                try await PHPhotoLibrary.shared().performChanges(photoCreationChange(for: image))
            }
        ) {
            self.requestAuthorization = requestAuthorization
            self.writeImage = writeImage
        }

        // Photos executes this block on its own queue. Both closures must be
        // Sendable so neither inherits this type's MainActor isolation.
        static func photoCreationChange(
            for image: UIImage,
            createAsset: @escaping @Sendable (UIImage) -> Void = { @Sendable image in
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        ) -> @Sendable () -> Void {
            { @Sendable in createAsset(image) }
        }

        func save(image: UIImage, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
            pendingRequests.append(SaveRequest(image: image, completion: completion))
            guard !isSaving else { return }
            isSaving = true
            // Keep accepted saves alive even if their originating view disappears.
            // The flag stays set through completion callbacks, which may enqueue another save.
            Task {
                while !pendingRequests.isEmpty {
                    let request = pendingRequests.removeFirst()
                    let status = await requestAuthorization()
                    guard status == .authorized || status == .limited else {
                        request.completion(.failure(NSError(
                            domain: PHPhotosErrorDomain,
                            code: PHPhotosError.Code.accessUserDenied.rawValue
                        )))
                        continue
                    }
                    do {
                        try await writeImage(request.image)
                        request.completion(.success(()))
                    } catch {
                        request.completion(.failure(error))
                    }
                }
                isSaving = false
            }
        }
    }
#endif
