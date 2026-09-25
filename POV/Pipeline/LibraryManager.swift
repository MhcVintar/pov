import AVFoundation
import Photos
import PhotosUI
import UIKit
import SwiftUI

/// Thrown when the picked video can't be used (wrong aspect ratio, unreadable, or
/// otherwise not a supported clip) — the one failure the app recovers from, by
/// showing an inline message on the selection screen. Any other failure is treated
/// as unexpected and crashes the app instead.
struct WrongFileFormatError: Error {}

enum LibraryManager {
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
            throw WrongFileFormatError()
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw WrongFileFormatError()
        }

        let avAsset: AVAsset = try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.version = .original
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, info in
                guard let avAsset, info?[PHImageErrorKey] == nil else {
                    continuation.resume(throwing: WrongFileFormatError())
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
            throw WrongFileFormatError()
        }

        let (naturalSize, transform) = try await (videoTrack.load(.naturalSize), videoTrack.load(.preferredTransform))
        let resolution = naturalSize.applying(transform)
        let width = abs(resolution.width)
        let height = abs(resolution.height)

        guard height > 0, abs(width / height - Self.expectedAspectRatio) < Self.aspectRatioTolerance else {
            throw WrongFileFormatError()
        }
    }

    static func saveVideo(at url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
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
