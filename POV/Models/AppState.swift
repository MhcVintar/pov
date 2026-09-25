import AVFoundation
import SwiftUI

class AppState: ObservableObject {
    let videoProcessor: VideoProcessor?

    @Published var navigationPath = NavigationPath()
    @Published var orientation: Orientation = .horizontal
    @Published var selectedVideo: SelectedVideo?
    @Published var outputVideo: OutputVideo?
    @Published var error: Error?

    init() {
        do {
            videoProcessor = try VideoProcessor()
        } catch {
            videoProcessor = nil
            self.error = error
        }
    }

    /// Fatal errors are handled by ContentView switching its whole body to ErrorView,
    /// so only recoverable ones need to be routed to the errorView destination here.
    func present(_ error: Error) {
        self.error = error

        if AppError.isRecoverable(error) {
            navigationPath.append(NavigationDestination.errorView)
        }
    }

    /// Returns to the selection screen with no video picked, keeping the last chosen orientation.
    func reset() {
        selectedVideo = nil
        outputVideo?.cleanUp()
        outputVideo = nil
        navigationPath = NavigationPath()
    }
}
