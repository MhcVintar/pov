import SwiftUI

struct ButtonComponent: View {
    let label: String
    let action: () -> Void
    
    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .foregroundStyle(.white)
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .background(.blue)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
    }
}

#Preview {
    ButtonComponent("Click me") {}
}
