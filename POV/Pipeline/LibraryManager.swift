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

    // The processing pipeline (crop ratios, warp math) assumes 4:3 source footage,
    // so anything else is rejected up front rather than producing a malformed result.
    private static let expectedAspectRatio = 4.0 / 3.0
    private static let aspectRatioTolerance = 0.01

    struct LoadedVideo {
        let asset: AVAsset
        let fileName: String
    }

    static func loadAsset(from item: PhotosPickerItem) async throws -> LoadedVideo {
        guard let assetIdentifier = item.itemIdentifier else {
            throw AppError.recoverableError(loadFailureMessage)
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw AppError.recoverableError(Self.loadFailureMessage)
        }

        let avAsset: AVAsset = try await withCheckedThrowingContinuation { continuation in
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

        try await Self.validateIsFourThree(avAsset)

        let fileName = PHAssetResource.assetResources(for: phAsset).first?.originalFilename ?? "Video"

        return LoadedVideo(asset: avAsset, fileName: fileName)
    }

    private static func validateIsFourThree(_ asset: AVAsset) async throws {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.recoverableError(loadFailureMessage)
        }

        let (naturalSize, transform) = try await (videoTrack.load(.naturalSize), videoTrack.load(.preferredTransform))
        let resolution = naturalSize.applying(transform)
        let width = abs(resolution.width)
        let height = abs(resolution.height)

        guard height > 0, abs(width / height - Self.expectedAspectRatio) < Self.aspectRatioTolerance else {
            throw AppError.wrongAspectRatio
        }
    }

    static func saveVideo(at url: URL) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            throw AppError.recoverableError(saveFailureMessage)
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
