import AVFoundation
import UIKit

/// The video picked and validated on the selection screen.
struct SelectedVideo {
    let asset: AVAsset
    let fileName: String
    let thumbnail: UIImage?
    let duration: TimeInterval
}
