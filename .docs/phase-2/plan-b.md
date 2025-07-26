// components/claude-code-ide.tsx
import React, { useRef, useEffect, useState, useCallback } from 'react';
import { EditorView, basicSetup } from 'codemirror';
import { EditorState } from '@codemirror/state';
import { javascript } from '@codemirror/lang-javascript';
import { oneDark } from '@codemirror/theme-one-dark';
import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebLinksAddon } from 'xterm-addon-web-links';
import { useChat } from '@ai-sdk/react';
import { 
  ClaudeCodeTransport,
  ProjectManager,
  SubAgentManager 
} from '@your-org/claude-code-integration';
import 'xterm/css/xterm.css';

interface ClaudeCodeIDEProps {
  projectPath: string;
  initialFile?: string;
}

export function ClaudeCodeIDE({ projectPath, initialFile }: ClaudeCodeIDEProps) {
  // Refs for editor and terminal
  const editorRef = useRef<HTMLDivElement>(null);
  const terminalRef = useRef<HTMLDivElement>(null);
  const editorViewRef = useRef<EditorView | null>(null);
  const terminalInstanceRef = useRef<Terminal | null>(null);
  
  // State
  const [currentFile, setCurrentFile] = useState(initialFile || '');
  const [files, setFiles] = useState<string[]>([]);
  const [activePanel, setActivePanel] = useState<'chat' | 'terminal'>('chat');
  const [commandPalette, setCommandPalette] = useState(false);
  const [selectedAgent, setSelectedAgent] = useState<string | null>(null);
  const [agents, setAgents] = useState<any[]>([]);

  // Initialize managers
  const projectManager = useRef(new ProjectManager(projectPath));
  const subAgentManager = useRef(new SubAgentManager(projectPath));

  // Chat integration
  const transport = new ClaudeCodeTransport({
    workingDirectory: projectPath,
    maxSteps: 10,
    systemPrompt: selectedAgent 
      ? `You are working with the ${selectedAgent} agent.` 
      : undefined,
  });

  const { 
    messages, 
    sendMessage, 
    status,
    addToolResult 
  } = useChat({
    transport,
    maxSteps: 5,
    onToolCall: async ({ toolCall }) => {
      // Handle tool calls that affect the IDE
      switch (toolCall.toolName) {
        case 'openFile':
          await openFile(toolCall.args.path);
          return { success: true };
        
        case 'runCommand':
          await runTerminalCommand(toolCall.args.command);
          return { success: true };
        
        case 'editFile':
          await editFile(toolCall.args.path, toolCall.args.content);
          return { success: true };
      }
    },
  });

  // Initialize CodeMirror
  useEffect(() => {
    if (!editorRef.current || editorViewRef.current) return;

    const startState = EditorState.create({
      doc: '',
      extensions: [
        basicSetup,
        javascript(),
        oneDark,
        EditorView.updateListener.of((update) => {
          if (update.docChanged && currentFile) {
            // Auto-save on change
            saveFile(currentFile, update.state.doc.toString());
          }
        }),
      ],
    });

    const view = new EditorView({
      state: startState,
      parent: editorRef.current,
    });

    editorViewRef.current = view;

    return () => {
      view.destroy();
    };
  }, []);

  // Initialize Terminal
  useEffect(() => {
    if (!terminalRef.current || terminalInstanceRef.current) return;

    const terminal = new Terminal({
      theme: {
        background: '#1e1e1e',
        foreground: '#ffffff',
      },
      fontSize: 14,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
    });

    const fitAddon = new FitAddon();
    const webLinksAddon = new WebLinksAddon();
    
    terminal.loadAddon(fitAddon);
    terminal.loadAddon(webLinksAddon);
    
    terminal.open(terminalRef.current);
    fitAddon.fit();

    // Connect to Claude Code process
    connectTerminalToClaudeCode(terminal);

    terminalInstanceRef.current = terminal;

    // Handle resize
    const resizeObserver = new ResizeObserver(() => {
      fitAddon.fit();
    });
    resizeObserver.observe(terminalRef.current);

    return () => {
      resizeObserver.disconnect();
      terminal.dispose();
    };
  }, []);

  // Load agents
  useEffect(() => {
    subAgentManager.current.loadSubAgents().then(setAgents);
  }, []);

  // File operations
  const openFile = async (path: string) => {
    try {
      const response = await fetch(`/api/files/${encodeURIComponent(path)}`);
      const content = await response.text();
      
      if (editorViewRef.current) {
        editorViewRef.current.dispatch({
          changes: {
            from: 0,
            to: editorViewRef.current.state.doc.length,
            insert: content,
          },
        });
      }
      
      setCurrentFile(path);
    } catch (error) {
      console.error('Failed to open file:', error);
    }
  };

  const saveFile = async (path: string, content: string) => {
    try {
      await fetch(`/api/files/${encodeURIComponent(path)}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'text/plain' },
        body: content,
      });
    } catch (error) {
      console.error('Failed to save file:', error);
    }
  };

  const editFile = async (path: string, content: string) => {
    await openFile(path);
    if (editorViewRef.current) {
      editorViewRef.current.dispatch({
        changes: {
          from: 0,
          to: editorViewRef.current.state.doc.length,
          insert: content,
        },
      });
    }
  };

  // Terminal operations
  const connectTerminalToClaudeCode = (terminal: Terminal) => {
    // Create a WebSocket connection to Claude Code
    const ws = new WebSocket(`ws://localhost:3001/claude-code/${projectPath}`);
    
    ws.onopen = () => {
      terminal.writeln('Connected to Claude Code terminal');
    };

    ws.onmessage = (event) => {
      terminal.write(event.data);
    };

    terminal.onData((data) => {
      ws.send(data);
    });

    ws.onerror = (error) => {
      terminal.writeln(`\r\nError: ${error}`);
    };

    ws.onclose = () => {
      terminal.writeln('\r\nDisconnected from Claude Code');
    };
  };

  const runTerminalCommand = async (command: string) => {
    if (terminalInstanceRef.current) {
      terminalInstanceRef.current.writeln(`$ ${command}`);
      // Send command through WebSocket
    }
  };

  // Command Palette
  const CommandPalette = () => {
    const [query, setQuery] = useState('');
    const [results, setResults] = useState<any[]>([]);

    useEffect(() => {
      if (!query) {
        setResults([]);
        return;
      }

      // Search commands
      const commands = [
        { id: 'new-session', label: 'New Session', action: () => createNewSession() },
        { id: 'open-file', label: 'Open File...', action: () => showFilePicker() },
        { id: 'run-tests', label: 'Run Tests', action: () => runTerminalCommand('npm test') },
        { id: 'select-agent', label: 'Select Agent...', action: () => showAgentPicker() },
        ...agents.map(agent => ({
          id: `agent-${agent.name}`,
          label: `Use ${agent.name}: ${agent.description}`,
          action: () => setSelectedAgent(agent.name),
        })),
      ];

      const filtered = commands.filter(cmd => 
        cmd.label.toLowerCase().includes(query.toLowerCase())
      );
      setResults(filtered);
    }, [query]);

    return (
      <div className="command-palette">
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Type a command..."
          autoFocus
        />
        <div className="results">
          {results.map((result) => (
            <div
              key={result.id}
              className="result-item"
              onClick={() => {
                result.action();
                setCommandPalette(false);
              }}
            >
              {result.label}
            </div>
          ))}
        </div>
      </div>
    );
  };

  // IDE Layout
  return (
    <div className="claude-code-ide">
      {/* Command Palette Overlay */}
      {commandPalette && (
        <div className="command-palette-overlay" onClick={() => setCommandPalette(false)}>
          <div onClick={(e) => e.stopPropagation()}>
            <CommandPalette />
          </div>
        </div>
      )}

      {/* Main Layout */}
      <div className="ide-layout">
        {/* Sidebar */}
        <div className="sidebar">
          <div className="sidebar-header">
            <h3>Files</h3>
          </div>
          <div className="file-tree">
            {files.map((file) => (
              <div
                key={file}
                className={`file-item ${file === currentFile ? 'active' : ''}`}
                onClick={() => openFile(file)}
              >
                {file}
              </div>
            ))}
          </div>
          
          <div className="sidebar-section">
            <h4>Agents</h4>
            <div className="agent-list">
              {agents.map((agent) => (
                <div
                  key={agent.name}
                  className={`agent-item ${selectedAgent === agent.name ? 'active' : ''}`}
                  onClick={() => setSelectedAgent(agent.name)}
                >
                  <div className="agent-name">{agent.name}</div>
                  <div className="agent-type">{agent.type}</div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Main Content */}
        <div className="main-content">
          {/* Editor */}
          <div className="editor-container">
            <div className="editor-header">
              <span>{currentFile || 'No file open'}</span>
              <div className="editor-actions">
                <button onClick={() => setCommandPalette(true)}>
                  ⌘K (Command Palette)
                </button>
              </div>
            </div>
            <div ref={editorRef} className="editor" />
          </div>

          {/* Bottom Panel */}
          <div className="bottom-panel">
            <div className="panel-tabs">
              <button
                className={activePanel === 'chat' ? 'active' : ''}
                onClick={() => setActivePanel('chat')}
              >
                Chat
              </button>
              <button
                className={activePanel === 'terminal' ? 'active' : ''}
                onClick={() => setActivePanel('terminal')}
              >
                Terminal
              </button>
            </div>

            {/* Chat Panel */}
            {activePanel === 'chat' && (
              <div className="chat-panel">
                <div className="chat-messages">
                  {messages.map((message) => (
                    <div key={message.id} className={`message ${message.role}`}>
                      {message.parts.map((part, index) => {
                        if (part.type === 'text') {
                          return <div key={index}>{part.text}</div>;
                        }
                        if (part.type === 'tool-invocation') {
                          return (
                            <div key={index} className="tool-invocation">
                              <span className="tool-name">
                                {part.toolInvocation.toolName}
                              </span>
                              {part.toolInvocation.state === 'result' && (
                                <span className="tool-result">✓</span>
                              )}
                            </div>
                          );
                        }
                        return null;
                      })}
                    </div>
                  ))}
                </div>
                
                <form
                  className="chat-input"
                  onSubmit={(e) => {
                    e.preventDefault();
                    const input = (e.target as any).message.value;
                    sendMessage({ text: input });
                    (e.target as any).message.value = '';
                  }}
                >
                  <input
                    name="message"
                    placeholder={
                      selectedAgent 
                        ? `Ask ${selectedAgent}...` 
                        : 'Ask Claude Code...'
                    }
                    disabled={status !== 'ready'}
                  />
                  <button type="submit" disabled={status !== 'ready'}>
                    Send
                  </button>
                </form>
              </div>
            )}

            {/* Terminal Panel */}
            {activePanel === 'terminal' && (
              <div ref={terminalRef} className="terminal-panel" />
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// styles/claude-code-ide.css
const styles = `
.claude-code-ide {
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: #1e1e1e;
  color: #ffffff;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
}

.command-palette-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.8);
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding-top: 100px;
  z-index: 1000;
}

.command-palette {
  background: #2d2d2d;
  border-radius: 8px;
  width: 600px;
  max-height: 400px;
  overflow: hidden;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
}

.command-palette input {
  width: 100%;
  padding: 16px;
  background: transparent;
  border: none;
  color: #ffffff;
  font-size: 16px;
  outline: none;
  border-bottom: 1px solid #444;
}

.command-palette .results {
  max-height: 350px;
  overflow-y: auto;
}

.command-palette .result-item {
  padding: 12px 16px;
  cursor: pointer;
  transition: background 0.1s;
}

.command-palette .result-item:hover {
  background: #3a3a3a;
}

.ide-layout {
  display: flex;
  flex: 1;
  overflow: hidden;
}

.sidebar {
  width: 240px;
  background: #252526;
  border-right: 1px solid #1e1e1e;
  display: flex;
  flex-direction: column;
}

.sidebar-header {
  padding: 12px;
  border-bottom: 1px solid #1e1e1e;
}

.sidebar-header h3 {
  margin: 0;
  font-size: 14px;
  font-weight: normal;
  text-transform: uppercase;
  opacity: 0.8;
}

.file-tree {
  flex: 1;
  overflow-y: auto;
}

.file-item {
  padding: 8px 16px;
  cursor: pointer;
  font-size: 14px;
  transition: background 0.1s;
}

.file-item:hover {
  background: #2a2a2a;
}

.file-item.active {
  background: #094771;
}

.sidebar-section {
  border-top: 1px solid #1e1e1e;
  padding: 12px;
}

.sidebar-section h4 {
  margin: 0 0 8px 0;
  font-size: 12px;
  text-transform: uppercase;
  opacity: 0.6;
}

.agent-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.agent-item {
  padding: 8px;
  border-radius: 4px;
  cursor: pointer;
  transition: background 0.1s;
}

.agent-item:hover {
  background: #2a2a2a;
}

.agent-item.active {
  background: #094771;
}

.agent-name {
  font-size: 13px;
  font-weight: 500;
}

.agent-type {
  font-size: 11px;
  opacity: 0.6;
  text-transform: uppercase;
}

.main-content {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.editor-container {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0;
}

.editor-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 16px;
  background: #2d2d2d;
  border-bottom: 1px solid #1e1e1e;
  font-size: 14px;
}

.editor-actions button {
  background: #094771;
  border: none;
  color: white;
  padding: 4px 12px;
  border-radius: 4px;
  font-size: 12px;
  cursor: pointer;
}

.editor {
  flex: 1;
  overflow: auto;
}

.bottom-panel {
  height: 300px;
  display: flex;
  flex-direction: column;
  border-top: 1px solid #1e1e1e;
}

.panel-tabs {
  display: flex;
  background: #2d2d2d;
  border-bottom: 1px solid #1e1e1e;
}

.panel-tabs button {
  padding: 8px 16px;
  background: transparent;
  border: none;
  color: #ffffff;
  font-size: 13px;
  cursor: pointer;
  opacity: 0.7;
  transition: opacity 0.1s;
}

.panel-tabs button:hover {
  opacity: 1;
}

.panel-tabs button.active {
  opacity: 1;
  border-bottom: 2px solid #007acc;
}

.chat-panel {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.chat-messages {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
}

.message {
  margin-bottom: 16px;
}

.message.user {
  text-align: right;
}

.message.assistant {
  text-align: left;
}

.tool-invocation {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 4px 8px;
  background: #2d2d2d;
  border-radius: 4px;
  font-size: 12px;
  margin: 4px 0;
}

.tool-name {
  font-weight: 500;
}

.tool-result {
  color: #4ec9b0;
}

.chat-input {
  display: flex;
  padding: 16px;
  border-top: 1px solid #2d2d2d;
}

.chat-input input {
  flex: 1;
  background: #2d2d2d;
  border: 1px solid #3a3a3a;
  color: white;
  padding: 8px 12px;
  border-radius: 4px;
  outline: none;
}

.chat-input button {
  margin-left: 8px;
  padding: 8px 16px;
  background: #007acc;
  border: none;
  color: white;
  border-radius: 4px;
  cursor: pointer;
}

.chat-input button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.terminal-panel {
  flex: 1;
  background: #1e1e1e;
}

/* CodeMirror theme adjustments */
.cm-editor {
  height: 100%;
}

.cm-scroller {
  font-family: 'Menlo', 'Monaco', 'Courier New', monospace;
  font-size: 14px;
}
`;