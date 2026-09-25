import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    let videoProcessor = VideoProcessor()

    var navigationPath = NavigationPath()
    var orientation: Orientation = .horizontal
    var selectedVideo: SelectedVideo?
    var outputVideo: OutputVideo?

    /// Returns to the selection screen with no video picked, keeping the last chosen orientation.
    func reset() {
        selectedVideo = nil
        outputVideo?.cleanUp()
        outputVideo = nil
        navigationPath = NavigationPath()
    }
}
