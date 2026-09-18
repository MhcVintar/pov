import SwiftUI
import AVFoundation

class AppState: ObservableObject {
    let videoProcessor: VideoProcessor?

    @Published var navigationPath = NavigationPath()
    @Published var asset: AVAsset?
    @Published var error: Error?

    init() {
        do {
            videoProcessor = try VideoProcessor()
        } catch {
            videoProcessor = nil
            self.error = error
        }
    }
}

