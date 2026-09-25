import SwiftUI

/// Full-width 56pt capsule button used at the bottom of the selection and done screens.
struct PrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? .white : Color.buttonDisabledText)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isEnabled ? Color.accent : Color.buttonDisabledFill, in: Capsule())
        }
        .disabled(!isEnabled)
    }
}
