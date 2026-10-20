import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The model an employee thinks with, what a turn costs, and what it has spent.
struct ModelSection: View {
    let store: StoreOf<Workspace>
    let employee: Employee

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            HStack(alignment: .center, spacing: DevysSpacing.compact) {
                Image(systemName: "cpu")
                    .foregroundStyle(DevysColors.ink3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                    Text(model?.label ?? employee.model)
                        .font(DevysTypography.body.weight(.semibold))
                        .foregroundStyle(DevysColors.ink)
                    if let model {
                        Text("\(model.provider) · \(ModelText.perTurn(model))")
                            .font(DevysTypography.secondary)
                            .foregroundStyle(DevysColors.ink2)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                if let catalog = store.models.catalog {
                    ModelChooser(catalog: catalog, selection: employee.model, label: "Change \(employee.name)'s model") { id in
                        store.send(.modelSelected(employee.id, id))
                    }
                } else {
                    Button("Change") {}.buttonStyle(DevysButtonStyle(.quiet, compact: true)).disabled(true)
                }
            }
            if let usage = store.state.usage(of: employee.id), usage.totalCost > 0 {
                Text(ModelText.spend(usage))
                    .font(DevysTypography.secondary)
                    .foregroundStyle(DevysColors.ink3)
            }
            if let error = store.models.errors[employee.id] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(DevysTypography.secondary)
                    .foregroundStyle(DevysColors.red)
            }
        }
        .devysCard()
        .onAppear { store.send(.modelRequested(employee.id)) }
        .onChange(of: employee.id) { _, id in store.send(.modelRequested(id)) }
    }

    private var model: ModelCatalog.Model? { store.models.catalog?.model(employee.model) }
}

/// "Change" opens every model the server offers: a popover on the Mac, a sheet on iPhone and iPad.
struct ModelChooser: View {
    let catalog: ModelCatalog
    let selection: String
    let label: String
    let choose: (String) -> Void
    @State private var isChoosing = false

    var body: some View {
        let button = Button("Change") { isChoosing = true }
            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            .accessibilityLabel(label)
        #if os(macOS)
            button.popover(isPresented: $isChoosing, arrowEdge: .bottom) {
                ModelList(catalog: catalog, selection: selection, choose: pick)
                    .frame(width: 380, height: 440)
            }
        #else
            button.sheet(isPresented: $isChoosing) {
                NavigationStack {
                    ModelList(catalog: catalog, selection: selection, choose: pick)
                        .navigationTitle("Model")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { isChoosing = false } }
                        }
                }
                .presentationDetents([.medium, .large])
            }
        #endif
    }

    private func pick(_ id: String) {
        isChoosing = false
        choose(id)
    }
}

/// Every model the server offers, one section per vendor; the default is marked.
private struct ModelList: View {
    let catalog: ModelCatalog
    let selection: String
    let choose: (String) -> Void

    var body: some View {
        List {
            ForEach(catalog.vendors, id: \.vendor) { group in
                Section(group.vendor) {
                    ForEach(group.models) { model in
                        Button { choose(model.id) } label: {
                            ModelRow(model: model, isDefault: model.id == catalog.defaults.employee, isSelected: model.id == selection)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.id == selection ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private struct ModelRow: View {
    let model: ModelCatalog.Model
    let isDefault: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DevysSpacing.compact) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.label).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    if isDefault {
                        Text("Default")
                            .font(DevysTypography.caption)
                            .foregroundStyle(DevysColors.ink2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(DevysColors.well, in: Capsule())
                    }
                }
                Text(model.summary).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                Text("\(model.provider) · \(ModelText.perTurn(model))")
                    .font(DevysTypography.caption)
                    .foregroundStyle(DevysColors.ink3)
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(DevysTypography.control)
                    .foregroundStyle(DevysColors.indigo)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Plain wording for prices and spend.
enum ModelText {
    static func perTurn(_ model: ModelCatalog.Model) -> String {
        "≈ \(dollars(model.typicalTurnUsd)) per turn"
    }

    static func spend(_ usage: RuntimeUsage) -> String {
        let spent = "Spent \(dollars(usage.totalCost))"
        guard let share = usage.cacheShare else { return spent }
        return "\(spent) · \(share.formatted(.percent.precision(.fractionLength(0)))) of input from cache"
    }

    /// Cents for ordinary amounts; small amounts keep enough digits to be meaningful.
    static func dollars(_ value: Double) -> String {
        let currency = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        return value > 0 && value < 0.01
            ? value.formatted(currency.precision(.significantDigits(1...2)))
            : value.formatted(currency.precision(.fractionLength(2)))
    }
}
