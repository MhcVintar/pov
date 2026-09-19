import AVFoundation
import SwiftUI

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

    /// Fatal errors are handled by ContentView switching its whole body to ErrorView,
    /// so only recoverable ones need to be routed to the errorView destination here.
    func present(_ error: Error) {
        self.error = error

        if AppError.isRecoverable(error) {
            navigationPath.append(NavigationDestination.errorView)
        }
    }
}
