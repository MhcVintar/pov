import Foundation
import UIKit

/// The reframed video produced by processing, already saved to Photos.
/// Kept around as a temp file so the done screen can play and share it.
struct OutputVideo {
    let url: URL
    let thumbnail: UIImage?
    let duration: TimeInterval
    let orientation: Orientation

    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }
}
