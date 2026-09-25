# POV — Design handoff spec

POV is an iOS app that reframes a 4:3 video into a landscape (16:9) or portrait (9:16) video. This document is the source of truth for building its three screens in SwiftUI. The visual reference is the design canvas at https://claude.ai/artifact/WH6Gc12pmjwxo1bSccqYMD (artboards are 390 × 844 pt, dark and light versions of every state). Where a screenshot and this document disagree, follow this document.

Sample values shown in the mockups (`IMG_0142.MOV`, `0:24`, `42%`, `About 2 min left`) are placeholders. Use real data.

## Flow

1. **Select video** (root screen). The user picks a video from their Photos library and chooses Landscape or Portrait, then taps "Continue to processing".
2. **Processing**. Shows progress and an estimate of time remaining. Cancel asks for confirmation with a system alert.
3. **Done**. The reframed video is already saved to the Photos library when this screen appears. The user can play it inline, share it, or tap "Reframe another video" to return to screen 1 with its state reset (no video selected).

There is no settings screen and no navigation bar title on any screen.

## General rules

- **Font:** the system font (SF Pro) everywhere. Use Dynamic Type text styles so the user's text-size setting is respected; the table under Typography maps each design size to a style.
- **Appearance:** follow the system light/dark setting. Every color below has a light and a dark value; put them in an asset catalog as color sets.
- **Horizontal margins:** 24 pt on both sides; content width is 342 pt on a 390 pt wide phone.
- **Safe areas:** respect them. Content starts about 16 pt below the top safe area. The bottom button sits about 8 pt above the bottom safe area (home indicator).
- **Touch targets:** at least 44 × 44 pt, including small icon buttons whose visible shape is smaller.
- **Icons:** SF Symbols (names listed per screen). Icons that are text-colored use the surrounding text color unless stated.
- **No icons inside the large bottom buttons.** Both "Continue to processing" and "Reframe another video" are text only.

## Colors

| Token | Dark | Light | Used for |
|---|---|---|---|
| `background` | `#141312` | `#FAF8F5` | Screen background |
| `textPrimary` | `#F4EFE8` | `#1C1A18` | Main text, file names, titles |
| `textSecondary` | `#A89F94` | `#6B635A` | Helper text, "OUTPUT" label, time remaining, unselected segment |
| `surface` | `#1D1B19` | `#F0ECE6` | Video picker box fill, segmented control track |
| `borderDashed` | `#4A443E` | `#C4BCB1` | Dashed outline of the empty picker box |
| `iconCircle` | `#2A2724` | `#E4DED6` | Circle behind the video icon in the picker box |
| `segmentBorder` | `#2E2A27` | `#E3DDD5` | 1 pt outline of the segmented control |
| `segmentSelectedFill` | `#3A3632` | `#FFFFFF` | Selected segment (light mode adds shadow: y 1, blur 3, `#1C1A18` at 12%) |
| `segmentSelectedText` | `#F4EFE8` | `#1C1A18` | Text and icon on the selected segment |
| `chip` | `#2A2724` | `#ECE7E0` | "Replace" button fill |
| `buttonDisabledFill` | `#2A2724` | `#E6E1DA` | Primary button when disabled |
| `buttonDisabledText` | `#7A726A` | `#948B81` | Primary button text when disabled |
| `progressTrack` | `#2A2724` | `#E4DED6` | Unfilled part of the progress ring |
| `accent` | `#0A84FF` | `#007AFF` | Primary buttons, Cancel, share icon, video icon, progress ring |
| `error` | `#FF453A` | `#D70015` | Wrong-aspect-ratio outline, icon and message |
| `overlay` | `#0A0908` at 72% | same | Duration badge and remove button on top of video |

Notes:
- `accent` is Apple's system blue. `Color.blue` / `.tint(.blue)` gives exactly these two values, so it can be used instead of a custom color set.
- `error` in dark mode is the standard system red. In light mode it is Apple's darker, high-contrast red (`#D70015`), chosen because the standard `#FF3B30` is too light to read as small text on the off-white background. Don't swap it for `Color.red` in light mode.
- Text on accent-filled buttons is white (`#FFFFFF`) in both modes.
- The overlay elements on top of video (duration badge, remove button, play button) look the same in both modes: dark translucent fill with `#F4EFE8` content.

## Typography

