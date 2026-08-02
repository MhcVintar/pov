import SwiftUI
import AVFoundation

class AppState: ObservableObject {
    let videoService: VideoService?
    
    @Published var navigationPath = NavigationPath()
    @Published var asset: AVAsset?
    @Published var error: Error?
    
    init() {
        do {
            videoService = try VideoService()
        } catch {
            videoService = nil
            self.error = error
        }
    }
}

