import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationStack(path: $appState.navigationPath) {
            SelectionView()
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .processingView:
                        ProcessingView()
                    case .completionView:
                        CompletionView()
                    }
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
