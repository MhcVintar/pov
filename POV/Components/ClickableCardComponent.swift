import SwiftUI

struct ClickableCardData: Identifiable {
    let id = UUID()
    let color: Color
    let icon: String
    let isSelected: Bool
    let label: String
    let caption: String
    let action: () -> Void
}

struct ClickableCardComponent: View {
    let data: ClickableCardData

    var body: some View {
        Button(action: data.action) {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(data.isSelected ? data.color.opacity(0.15) : .clear)
                    .strokeBorder(data.isSelected ? data.color : .secondary.opacity(0.5), lineWidth: 2)
                    .frame(width: 60, height: 40)
                    .overlay {
                        Image(systemName: data.icon)
                            .foregroundStyle(data.isSelected ? data.color : .secondary)
                            .font(.title2)
                    }

                VStack(spacing: 2) {
                    Text(data.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(data.isSelected ? data.color : .primary)

                    Text(data.caption)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(data.isSelected ? data.color.opacity(0.1) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                data.isSelected ? data.color.opacity(0.5) : .secondary.opacity(0.5),
                                lineWidth: data.isSelected ? 2 : 1,
                            ),
                    ),
            )
        }
    }
}

#Preview {
    ClickableCardComponent(data: ClickableCardData(
        color: .blue,
        icon: "rectangle",
        isSelected: true,
        label: "Horizontal",
        caption: "Wide screen view",
        action: {},
    ))
}
