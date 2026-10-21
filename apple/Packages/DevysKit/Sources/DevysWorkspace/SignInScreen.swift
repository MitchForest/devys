import ComposableArchitecture2
import DevysCharacter
import DevysDesignSystem
import SwiftUI

struct SignInScreen: View {
    let store: StoreOf<SignIn>

    var body: some View {
        ScrollView {
            VStack(spacing: DevysSpacing.roomy) {
                DevysAvatar(
                    AvatarSpec(palette: .blue, shape: .roundedSquare, seed: 7),
                    size: 84,
                    mood: store.isSubmitting ? .thinking : store.errorText == nil ? .idle : .oops,
                    label: "Devys"
                )
                VStack(spacing: DevysSpacing.small) {
                    Text("Welcome to Devys")
                        .font(DevysTypography.greeting)
                        .foregroundStyle(DevysColors.ink)
                    Text("Run `bun run local code` (or `bun run local install`) on the Mac running Devys and open the link it prints, or paste its code here. Later devices: Settings › Devices on a signed-in one.")
                        .font(DevysTypography.body)
                        .foregroundStyle(DevysColors.ink2)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: DevysSpacing.compact) {
                    field(
                        "Server",
                        text: Binding(get: { store.server }, set: { store.send(.serverChanged($0)) }),
                        prompt: "https://devys.example.com"
                    )
                    .textContentType(.URL)
                    field(
                        "Enrollment code",
                        text: Binding(get: { store.code }, set: { store.send(.codeChanged($0)) }),
                        prompt: "64-character code"
                    )
                    .textContentType(.oneTimeCode)
                    if let error = store.errorText {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(DevysTypography.secondary)
                            .foregroundStyle(DevysColors.red)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                Button {
                    store.send(.submitTapped)
                } label: {
                    Text(store.isSubmitting ? "Signing in…" : "Sign in").frame(maxWidth: .infinity)
                }
                .buttonStyle(.aurora)
                .disabled(!store.canSubmit)
                .keyboardShortcut(.defaultAction)
            }
            .padding(DevysSpacing.section)
            .frame(maxWidth: 440)
            .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: DevysRadius.sheet, style: .continuous))
            .devysElevation(.raised)
            .padding(DevysSpacing.roomy)
            .frame(maxWidth: .infinity, minHeight: 560)
            .animation(DevysMotion.quick, value: store.errorText)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DevysColors.frame)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(DevysColors.ink3))
                .textFieldStyle(.plain)
                .font(DevysTypography.body)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(DevysColors.track, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(label)
        }
    }
}
