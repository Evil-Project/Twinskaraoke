#if canImport(UIKit)
    import UIKit

    final class ImageSaver: NSObject {
        static let shared = ImageSaver()
        private var completion: ((Result<Void, Error>) -> Void)?

        func save(image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
            self.completion = completion
            UIImageWriteToSavedPhotosAlbum(
                image, self, #selector(didFinishSaving(_:didFinishSavingWithError:contextInfo:)), nil
            )
        }

        @objc private func didFinishSaving(
            _: UIImage, didFinishSavingWithError error: Error?, contextInfo _: UnsafeRawPointer
        ) {
            if let error {
                completion?(.failure(error))
            } else {
                completion?(.success(()))
            }
            completion = nil
        }
    }
#endif
