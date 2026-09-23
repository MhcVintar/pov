import AVFoundation
import CoreGraphics

struct Metadata {
    let creationDate: AVMetadataItem
    let duration: CMTime
    let resolution: CGSize
    let transform: CGAffineTransform
    let frameRate: Double
    let bitRate: Double
}
