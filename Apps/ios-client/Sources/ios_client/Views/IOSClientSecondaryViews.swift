import ComposableArchitecture
import RemoteFeatures
import RemoteCore
import SSH
import SwiftUI
import UI

struct IOSSettingsSheet: View {
    @Bindable var store: StoreOf<RemoteTerminalFeature>
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.space4) {
                    VStack(alignment: .leading, spacing: Spacing.space3) {
                        SectionHeader("Trusted SSH Hosts")
                        Text("\(store.trustedHostsCount)")
                            .font(Typography.title.weight(.semibold))
                            .foregroundStyle(theme.accent)
                        ActionButton("Clear Trusted Hosts", style: .ghost, tone: .destructive) {
                            store.send(.clearTrustedHosts)
                        }
                    }
                    .padding(Spacing.space4)
                    .elevation(.card)

                    VStack(alignment: .leading, spacing: Spacing.space3) {
                        SectionHeader("Discovered tmux Sessions")
                        Text("\(store.discoveredSessions.count)")
                            .font(Typography.title.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(Spacing.space4)
                    .elevation(.card)
                }
                .padding(Spacing.space3)
            }
            .background(theme.base.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        store.send(.dismissSettings)
                    }
                    .tint(theme.text)
                }
            }
        }
    }
}
