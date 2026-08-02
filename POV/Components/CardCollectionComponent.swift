import SwiftUI

struct CardCollectionComponent<Data: Identifiable, Component: View>: View {
    let title: String
    let cards: [Data]
    let cardBuilder: (Data) -> Component

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 14)

            HStack(spacing: 8) {
                ForEach(cards, id: \.id) { card in
                    cardBuilder(card)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

#Preview {
    CardCollectionComponent(
        title: "Output Orientation",
        cards: [
            ClickableCardData(
                color: .blue,
                icon: "rectangle",
                isSelected: true,
                label: "Horizontal",
                caption: "Wide screen view",
                action: {},
            ),
            ClickableCardData(
                color: .green,
                icon: "rectangle.portrait",
                isSelected: false,
                label: "Verticat",
                caption: "Vertical screen view",
                action: {},
            ),
        ],
        cardBuilder: { ClickableCardComponent(data: $0) }
    )
}
