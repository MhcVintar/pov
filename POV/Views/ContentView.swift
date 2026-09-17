import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    @State var orientation = Orientation.horizontal

    var body: some View {
        if let error = appState.error, !AppError.isRecoverable(error) {
            ErrorView(error)
        } else {
            NavigationStack(path: $appState.navigationPath) {
                SelectionView(orientation: $orientation)
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .processingView:
                            ProcessingView(orientation: $orientation)
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
    case processingView
    case completionView
    case errorView
}

#Preview {
    ContentView()
}
