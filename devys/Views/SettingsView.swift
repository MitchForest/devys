//
//  SettingsView.swift
//  devys
//
//  Application settings.
//

import SwiftUI

struct SettingsView: View {
    // MARK: - AppStorage
    
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("codexPath") private var codexPath = "/usr/local/bin/codex"
    @AppStorage("claudePath") private var claudePath = "/usr/local/bin/claude"
    @AppStorage("defaultAgent") private var defaultAgent = AgentType.codex
    
    // MARK: - Body
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                appearance: $appearance,
                defaultAgent: $defaultAgent
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            AgentSettingsView(
                codexPath: $codexPath,
                claudePath: $claudePath
            )
            .tabItem {
                Label("Agents", systemImage: "cpu")
            }
        }
        .frame(width: 450, height: 250)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Binding var appearance: Appearance
    @Binding var defaultAgent: AgentType
    
    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { option in
                        Label(option.label, systemImage: option.icon)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }
            
            Section {
                Picker("Default Agent", selection: $defaultAgent) {
                    ForEach(AgentType.allCases, id: \.self) { agent in
                        Label(agent.displayName, systemImage: agent.icon)
                            .tag(agent)
                    }
                }
            } header: {
                Text("Agent")
            } footer: {
                Text("New workspaces will use this agent by default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Agent Settings

struct AgentSettingsView: View {
    @Binding var codexPath: String
    @Binding var claudePath: String
    
    @State private var codexValid = false
    @State private var claudeValid = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Codex CLI Path", text: $codexPath)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Browse...") {
                        browsePath { codexPath = $0 }
                    }
                    
                    Image(systemName: codexValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(codexValid ? .green : .red)
                }
            } header: {
                Text("Codex")
            }
            
            Section {
                HStack {
                    TextField("Claude CLI Path", text: $claudePath)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Browse...") {
                        browsePath { claudePath = $0 }
                    }
                    
                    Image(systemName: claudeValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(claudeValid ? .green : .red)
                }
            } header: {
                Text("Claude Code")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            validatePaths()
        }
        .onChange(of: codexPath) { _, _ in validatePaths() }
        .onChange(of: claudePath) { _, _ in validatePaths() }
    }
    
    private func validatePaths() {
        codexValid = FileManager.default.isExecutableFile(atPath: codexPath)
        claudeValid = FileManager.default.isExecutableFile(atPath: claudePath)
    }
    
    private func browsePath(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the CLI executable"
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
