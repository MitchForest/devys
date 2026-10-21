import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// Settings → Devices: every signed-in device, signing others out, and adding one by QR code or link.
struct DevicesPane: View {
    let store: StoreOf<Preferences>

    var body: some View {
        PaneScroll {
            VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
                if let code = store.deviceCode {
                    AddDeviceCard(code: code) { store.send(.addDeviceTapped) } done: { store.send(.deviceCodeDismissed) }
                } else {
                    HStack {
                        Text("Signed-in devices").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                        Spacer()
                        Button(store.isIssuingCode ? "Issuing…" : "Add a device", systemImage: "qrcode") { store.send(.addDeviceTapped) }
                            .buttonStyle(DevysButtonStyle(.raised, compact: true))
                            .disabled(store.isIssuingCode)
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

/// The code as a QR code the iPhone or iPad camera opens, plus the code and link to copy,
/// counting down its ten minutes.
private struct AddDeviceCard: View {
    let code: DeviceCode
    let renew: () -> Void
    let done: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(code.expiresAt.timeIntervalSince(context.date)))
            VStack(alignment: .leading, spacing: DevysSpacing.regular) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add a device").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                        Text("Point the iPhone or iPad camera at the code, or open the link on the device. It signs in as you, once.")
                            .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Done", action: done).buttonStyle(DevysButtonStyle(.quiet, compact: true))
                }
                HStack(alignment: .top, spacing: DevysSpacing.roomy) {
                    QRCode(code.link.url.absoluteString, size: 168)
                        .opacity(remaining > 0 ? 1 : 0.2)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(remaining > 0 ? "Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))" : "Expired")
                            .font(DevysTypography.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(remaining > 0 ? DevysColors.ink : DevysColors.red)
                        copyRow("Code", value: code.code)
                        copyRow("Link", value: code.link.url.absoluteString)
                        if remaining == 0 {
                            Button("New code", systemImage: "arrow.clockwise", action: renew)
                                .buttonStyle(DevysButtonStyle(.raised, compact: true))
                        }
                    }
                }
            }
            .devysCard()
        }
    }

    private func copyRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            HStack(spacing: 6) {
                Text(value)
                    .font(DevysTypography.secondary.monospaced())
                    .foregroundStyle(DevysColors.ink2)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button("Copy \(label.lowercased())", systemImage: "doc.on.doc") { DevysPasteboard.copy(value) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DevysColors.ink3)
                    .help("Copy")
            }
        }
    }
}
