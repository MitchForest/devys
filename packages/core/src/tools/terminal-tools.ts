import { z } from 'zod';
import type { ToolDefinition } from '@claude-code-ide/types';
import { spawn } from 'child_process';

export function createTerminalTools(): Record<string, ToolDefinition> {
  return {
    runCommand: {
      name: 'runCommand',
      description: 'Execute a shell command',
      parameters: {
        command: z.string().describe('The command to execute'),
        cwd: z.string().optional().describe('Working directory for the command'),
        timeout: z.number().optional().describe('Command timeout in milliseconds')
      },
      execute: async ({ command, cwd, timeout = 30000 }: { 
        command: string; 
        cwd?: string; 
        timeout?: number 
      }) => {
        return new Promise((resolve) => {
          const [cmd, ...args] = command.split(' ');
          const child = spawn(cmd, args, {
            cwd: cwd || process.cwd(),
            shell: true
          });

          let stdout = '';
          let stderr = '';
          let timedOut = false;

          const timer = setTimeout(() => {
            timedOut = true;
            child.kill();
          }, timeout);

          child.stdout.on('data', (data) => {
            stdout += data.toString();
          });

          child.stderr.on('data', (data) => {
            stderr += data.toString();
          });

          child.on('close', (code) => {
            clearTimeout(timer);
            
            if (timedOut) {
              resolve({
                success: false,
                error: 'Command timed out',
                stdout,
                stderr
              });
            } else if (code !== 0) {
              resolve({
                success: false,
                error: `Command exited with code ${code}`,
                stdout,
                stderr,
                exitCode: code
              });
            } else {
              resolve({
                success: true,
                stdout,
                stderr,
                exitCode: code
              });
            }
          });

          child.on('error', (error) => {
            clearTimeout(timer);
            resolve({
              success: false,
              error: error.message,
              stdout,
              stderr
            });
          });
        });
      }
    },

    checkCommand: {
      name: 'checkCommand',
      description: 'Check if a command is available in the system',
      parameters: {
        command: z.string().describe('The command to check')
      },
      execute: async ({ command }: { command: string }) => {
        return new Promise((resolve) => {
          const child = spawn('which', [command], { shell: true });
          
          child.on('close', (code) => {
            resolve({
              success: true,
              available: code === 0,
              command
            });
          });

          child.on('error', () => {
            resolve({
              success: true,
              available: false,
              command
            });
          });
        });
      }
    }
  };
}