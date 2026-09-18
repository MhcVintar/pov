import AVFoundation
import Photos
import PhotosUI
import SwiftUI

enum LibraryManager {
    static func loadAsset(from item: PhotosPickerItem) async throws -> AVAsset {
        guard let assetIdentifier = item.itemIdentifier else {
            throw AppError.recoverableError("Failed to get asset identifier.")
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw AppError.recoverableError("Failed to load PHAsset.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .original
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let avAsset else {
                    continuation.resume(throwing: AppError.recoverableError("Failed to load AVAsset."))
                    return
                }

                continuation.resume(returning: avAsset)
            }
        }
    }

    static func saveVideo(at url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
