public import SwiftUI
import DevysCharacter

/// Every design-system component in both appearances, for review.
/// Opened from the Debug menu on macOS or with DEVYS_GALLERY=1.
public struct DesignGallery: View {
    @State private var tab = "List"
    @State private var draft = ""

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
                Text("Design Gallery").font(DevysTypography.greeting).foregroundStyle(DevysColors.ink)
                panel("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                        swatch("Frame", DevysColors.frame)
                        swatch("Sheet", DevysColors.sheet)
                        swatch("Tint", DevysColors.sheetTint)
                        swatch("Track", DevysColors.track)
                        swatch("Ink", DevysColors.ink)
                        swatch("Ink 2", DevysColors.ink2)
                        swatch("Ink 3", DevysColors.ink3)
                        swatch("Indigo", DevysColors.indigo)
                        swatch("Amber", DevysColors.amber)
                        swatch("Green", DevysColors.green)
                        swatch("Red", DevysColors.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Aurora().frame(height: 40).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("Aurora").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                        }
                    }
                }
                panel("Type") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Good afternoon, Mitch.").font(DevysTypography.greeting)
                        Text("Launch").font(DevysTypography.title)
                        Text("Send PR pricing inquiry").font(DevysTypography.heading)
                        Text("To the Northfield Gazette, you in CC.").font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                        Text("SPACES").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                        Text("op_7f3a · $0.00").font(DevysTypography.data).foregroundStyle(DevysColors.ink2)
                    }
                    .foregroundStyle(DevysColors.ink)
                }
                panel("Actions") {
                    HStack(spacing: 10) {
                        Button("Ask Operations", systemImage: "sparkles") {}.buttonStyle(.aurora)
                        Button("Approve", systemImage: "faceid") {}.buttonStyle(.aurora)
                        Button("Review") {}.buttonStyle(.raised)
                        Button("Later") {}.buttonStyle(.quiet)
                        Button("Connect GitHub", systemImage: "plus") {}.buttonStyle(.dashed)
                        Button("Disabled") {}.buttonStyle(.raised).disabled(true)
                    }
                }
                panel("Status") {
                    HStack(spacing: 10) {
                        StatusChip("Needs you", tone: .needsYou)
                        StatusChip("In progress", tone: .inProgress)
                        StatusChip("Done", tone: .done)
                        StatusChip("Failed", tone: .failed)
                        StatusChip("Expired", tone: .expired)
                        StatusChip("Checking", tone: .checking)
                        LiveTag()
                        DashedTag("Draft · not sent")
                    }
                }
                panel("Choice") {
                    HStack(spacing: 16) {
                        SegmentedTabs(selection: $tab, options: ["List", "Board", "Timeline"].map { (value: $0, title: $0) })
                        FilterChip("Owner", count: 2) {}
                        SectionHeader("Needs you", count: 2, sample: true)
                    }
                }
                panel("Presence") {
                    HStack(spacing: 16) {
                        ForEach(Array([BotMood.idle, .working, .waiting, .thinking, .celebrate, .oops].enumerated()), id: \.offset) { index, mood in
                            VStack(spacing: 6) {
                                DevysAvatar(AvatarSpec(palette: AvatarPalette.allCases[index * 2 % 10], shape: AvatarShape.allCases[index], seed: index), size: 48, mood: mood)
                                Text(mood.accessibilityDescription).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                            }
                        }
                        BusinessTile("E", tint: .blue)
                        BusinessTile("S", tint: .orange)
                    }
                }
                panel("Cards and composer") {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            StatusChip("Needs approval", tone: .needsYou)
                            Text("Send PR pricing inquiry").font(DevysTypography.heading)
                            Text("Growth drafted it. To the Northfield Gazette, you in CC.").font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                            HStack { Button("Approve", systemImage: "faceid") {}.buttonStyle(.aurora); Button("Review") {}.buttonStyle(.raised) }
                        }
                        .devysCard()
                        .frame(width: 300)
                        Composer("Ask Operations…", text: $draft) {}.frame(width: 320)
                    }
                }
            }
            .padding(DevysSpacing.section)
        }
        .background(DevysColors.frame)
    }

    private func panel(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
            ScrollView(.horizontal) { content().padding(4) }.scrollIndicators(.never)
        }
        .padding(DevysSpacing.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: DevysRadius.sheet, style: .continuous))
        .devysElevation(.resting)
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .frame(height: 40)
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DevysColors.hairline) }
            Text(name).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
        }
    }
}