| Design size / weight | Dynamic Type style | Used for |
|---|---|---|
| 60 pt medium, tracking −0.03 em, monospaced digits | Custom, scaled relative to `.largeTitle` | Progress number |
| 28 pt regular, `textSecondary` | Custom, scaled relative to `.title` | "%" sign next to the progress number |
| 17 pt semibold | `.body` semibold | Primary buttons |
| 17 pt medium | `.body` medium | "Select a video", "Reframing to …", "Your video is ready" |
| 17 pt regular | `.body` | Cancel |
| 15 pt medium | `.subheadline` medium | File name, segment labels |
| 15 pt regular | `.subheadline` | Screen 1 intro line, time remaining, Done subtitle |
| 14 pt medium | `.subheadline` medium | "Replace" button (15 pt is fine) |
| 14 pt regular, line height 1.4 | `.subheadline` | Error message (15 pt is fine) |
| 13 pt semibold, uppercase, tracking 0.08 em | `.footnote` semibold | "OUTPUT" section label |
| 13 pt regular | `.footnote` | "From your Photos library", hint above the primary button |
| 12 pt medium, monospaced digits | `.caption` medium | Duration badge |

Use `.monospacedDigit()` for the progress number and durations so they don't jitter while changing.

## Shared components

**Primary button.** Full width, 56 pt tall, capsule (corner radius 28). Enabled: `accent` fill, white 17 pt semibold text. Disabled: `buttonDisabledFill` with `buttonDisabledText`, not tappable.

**Hint above primary button.** When the primary button on screen 1 is disabled, a single centered line of `.footnote` `textSecondary` text sits 12 pt above it. It disappears when the button becomes enabled.

**Video thumbnail.** Corner radius 20, clipped. Shows the video's first frame (or a representative frame), filling its frame (aspect fill).

**Duration badge.** Bottom-left of a video thumbnail, inset 12 pt. Padding 5 pt vertical × 9 pt horizontal, corner radius 8, `overlay` fill, `.caption` medium text in `#F4EFE8`. Format `m:ss` (e.g. `0:24`, `12:05`).

## Screen 1 — Select video

Layout from top to bottom, 28 pt vertical spacing between blocks:

1. **Intro line:** "Pick a video and how you want it framed." `.subheadline`, `textSecondary`.
2. **Video area** (one of the states below). Full width, 4:3 aspect ratio.
3. **Output section:** "OUTPUT" label, 12 pt gap, then the orientation control.
4. Flexible space.
5. **Bottom:** optional hint line, then the primary button "Continue to processing".

### Video area states

**Empty (no video selected).** A button filling the 4:3 area: `surface` fill, 1.5 pt dashed `borderDashed` outline, corner radius 20. Centered inside, stacked with 14 pt spacing: a 56 pt `iconCircle` circle holding the SF Symbol `video` (26 pt, `accent`), then "Select a video" (`.body` medium, `textPrimary`) with "From your Photos library" (`.footnote`, `textSecondary`) 4 pt below. Tapping anywhere opens the Photos picker.

**Video selected (valid 4:3).** The video thumbnail fills the 4:3 area. On top of it: the duration badge (bottom-left) and a remove button (top-right): a 30 pt `overlay` circle with SF Symbol `xmark` (14 pt, bold, `#F4EFE8`), inside a 44 pt tap area positioned 8 pt from the top and right edges. Tapping remove returns to the empty state. Below the thumbnail, 12 pt gap, one row: the file name (`.subheadline` medium, `textPrimary`, truncates) on the left and a "Replace" button on the right (44 pt tall capsule, 16 pt horizontal padding, `chip` fill, `textPrimary` text). Replace opens the Photos picker again.

**Wrong aspect ratio.** No thumbnail, file name or Replace button. The empty-state box is shown again, with its dashed outline in `error` instead of `borderDashed`. 12 pt below it, a row with 10 pt spacing: SF Symbol `exclamationmark.circle` (18 pt, `error`) and the message "The video needs to be 4:3. Please choose a different one." (`error`, `.subheadline`, wraps). Post it as an accessibility announcement when it appears. Tapping the box opens the picker.

### Orientation control

