import SwiftUI

struct ErrorView: View {
    let error: Error

    init(_ error: Error) {
        self.error = error
    }

    var body: some View {
        if AppError.isRecoverable(error) {
            InfoComponent(
                icon: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                iconColor: .yellow,
                title: "Error Occurred",
                caption: error.localizedDescription
            )
        } else {
            InfoComponent(
                icon: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
                iconColor: .red,
                title: "Fatal Error Occurred",
                caption: "Please close the app and try again."
            )
        }
    }
}

#Preview {
    ErrorView(AppError.recoverableError("Some error occurred."))
    //ErrorView(AppError.fatalError)
}
