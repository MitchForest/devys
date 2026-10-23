package import DevysClient
import DevysDesignSystem
import SwiftUI

// MARK: - The secure entry sheet (secrets by name)

/// The secure entry sheet's state: which secret is being added, never its value. The value lives
/// only in the sheet's own fields until it is sent, and goes when the sheet closes.
package struct SecretEntrySheet: Equatable {
    package var name: String
    package var isCard: Bool
    /// The employee's `askOwner` request it answers; then its name and kind are the request's.
    package let requestID: String?
    /// Why the employee needs it, from the request.
    package let why: String?
    package var isSaving = false
    package var error: String?

    package init(name: String = "", isCard: Bool = false, requestID: String? = nil, why: String? = nil) {
        self.name = name
        self.isCard = isCard
        self.requestID = requestID
        self.why = why
    }

    /// For an `askOwner` secret request.
    package init?(request decision: Decision) {
        guard case .secret(let name, let why, let spend) = decision.request else { return nil }
        self.init(name: name, isCard: spend, requestID: decision.id, why: why)
    }

    package var isFixed: Bool { requestID != nil }

    /// What the server said, which never repeats the value; otherwise a plain failure.
    package static func message(_ error: any Error) -> String {
        switch error {
        case DevysHTTPError.rejected(_, let message) where !message.isEmpty: message
        case let error as DevysHTTPError: Workspace.message(for: error)
        default: "It wasn't saved. Try again."
        }
    }
}

/// The sheet: a name and a value (AutoFill from Passwords), or a card. Nothing typed here is
/// shown again, kept after the sheet closes, or logged.
struct SecretEntryView: View {
    let sheet: SecretEntrySheet
    let edit: (SecretEntrySheet) -> Void
    let save: (NewSecret) -> Void
    let cancel: () -> Void

    @State private var value = ""
    @State private var number = ""
    @State private var expiry = ""
    @State private var cvc = ""
    @State private var keepCVC = false
    @State private var holder = ""
    @State private var postal = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.regular) {
            Text(sheet.isFixed ? (sheet.isCard ? "Add your card" : "Add the secret") : sheet.isCard ? "Add a card" : "Add a secret")
                .font(DevysTypography.title).foregroundStyle(DevysColors.ink)
            if let why = sheet.why {
                Text(why).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
            }
            if !sheet.isFixed {
                Picker("Kind", selection: Binding(get: { sheet.isCard }, set: { isCard in edit { $0.isCard = isCard } })) {
                    Text("Secret").tag(false)
                    Text("Card").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                FieldBox {
                    TextField("NAME_IN_CAPITALS", text: Binding(get: { sheet.name }, set: { name in edit { $0.name = name.uppercased() } }))
                        .autocorrectionDisabled()
                        .monospaced()
                }
            }
            if sheet.isCard { card } else {
                FieldBox {
                    SecureField("Value", text: $value)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                }
            }
            if let error = sheet.error {
                Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.quiet).disabled(sheet.isSaving)
                Button(sheet.isSaving ? "Saving…" : "Save") { if let entered { save(entered) } }
                    .buttonStyle(.aurora)
                    .disabled(entered == nil || sheet.isSaving)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DevysSpacing.roomy)
        .sheetFrame(width: 420, height: sheet.isCard ? 440 : 320)
        .background(DevysColors.sheet)
        .onDisappear(perform: forget)
        // Saved: the sheet closes; until then a failure keeps what was typed for another try.
    }

    @ViewBuilder private var card: some View {
        FieldBox {
            TextField("Card number", text: $number)
                .textContentType(.creditCardNumber)
                .autocorrectionDisabled()
                .numeric()
        }
        HStack(spacing: DevysSpacing.compact) {
            FieldBox {
                TextField("MM/YY", text: $expiry)
                    .textContentType(.creditCardExpiration)
                    .numeric()
            }
            if !keepCVC {
                FieldBox {
                    SecureField("Security code", text: $cvc)
                        .textContentType(.creditCardSecurityCode)
                        .numeric()
                }
            }
        }
        FieldBox {
            TextField("Name on card", text: $holder)
                .textContentType(.creditCardName)
        }
        FieldBox {
            TextField("Postal code", text: $postal)
                .textContentType(.postalCode)
                .autocorrectionDisabled()
        }
        Toggle("Keep the security code to myself", isOn: $keepCVC)
            .toggleStyle(.switch)
            .font(DevysTypography.control)
    }

    /// What Save sends, once it is complete and within bounds.
    private var entered: NewSecret? {
        guard NewSecret.isName(sheet.name) else { return nil }
        if !sheet.isCard {
            guard !value.isEmpty, value.count <= NewSecret.maximumLength else { return nil }
            return NewSecret(name: sheet.name, value: .secret(value))
        }
        let digits = number.filter { !$0.isWhitespace && $0 != "-" }
        let holder = holder.trimmingCharacters(in: .whitespacesAndNewlines)
        let postal = postal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard digits.wholeMatch(of: /\d{12,19}/) != nil,
              expiry.wholeMatch(of: /(0[1-9]|1[0-2])\/\d{2}/) != nil,
              keepCVC || cvc.wholeMatch(of: /\d{3,4}/) != nil,
              !holder.isEmpty, holder.count <= 100, !postal.isEmpty, postal.count <= 20
        else { return nil }
        return NewSecret(name: sheet.name, value: .card(CardEntry(number: digits, expiry: expiry, cvc: keepCVC ? nil : cvc, name: holder, postal: postal)))
    }

    private func edit(_ change: (inout SecretEntrySheet) -> Void) {
        var next = sheet
        change(&next)
        edit(next)
    }

    private func forget() {
        value = ""
        number = ""
        expiry = ""
        cvc = ""
        holder = ""
        postal = ""
    }
}

extension View {
    /// A digits keyboard on iPhone and iPad.
    fileprivate func numeric() -> some View {
        #if os(iOS)
            keyboardType(.numberPad)
        #else
            self
        #endif
    }
}
