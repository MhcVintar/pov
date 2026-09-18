import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

enum LibraryManager {
    // Shown to the user for any failure below — the specific Photos/AVFoundation
    // failure reason isn't actionable for them, so we keep one plain message
    // rather than surfacing framework-internal text.
    private static let loadFailureMessage = "Couldn't load the selected video. Please try a different one."
    private static let saveFailureMessage = "Couldn't save the processed video to your Photos library. Please try again."

    static func loadAsset(from item: PhotosPickerItem) async throws -> AVAsset {
        guard let assetIdentifier = item.itemIdentifier else {
            throw AppError.recoverableError(Self.loadFailureMessage)
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw AppError.recoverableError(Self.loadFailureMessage)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .original
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, info in
                guard let avAsset, info?[PHImageErrorKey] == nil else {
                    continuation.resume(throwing: AppError.recoverableError(Self.loadFailureMessage))
                    return
                }

                continuation.resume(returning: avAsset)
            }
        }
    }

    static func saveVideo(at url: URL) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            throw AppError.recoverableError(Self.saveFailureMessage)
        }
    }

    // Best-effort: a missing thumbnail shouldn't block the user from processing
    // the video they already picked, so callers can just ignore a nil result.
    static func thumbnail(for asset: AVAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        guard let cgImage = try? await generator.image(at: .zero).image else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
