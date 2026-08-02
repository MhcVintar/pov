import AVFoundation
import Foundation

enum Utils {
    static func getMetadata(from asset: AVAsset) async throws -> Metadata {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AppError.recoverableError("Failed to load video track")
        }
        
        let (
            creationDate,
            duration,
            naturalSize,
            transform,
            frameRate,
            bitRate,
        ) = try await (
            asset.load(.creationDate),
            asset.load(.duration),
            videoTrack.load(.naturalSize),
            videoTrack.load(.preferredTransform),
            videoTrack.load(.nominalFrameRate),
            videoTrack.load(.estimatedDataRate),
        )
        
        let transformedSize = naturalSize.applying(transform)
        let resolution = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        
        guard let creationDate = creationDate else {
            throw AppError.recoverableError("Failed to load creation date")
        }
        
        return Metadata(
            creationDate: creationDate,
            duration: duration,
            resolution: resolution,
            frameRate: Double(frameRate),
            bitRate: Double(bitRate),
        )
    }
}
