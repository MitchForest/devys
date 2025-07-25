// Import will be injected at runtime to avoid circular dependency
let wsManager: { sendTerminalOutput?: (terminalId: string, data: string) => void };

/**
 * Bridge between Claude Code's Bash tool and the terminal UI
 * Routes command output to the appropriate terminal session
 */
export class TerminalBridge {
  private activeTerminalId: string | null = null;
  private commandMap: Map<string, string> = new Map(); // command -> terminalId

  /**
   * Set the active terminal ID for routing output
   */
  setActiveTerminal(terminalId: string) {
    this.activeTerminalId = terminalId;
  }

  /**
   * Set the WebSocket manager instance
   */
  setWsManager(manager: { sendTerminalOutput?: (terminalId: string, data: string) => void }) {
    wsManager = manager;
  }

  /**
   * Route a command to a specific terminal
   */
  routeCommand(command: string, terminalId?: string) {
    const id = terminalId || this.activeTerminalId;
    if (id) {
      this.commandMap.set(command, id);
      
      // Send command to terminal via WebSocket if available
      if (wsManager?.sendTerminalOutput) {
        wsManager.sendTerminalOutput(id, `$ ${command}\n`);
      }
    }
  }

  /**
   * Send output from Claude Code's Bash tool to the terminal
   */
  sendOutput(output: string, command?: string) {
    let terminalId = this.activeTerminalId;
    
    // Try to find the terminal ID from the command
    if (command && this.commandMap.has(command)) {
      terminalId = this.commandMap.get(command)!;
    }
    
    if (terminalId && wsManager?.sendTerminalOutput) {
      wsManager.sendTerminalOutput(terminalId, output);
    }
  }

  /**
   * Send error output to the terminal
   */
  sendError(error: string, command?: string) {
    this.sendOutput(`Error: ${error}\n`, command);
  }

  /**
   * Mark command as completed
   */
  completeCommand(command: string, exitCode: number = 0) {
    const terminalId = this.commandMap.get(command);
    if (terminalId && wsManager?.sendTerminalOutput) {
      wsManager.sendTerminalOutput(terminalId, `\nProcess exited with code ${exitCode}\n$ `);
      this.commandMap.delete(command);
    }
  }

  /**
   * Clear all command mappings
   */
  clear() {
    this.commandMap.clear();
    this.activeTerminalId = null;
  }
}

// Export singleton instance
export const terminalBridge = new TerminalBridge();