import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let error = appState.error, !AppError.isRecoverable(error) {
            ErrorView(error)
        } else {
            NavigationStack(path: $appState.navigationPath) {
                SelectionView()
                    .navigationDestination(for: NavigationDestination.self) { destination in
                        switch destination {
                        case .processingView:
                            ProcessingView()
                        case .completionView:
                            CompletionView()
                        case .errorView:
                            ErrorView(appState.error!)
                                .onDisappear {
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
