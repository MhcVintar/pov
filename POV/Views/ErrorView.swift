import SwiftUI

struct ErrorView: View {
    let error: Error
    
    init(_ error: Error) {
        self.error = error
    }
    
    var body: some View {
        if AppError.isRecoverable(error) {
            InfoComponent(
                icon: "exclamationmark.triangle",
                iconColor: .yellow,
                title: "Error Occurred",
                caption: error.localizedDescription
            )
        } else {
            InfoComponent(
                icon: "exclamationmark.octagon",
                iconColor: .red,
                title: "Fatal Error Occurred",
                caption: "\(error.localizedDescription) Please close the app any try again."
            )
        }
    }
}

#Preview {
    ErrorView(AppError.fatalError("Some error occurred."))
}
