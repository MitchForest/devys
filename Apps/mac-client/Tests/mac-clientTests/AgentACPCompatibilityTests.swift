import Foundation
import Testing
@testable import mac_client

private enum AgentACPCompatibilityFixtures {
    static let codexSessionNewPayload = Data(
        """
        {
          "sessionId": "019d6ad1-ec7b-7462-b417-6a619fd29438",
          "modes": {
            "currentModeId": "auto",
            "availableModes": [
              {
                "id": "read-only",
                "name": "Read Only",
                "description": "Codex can read files in the current workspace."
              },
              {
                "id": "auto",
                "name": "Default",
                "description": "Codex can read and edit files in the current workspace."
              }
            ]
          },
          "configOptions": [
            {
              "id": "mode",
              "name": "Approval Preset",
              "description": "Choose an approval preset for your session",
              "category": "mode",
              "type": "select",
              "currentValue": "auto",
              "options": [
                {
                  "value": "read-only",
                  "name": "Read Only",
                  "description": "Codex can read files in the current workspace."
                },
                {
                  "value": "auto",
                  "name": "Default",
                  "description": "Codex can read and edit files in the current workspace."
                }
              ]
            },
            {
              "id": "reasoning_effort",
              "name": "Reasoning Effort",
              "description": "Choose how much reasoning effort the model should use",
              "category": "thought_level",
              "type": "select",
              "currentValue": "high",
              "options": [
                {
                  "value": "low",
                  "name": "Low",
                  "description": "Fast responses with lighter reasoning"
                },
                {
                  "value": "high",
                  "name": "High",
                  "description": "Greater reasoning depth for complex problems"
                }
              ]
            }
          ]
        }
        """.utf8
    )

    static let claudeSessionNewPayload = Data(
        """
        {
          "sessionId": "0dfcc308-869f-41b1-9723-aed62551a5fc",
          "modes": {
            "currentModeId": "default",
            "availableModes": [
              {
                "id": "default",
                "name": "Default",
                "description": "Standard behavior"
              },
              {
                "id": "plan",
                "name": "Plan Mode",
                "description": "Planning mode, no actual tool execution"
              }
            ]
          },
          "configOptions": [
            {
              "id": "mode",
              "name": "Mode",
              "description": "Session permission mode",
              "category": "mode",
              "type": "select",
              "currentValue": "default",
              "options": [
                {
                  "value": "default",
                  "name": "Default",
                  "description": "Standard behavior"
                },
                {
                  "value": "plan",
                  "name": "Plan Mode",
                  "description": "Planning mode"
                }
              ]
            },
            {
              "id": "model",
              "name": "Model",
              "description": "AI model to use",
              "category": "model",
              "type": "select",
              "currentValue": "opus[1m]",
              "options": [
                {
                  "value": "default",
                  "name": "Default (recommended)",
                  "description": "Use the default model"
                },
                {
                  "value": "opus[1m]",
                  "name": "Opus (1M context)",
                  "description": "Most capable for complex work"
                }
              ]
            }
          ]
        }
        """.utf8
    )
}

@Suite("Agent ACP Compatibility Tests")
struct AgentACPCompatibilityTests {
    @Test("Codex session/new payload decodes")
    func codexSessionNewPayloadDecodes() throws {
        let response = try decodeSessionNewResponse(
            from: AgentACPCompatibilityFixtures.codexSessionNewPayload
        )

        #expect(response.sessionId.rawValue == "019d6ad1-ec7b-7462-b417-6a619fd29438")
        #expect(response.modes?.currentModeId == "auto")
        #expect(response.configOptions?.map(\.id) == ["mode", "reasoning_effort"])
        #expect(response.configOptions?.last?.currentValue == "high")
    }

    @Test("Claude session/new payload decodes")
    func claudeSessionNewPayloadDecodes() throws {
        let response = try decodeSessionNewResponse(
            from: AgentACPCompatibilityFixtures.claudeSessionNewPayload
        )

        #expect(response.sessionId.rawValue == "0dfcc308-869f-41b1-9723-aed62551a5fc")
        #expect(response.modes?.currentModeId == "default")
        #expect(response.configOptions?.map(\.id) == ["mode", "model"])
        #expect(response.configOptions?.last?.currentValue == "opus[1m]")
    }

    @Test("Legacy flat mode payload decodes")
    func legacyFlatModePayloadDecodes() throws {
        let payload = Data(
            """
            {
              "sessionId": "legacy-session",
              "currentModeId": "default",
              "availableModes": [
                {
                  "id": "default",
                  "name": "Default"
                }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(AgentSessionLoadResponse.self, from: payload)

        #expect(response.sessionId.rawValue == "legacy-session")
        #expect(response.modes?.currentModeId == "default")
        #expect(response.modes?.availableModes.map(\.id) == ["default"])
    }

    @Test("Command input falls back across compatible keys")
    func commandInputFallbacksDecode() throws {
        let payload = Data(
            """
            {
              "sessionId": "session-commands",
              "update": {
                "sessionUpdate": "available_commands_update",
                "availableCommands": [
                  {
                    "name": "review-branch",
                    "description": "Review the code changes against a branch",
                    "input": {
                      "placeholder": "branch name"
                    }
                  },
                  {
                    "name": "compact",
                    "description": "Summarize the conversation",
                    "input": null
                  }
                ]
              }
            }
            """.utf8
        )

        let notification = try JSONDecoder().decode(AgentSessionNotification.self, from: payload)
        guard case .availableCommandsUpdate(let commands) = notification.update else {
            Issue.record("Expected available commands update")
            return
        }

        #expect(commands.first?.input?.hint == "branch name")
        #expect(commands.last?.input == nil)
    }

    private func decodeSessionNewResponse(from payload: Data) throws -> AgentSessionNewResponse {
        try JSONDecoder().decode(AgentSessionNewResponse.self, from: payload)
    }
}
