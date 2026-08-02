import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState
    
    @State var orientation = Orientation.horizontal
    // TODO: make sure that if the video is of lower quality, this gets adjusted
    @State var quality = Quality.k27
    
    var body: some View {
        if let error = appState.error, !AppError.isRecoverable(error) {
            ErrorView(error)
        } else {
            NavigationStack(path: $appState.navigationPath) {
                SelectionView()
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .configurationView:
                            ConfigurationView(
                                orientation: $orientation,
                                quality: $quality
                            )
                        case .processingView:
                            ProcessingView(
                                orientation: $orientation,
                                quality: $quality
                            )
                        case .completionView:
                            CompletionView()
                        case .errorView:
                            ErrorView(appState.error!)
                                .onDisappear() {
                                    appState.error = nil
                                }
                        }
                    }
            }
        }
    }
}

enum NavigationDestination: Hashable {
    case configurationView
    case processingView
    case completionView
    case errorView
}

#Preview {
    RootView()
}
