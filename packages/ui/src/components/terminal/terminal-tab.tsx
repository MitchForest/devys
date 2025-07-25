import React, { useEffect, useRef, useCallback } from 'react';
import { TerminalWithRef } from './terminal';
import { terminalService } from '../../services/terminal-service';
import type { TerminalSession, TerminalOutput } from '../../services/terminal-service';

interface TerminalTabProps {
  session: TerminalSession;
  theme?: 'dark' | 'light';
  onTitleChange?: (title: string) => void;
}

export function TerminalTab({ session, theme = 'dark', onTitleChange }: TerminalTabProps) {
  const terminalRef = useRef<{
    write: (data: string) => void;
    writeln: (data: string) => void;
    clear: () => void;
    focus: () => void;
    fit: () => void;
    getTerminal: () => import('xterm').Terminal | null;
  }>(null);

  const commandBuffer = useRef<string>('');
  const cursorPosition = useRef<number>(0);

  // Handle terminal output
  useEffect(() => {
    const handleOutput = (output: TerminalOutput) => {
      if (output.sessionId === session.id && terminalRef.current) {
        terminalRef.current.write(output.data);
      }
    };

    const handleSessionCleared = (sessionId: string) => {
      if (sessionId === session.id && terminalRef.current) {
        terminalRef.current.clear();
        terminalRef.current.write('$ ');
      }
    };

    const handleExit = ({ sessionId, code }: { sessionId: string; code: number }) => {
      if (sessionId === session.id && terminalRef.current) {
        terminalRef.current.writeln(`\nProcess exited with code ${code}`);
        terminalRef.current.write('$ ');
      }
    };

    terminalService.on('output', handleOutput);
    terminalService.on('session-cleared', handleSessionCleared);
    terminalService.on('exit', handleExit);

    return () => {
      terminalService.off('output', handleOutput);
      terminalService.off('session-cleared', handleSessionCleared);
      terminalService.off('exit', handleExit);
    };
  }, [session.id]);

  // Write existing output when component mounts
  useEffect(() => {
    if (terminalRef.current && session.output.length > 0) {
      session.output.forEach((line: string) => {
        terminalRef.current!.write(line);
      });
    }
  }, [session.output]);

  // Handle terminal data (user input)
  const handleData = useCallback((data: string) => {
    const term = terminalRef.current?.getTerminal();
    if (!term) return;

    // Handle special keys
    switch (data) {
      case '\r': // Enter
        if (commandBuffer.current.trim()) {
          terminalRef.current!.writeln('');
          
          // Execute command through WebSocket
          terminalService.executeCommand({
            sessionId: session.id,
            command: commandBuffer.current.trim(),
            cwd: session.cwd
          }).catch(error => {
            terminalRef.current!.writeln(`Error: ${error.message}`);
            terminalRef.current!.write('$ ');
          });
          
          commandBuffer.current = '';
          cursorPosition.current = 0;
        } else {
          terminalRef.current!.writeln('');
          terminalRef.current!.write('$ ');
        }
        break;

      case '\x7F': // Backspace
        if (cursorPosition.current > 0) {
          // Move cursor back, write space, move cursor back again
          terminalRef.current!.write('\b \b');
          commandBuffer.current = 
            commandBuffer.current.slice(0, cursorPosition.current - 1) + 
            commandBuffer.current.slice(cursorPosition.current);
          cursorPosition.current--;
        }
        break;

      case '\x1B[D': // Left arrow
        if (cursorPosition.current > 0) {
          terminalRef.current!.write(data);
          cursorPosition.current--;
        }
        break;

      case '\x1B[C': // Right arrow
        if (cursorPosition.current < commandBuffer.current.length) {
          terminalRef.current!.write(data);
          cursorPosition.current++;
        }
        break;

      case '\x03': // Ctrl+C
        terminalRef.current!.writeln('^C');
        commandBuffer.current = '';
        cursorPosition.current = 0;
        terminalRef.current!.write('$ ');
        break;

      case '\x0C': // Ctrl+L (clear)
        terminalRef.current!.clear();
        terminalRef.current!.write('$ ');
        terminalRef.current!.write(commandBuffer.current);
        break;

      default:
        // Regular character input
        if (data.length === 1 && data.charCodeAt(0) >= 32) {
          terminalRef.current!.write(data);
          commandBuffer.current = 
            commandBuffer.current.slice(0, cursorPosition.current) + 
            data + 
            commandBuffer.current.slice(cursorPosition.current);
          cursorPosition.current++;
        }
    }
  }, [session.id, session.cwd]);

  // Handle terminal resize
  const handleResize = useCallback((cols: number, rows: number) => {
    // Could send resize info to backend if needed
    // eslint-disable-next-line no-console
    console.log(`Terminal ${session.id} resized to ${cols}x${rows}`);
  }, [session.id]);

  return (
    <TerminalWithRef
      ref={terminalRef}
      id={session.id}
      theme={theme}
      onData={handleData}
      onResize={handleResize}
      onTitleChange={onTitleChange}
      className="h-full"
    />
  );
}