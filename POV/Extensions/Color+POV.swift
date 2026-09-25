import SwiftUI

// Every other design token (textPrimary, textSecondary, surface, borderDashed,
// segmentBorder, segmentSelectedFill, segmentSelectedText, chip,
// buttonDisabledFill, buttonDisabledText, progressTrack, overlay,
// overlayContent) is a color set in Assets.xcassets/Colors and already gets a
// matching `Color.<name>` static var generated automatically
// (ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS), so only the
// tokens without a color set of their own are declared here.
extension Color {
    static let appBackground = Color("background")

    // Apple's system blue matches the design's `accent` token exactly in both
    // appearances, so no custom color set is needed for it.
    static let accent = Color.blue
}
