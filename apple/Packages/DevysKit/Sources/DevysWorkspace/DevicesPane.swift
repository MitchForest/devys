import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// Settings → Devices: every signed-in device and signing others out. A new device joins by
/// itself (its one button, allowed here); the QR code is for one that can't find this Mac.
struct DevicesPane: View {
    let store: StoreOf<Preferences>
    @Environment(\.openURL) private var openURL

    var body: some View {
        PaneScroll {
            VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
                if let link = store.connectLink {
                    ConnectCard(link: link) { store.send(.connectLinkDismissed) }
                }
                HStack {
                    Text("Signed in").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                    Spacer()
                    #if os(macOS)
                        Button("Open in browser", systemImage: "safari") { store.send(.openInBrowserTapped) }
                            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    #endif
                    if store.connectLink == nil {
                        Button("Add a device", systemImage: "qrcode") { store.send(.addDeviceTapped) }
                            .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    }
                }
                if let error = store.errorText {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                list
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DevysSpacing.roomy)
        }
        .onAppear { store.send(.devicesRequested) }
        .onChange(of: store.browserLink) { _, link in
            guard let link else { return }
            openURL(link)
            store.send(.browserLinkOpened)
        }
    }

    @ViewBuilder private var list: some View {
        switch store.devices {
        case .loading:
            ProgressView()
        case .failed(let message):
            Text(message).font(DevysTypography.body).foregroundStyle(DevysColors.ink3)
        case .loaded(let devices):
            VStack(alignment: .leading, spacing: 2) {
                let canAllow = store.keys.contains { $0.current && $0.status == .active }
                ForEach(devices) { device in
                    let key = store.keys.first { $0.device == device.id }
                    DeviceRow(device: device, key: key, canAllow: canAllow) {
                        store.send(.deviceRevoked(device.id))
                    } allow: {
                        if let key { store.send(.keyAllowed(key.id)) }
                    }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    let device: Device
    /// Its signing key, when it is a Mac or iPhone app that has one.
    let key: DeviceKey?
    /// This device approves spending, so it can allow another.
    let canAllow: Bool
    let revoke: () -> Void
    let allow: () -> Void

    var body: some View {
        HStack(spacing: DevysSpacing.compact) {
            Image(systemName: symbol).frame(width: 24).foregroundStyle(DevysColors.ink2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(device.label ?? "Device").font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    if device.current {
                        Text("This device").font(DevysTypography.caption).foregroundStyle(DevysColors.indigo)
                    }
                }
                if let added = device.addedDate {
                    Text("Added \(added.formatted(date: .abbreviated, time: .shortened))")
                        .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                }
                if let key {
                    Text(key.status == .active ? "Approves spending" : "Can't approve spending until allowed")
                        .font(DevysTypography.caption).foregroundStyle(key.status == .active ? DevysColors.ink2 : DevysColors.ink3)
                }
            }
            Spacer(minLength: 8)
            if key?.status == .pending, canAllow, !device.current {
                Button("Allow", action: allow)
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    .help("Lets this device approve spending. You confirm with Face ID or Touch ID.")
                    .accessibilityLabel("Allow \(device.label ?? "this device") to approve spending")
            }
            if !device.current {
                Button("Sign out", role: .destructive, action: revoke)
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    .accessibilityLabel("Sign out \(device.label ?? "this device")")
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        let label = (device.label ?? "").lowercased()
        if label.contains("ipad") { return "ipad" }
        if label.contains("iphone") { return "iphone" }
        if label.contains("browser") { return "globe" }
        return "laptopcomputer"
    }
}

/// This Mac as a QR code the iPhone or iPad camera opens: the app, on its one button.
private struct ConnectCard: View {
    let link: ConnectLink
    let done: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DevysSpacing.roomy) {
            QRCode(link.url.absoluteString, size: 156)
                .accessibilityLabel("QR code for \(link.mac.name)")
            VStack(alignment: .leading, spacing: DevysSpacing.compact) {
                Text("Scan with your iPhone or iPad").font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                Button("Done", action: done).buttonStyle(DevysButtonStyle(.quiet, compact: true))
            }
        }
        .devysCard()
    }
}
