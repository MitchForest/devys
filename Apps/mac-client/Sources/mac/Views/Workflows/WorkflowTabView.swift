import AppFeatures
import Canvas
import SwiftUI
import UI

@MainActor
struct WorkflowTabView: View {
    @Environment(\.devysTheme) var theme

    enum DisplayMode: Hashable {
        case design
        case run
    }

    let definition: WorkflowDefinition?
    let run: WorkflowRun?
    let lastErrorMessage: String?
    let canOpenDiff: Bool
    let initialMode: DisplayMode

    let onUpdateDefinition: (WindowFeature.WorkflowDefinitionUpdate) -> Void
    let onCreateWorker: () -> Void
    let onUpdateWorker: (String, WindowFeature.WorkflowWorkerUpdate) -> Void
    let onDeleteWorker: (String) -> Void
    let onReplaceGraph: ([WorkflowNode], [WorkflowEdge]) -> Void
    let onDeleteDefinition: () -> Void

    let onStartRun: () -> Void
    let onContinueRun: () -> Void
    let onRestartRun: () -> Void
    let onStopRun: () -> Void
    let onDeleteRun: () -> Void
    let onChooseEdge: (String) -> Void
    let onAppendFollowUpTicket: (String, String) -> Void
    let onOpenPromptArtifact: () -> Void
    let onOpenTerminal: () -> Void
    let onOpenDiff: () -> Void

    let onOpenPlan: () -> Void

    @State var mode: DisplayMode
    @State var canvas = CanvasModel()
    @State var lastCanvasSignature = ""
    @State var followUpSectionTitle = "Follow-Ups"
    @State var followUpText = ""
    @State var isDeleteRunConfirmationPresented = false
    @State var isDeleteDefinitionConfirmationPresented = false

    init(
        definition: WorkflowDefinition?,
        run: WorkflowRun?,
        lastErrorMessage: String?,
        canOpenDiff: Bool,
        initialMode: DisplayMode,
        onUpdateDefinition: @escaping (WindowFeature.WorkflowDefinitionUpdate) -> Void,
        onCreateWorker: @escaping () -> Void,
        onUpdateWorker: @escaping (String, WindowFeature.WorkflowWorkerUpdate) -> Void,
        onDeleteWorker: @escaping (String) -> Void,
        onReplaceGraph: @escaping ([WorkflowNode], [WorkflowEdge]) -> Void,
        onDeleteDefinition: @escaping () -> Void,
        onStartRun: @escaping () -> Void,
        onContinueRun: @escaping () -> Void,
        onRestartRun: @escaping () -> Void,
        onStopRun: @escaping () -> Void,
        onDeleteRun: @escaping () -> Void,
        onChooseEdge: @escaping (String) -> Void,
        onAppendFollowUpTicket: @escaping (String, String) -> Void,
        onOpenPromptArtifact: @escaping () -> Void,
        onOpenTerminal: @escaping () -> Void,
        onOpenDiff: @escaping () -> Void,
        onOpenPlan: @escaping () -> Void
    ) {
        self.definition = definition
        self.run = run
        self.lastErrorMessage = lastErrorMessage
        self.canOpenDiff = canOpenDiff
        self.initialMode = initialMode
        self.onUpdateDefinition = onUpdateDefinition
        self.onCreateWorker = onCreateWorker
        self.onUpdateWorker = onUpdateWorker
        self.onDeleteWorker = onDeleteWorker
        self.onReplaceGraph = onReplaceGraph
        self.onDeleteDefinition = onDeleteDefinition
        self.onStartRun = onStartRun
        self.onContinueRun = onContinueRun
        self.onRestartRun = onRestartRun
        self.onStopRun = onStopRun
        self.onDeleteRun = onDeleteRun
        self.onChooseEdge = onChooseEdge
        self.onAppendFollowUpTicket = onAppendFollowUpTicket
        self.onOpenPromptArtifact = onOpenPromptArtifact
        self.onOpenTerminal = onOpenTerminal
        self.onOpenDiff = onOpenDiff
        self.onOpenPlan = onOpenPlan
        self._mode = State(initialValue: initialMode)
    }

    var body: some View {
        Group {
            if let definition {
                VStack(alignment: .leading, spacing: 0) {
                    toolbar(for: definition)
                    toolbarDivider()
                    errorBanner()
                    mainLayout(for: definition)
                }
                .onAppear {
                    applyDefinitionToCanvas(definition)
                }
                .onChange(of: definition.updatedAt) { _, _ in
                    applyDefinitionToCanvas(definition)
                }
                .onChange(of: canvas.nodes) { _, _ in
                    syncCanvasGraph(definition)
                }
                .onChange(of: canvas.connectors) { _, _ in
                    syncCanvasGraph(definition)
                }
            } else {
                EmptyState(
                    icon: "square.and.pencil",
                    title: "Workflow unavailable",
                    description: "The selected workflow could not be loaded."
                )
            }
        }
        .background(theme.base)
        .alert("Delete Run?", isPresented: $isDeleteRunConfirmationPresented) {
            Button("Delete Run", role: .destructive, action: onDeleteRun)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes the saved run history, attempts, and artifacts for this run. "
                + "It does not delete the workflow definition or plan file."
            )
        }
        .alert("Delete Workflow?", isPresented: $isDeleteDefinitionConfirmationPresented) {
            Button("Delete Workflow", role: .destructive, action: onDeleteDefinition)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the workflow definition. Run history is preserved until each run is removed.")
        }
    }

    @ViewBuilder
    func mainLayout(for definition: WorkflowDefinition) -> some View {
        switch mode {
        case .design:
            designLayout(for: definition)
        case .run:
            runLayout(for: definition)
        }
    }

    @ViewBuilder
    private func designLayout(for definition: WorkflowDefinition) -> some View {
        HStack(alignment: .top, spacing: 0) {
            canvasPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            sidebarDivider()
            designInspector(for: definition)
                .frame(width: 360)
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func runLayout(for definition: WorkflowDefinition) -> some View {
        if let run {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    canvasPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    runStrip(for: run, definition: definition)
                }
                sidebarDivider()
                runInspector(for: run, definition: definition)
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                canvasPane()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: Spacing.space2) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(theme.textSecondary)
                    Text("No active run — switch to Design and press Run to launch this workflow.")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                }
                .padding(Spacing.space4)
                .background(theme.base)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: Spacing.borderWidth)
                }
            }
        }
    }

    private func canvasPane() -> some View {
        WorkflowCanvasView(canvas: canvas)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorBanner() -> some View {
        if let message = lastErrorMessage, !message.isEmpty {
            HStack(alignment: .top, spacing: Spacing.space2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.error)
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(theme.error)
                Spacer()
            }
            .padding(.horizontal, Spacing.space4)
            .padding(.vertical, Spacing.space2)
            .background(theme.error.opacity(0.08))
        }
    }

    private func toolbarDivider() -> some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: Spacing.borderWidth)
    }

    private func sidebarDivider() -> some View {
        Rectangle()
            .fill(theme.border)
            .frame(width: Spacing.borderWidth)
    }
}