A two-option segmented control, custom-styled rather than the native segmented `Picker` (the native one is 32 pt tall and can't show an icon and a label together):

- Track: full width, `surface` fill, 1 pt `segmentBorder` outline, corner radius 16, 4 pt inner padding, 4 pt gap between the two segments.
- Segments: equal width, 48 pt tall, corner radius 12. Icon and label centered with 10 pt spacing.
  - Left: SF Symbol `rectangle` + "Landscape".
  - Right: SF Symbol `rectangle.portrait` + "Portrait".
- Selected segment: `segmentSelectedFill`, `segmentSelectedText` (plus the light-mode shadow). Unselected: transparent, `textSecondary`.
- Default: Landscape. Animate the selection change with a short spring.
- Accessibility: expose as a single control with two options and the selected one marked as selected (`.accessibilityAddTraits(.isSelected)` on the selected segment).

The orientation can be changed in every state, including before a video is picked.

### Primary button and hint

| State | Button | Hint above button |
|---|---|---|
| Empty | Disabled | "Select a video to continue" |
| Video selected (valid) | Enabled | none |
| Wrong aspect ratio | Disabled | "Choose a 4:3 video to continue" |

Tapping the enabled button starts processing and shows screen 2.

### Picking and validating the video

- Use SwiftUI's `PhotosPicker` (or `PHPickerViewController`) filtered to videos (`matching: .videos`). The system picker runs out of process and needs no photo-library read permission.
- The picker can't filter by aspect ratio, so check the ratio after the pick. Read the video track's `naturalSize` and apply its `preferredTransform` before comparing; phone videos are often stored rotated, and skipping the transform reports the wrong shape. Accept a video when width ÷ height is within a small tolerance of 4 ÷ 3 (for example ±0.01).
- Show the selected state only after validation has finished. If loading the video takes noticeable time, show a small spinner in the box rather than leaving the empty state visible.

## Screen 2 — Processing

- **Top-left:** "Cancel" text button, `.body` regular, `accent`, 44 pt tall.
- **Center** (vertically centered in the space below Cancel), stacked with 36 pt spacing:
  - **Progress ring:** 232 pt diameter, 8 pt stroke, round line caps. Track in `progressTrack`, filled arc in `accent`, starting at 12 o'clock and filling clockwise. Inside, centered: the percentage as a whole number (60 pt medium, `textPrimary`, monospaced digits) followed by a "%" (28 pt regular, `textSecondary`, 2 pt gap). Animate progress changes smoothly. Accessibility: expose as a progress indicator with the percentage as its value.
  - **Text block,** centered, 6 pt between lines:
    - "Reframing to portrait" or "Reframing to landscape" (`.body` medium, `textPrimary`).
    - Time remaining (`.subheadline`, `textSecondary`): "About N min left". Suggested wording at the ends: "Less than a minute left" under 60 seconds, and "Estimating time…" until there's enough data for a stable estimate. Update it no more than every few seconds so the number doesn't jump.
- Nothing else on the screen.

### Cancel confirmation

Tapping Cancel shows the standard system alert (SwiftUI `.alert`), no custom design:

- Title: "Stop processing?"
- Message: "Your video won't be saved."
- Buttons: "Keep Processing" (cancel role) and "Stop" (destructive role, shown in red by iOS).

"Stop" ends processing, discards partial output and returns to screen 1 with the previously selected video and orientation still selected. "Keep Processing" dismisses the alert.

### When processing finishes

Save the result to the Photos library, then move to screen 3 automatically. Saving requires the add-only permission, so the app needs an `NSPhotoLibraryAddUsageDescription` entry in Info.plist; request access with `PHPhotoLibrary.requestAuthorization(for: .addOnly)`.

## Screen 3 — Done

- **Top-right:** share button, SF Symbol `square.and.arrow.up` (22 pt, `accent`) in a 44 pt tap area. Opens the system share sheet with the finished video (`ShareLink`). No custom design needed.
- **Center** (vertically centered), stacked with 24 pt spacing:
  - **Result preview,** sized to the output orientation:
    - Portrait: 252 × 448 pt (9:16).
    - Landscape: full content width, 342 × 192 pt (16:9).
    - Corner radius 20. Before playback: the thumbnail, a centered 64 pt `overlay` circle (60% opacity) with SF Symbol `play.fill` (24 pt, `#F4EFE8`), and the duration badge.
    - Tapping plays the video inline in the same frame using `VideoPlayer`. Once playback starts, hide the play circle and duration badge and let the system playback controls take over (they include a full-screen button).
  - **Text block,** centered, 6 pt between lines:
    - "Your video is ready" (`.body` medium, `textPrimary`).
    - "Reframed to portrait and saved to Photos" or "Reframed to landscape and saved to Photos" (`.subheadline`, `textSecondary`).
- **Bottom:** primary button "Reframe another video" (always enabled). Returns to screen 1 with no video selected. Keep the last chosen orientation selected there.

## SF Symbols used

| Where | Symbol |
|---|---|
| Picker box icon | `video` |
| Landscape segment | `rectangle` |
| Portrait segment | `rectangle.portrait` |
| Remove video | `xmark` |
| Error message | `exclamationmark.circle` |
| Share | `square.and.arrow.up` |
| Play | `play.fill` |

## Not yet designed

These cases aren't covered by the mockups. Decide on them before or during implementation:

- **Vertical 4:3 videos (3:4).** Should a video filmed upright in 4:3 be accepted, or only horizontal 4:3?
- **Processing failure.** What the user sees if reframing or saving fails. A system alert with a retry option would fit the current design without a new screen.
- **Photos add permission denied.** What happens at the end of processing if the user declines saving access.
- **Leaving the app mid-processing.** Whether processing continues in the background, and whether the user should be told to keep POV open.
- **Time estimate method.** How "About N min left" is calculated.
