import SwiftUI

struct ConfigurationView: View {
    @EnvironmentObject var appState: AppState
    
    @Binding var orientation: Orientation
    @Binding var quality: Quality
    
    @State private var metadata: Metadata?
    
    var body: some View {
        VStack(spacing: 24) {
            if let _ = metadata {
                CardCollectionComponent(
                    title: "Information",
                    cards: getInfoCardsData(),
                    cardBuilder: InfoCardComponent.init
                )
                
                CardCollectionComponent(
                    title: "Orientation",
                    cards: getOrientationCardsData(),
                    cardBuilder: ClickableCardComponent.init
                )
                
                CardCollectionComponent(
                    title: "Quality",
                    cards: getQualityCardsData(),
                    cardBuilder: ClickableCardComponent.init
                )
                
                ButtonComponent("Process") {
                    self.appState.navigationPath.append(NavigationDestination.processingView)
                }
            }
        }
        .task {
            do {
                metadata = try await Utils.getMetadata(from: appState.asset!)
            } catch {
                appState.error = error
            }
        }
    }
    
    private func getInfoCardsData() -> [InfoCardData] {
        let resolution = metadata!.resolution
        
        let seconds = metadata!.duration.seconds
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        
        return [
            InfoCardData(
                color: .blue,
                icon: "viewfinder.rectangular",
                label: "Resolution",
                value: "\(resolution.width) x \(resolution.height)"
            ),
            InfoCardData(
                color: .green,
                icon: "clock",
                label: "Duration",
                value: String(format: "%d:%02d", minutes, remainingSeconds)
            ),
            InfoCardData(
                color: .yellow,
                icon: "gauge.with.needle",
                label: "Frame Rate",
                value: String(format: "%.2f fps", metadata!.frameRate)
            )
        ]
    }
    
    private func getOrientationCardsData() -> [ClickableCardData] {
        return Orientation.allCases.map { orientation in
            ClickableCardData(
                color: orientation.color,
                icon: orientation.icon,
                isSelected: self.orientation == orientation,
                label: orientation.displayName,
                caption: orientation.description,
                action: { self.orientation = orientation }
            )
        }
    }
    
    private func getQualityCardsData() -> [ClickableCardData] {
        return Quality.allCases
            .filter { quality in
                return switch orientation {
                case .horizontal:
                    metadata!.resolution.height >= quality.size16by9.height
                case .vertical:
                    metadata!.resolution.height >= quality.size4by3.height
                }
            }
            .map { quality in
                ClickableCardData(
                    color: quality.color,
                    icon: quality.icon,
                    isSelected: self.quality == quality,
                    label: quality.displayName,
                    caption: quality.description,
                    action: { self.quality = quality }
                )
            }
    }
}
