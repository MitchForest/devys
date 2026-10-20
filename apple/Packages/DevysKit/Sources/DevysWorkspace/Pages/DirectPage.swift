import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// A direct-message conversation with one employee, filling the main pane.
struct DirectPage: View {
    let store: StoreOf<Workspace>
    let employeeID: String

    var body: some View {
        if let employee = store.snapshot.employees.first(where: { $0.id == employeeID }) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    AboutButton(name: employee.name) {
                        HStack(spacing: 10) {
                            Portrait(store.state.portrait(for: employee), size: 32, mood: mood(employee), label: employee.name)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(employee.name).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                                // Only what's changing; who they are is a click away.
                                if employee.paused || store.state.isWorking(employee.id) {
                                    Text(EmployeeLine.status(employee, working: store.state.isWorking(employee.id)))
                                        .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                                }
                            }
                        }
                    } about: {
                        DirectInfo(store: store, employeeID: employee.id)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, DevysSpacing.regular)
                .padding(.vertical, 10)
                Rectangle().fill(DevysColors.hairline).frame(height: 1)
                ConversationPane(store: store, key: .direct(employee.id), voice: true)
            }
        } else {
            PageBody { EmptyNote(text: "This employee is no longer on the team.") }
        }
    }

    /// While talking by voice, the face follows the conversation.
    private func mood(_ employee: Employee) -> BotMood {
        store.state.voiceMood ?? store.state.mood(for: employee)
    }
}
