import SwiftUI

struct InfoCardData: Identifiable {
    let id = UUID()
    let color: Color
    let icon: String
    let label: String
    let value: String
}

struct InfoCardComponent: View {
    let data: InfoCardData

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(data.color.opacity(0.15))
                .strokeBorder(data.color, lineWidth: 2)
                .frame(width: 60, height: 40)
                .overlay {
                    Image(systemName: data.icon)
                        .foregroundStyle(data.color)
                        .font(.title2)
                }

            VStack(spacing: 2) {
                Text(data.label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.secondary)

                Text(data.value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.primary.opacity(0.5), lineWidth: 1),
                ),
        )
    }
}

#Preview {
    InfoCardComponent(data: InfoCardData(
        color: .blue,
        icon: "viewfinder",
        label: "Duration",
        value: "2:43",
    ))
}
