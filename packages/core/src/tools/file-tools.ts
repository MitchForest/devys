import { z } from 'zod';
import type { ToolDefinition } from '@claude-code-ide/types';
import { FileSystemService } from '../services/file-system.service';

export function createFileTools(fileSystemService: FileSystemService): Record<string, ToolDefinition> {
  return {
    readFile: {
      name: 'readFile',
      description: 'Read the contents of a file',
      parameters: {
        path: z.string().describe('The file path to read')
      },
      execute: async (args: unknown) => {
        const { path } = args as { path: string };
        try {
          const content = await fileSystemService.readFile(path);
          return {
            success: true,
            content
          };
        } catch (error) {
          return {
            success: false,
            error: error instanceof Error ? error.message : 'Failed to read file'
          };
        }
      }
    },

    writeFile: {
      name: 'writeFile',
      description: 'Write content to a file',
      parameters: {
        path: z.string().describe('The file path to write to'),
        content: z.string().describe('The content to write')
      },
      execute: async (args: unknown) => {
        const { path, content } = args as { path: string; content: string };
        try {
          await fileSystemService.writeFile(path, content);
          return {
            success: true,
            message: `File written successfully: ${path}`
          };
        } catch (error) {
          return {
            success: false,
            error: error instanceof Error ? error.message : 'Failed to write file'
          };
        }
      }
    },

    createFile: {
      name: 'createFile',
      description: 'Create a new file',
      parameters: {
        path: z.string().describe('The file path to create'),
        content: z.string().optional().describe('Initial content for the file')
      },
      execute: async (args: unknown) => {
        const { path, content } = args as { path: string; content?: string };
        try {
          await fileSystemService.createFile(path, content);
          return {
            success: true,
            message: `File created successfully: ${path}`
          };
        } catch (error) {
          return {
            success: false,
            error: error instanceof Error ? error.message : 'Failed to create file'
          };
        }
      }
    },

    listFiles: {
      name: 'listFiles',
      description: 'List files in a directory',
      parameters: {
        path: z.string().optional().describe('The directory path to list (defaults to project root)')
      },
      execute: async (args: unknown) => {
        const { path } = args as { path?: string };
        try {
          const files = await fileSystemService.listFiles(path);
          return {
            success: true,
            files
          };
        } catch (error) {
          return {
            success: false,
            error: error instanceof Error ? error.message : 'Failed to list files'
          };
        }
      }
    },

    deleteFile: {
      name: 'deleteFile',
      description: 'Delete a file or directory',
      parameters: {
        path: z.string().describe('The file or directory path to delete')
      },
      execute: async (args: unknown) => {
        const { path } = args as { path: string };
        try {
          await fileSystemService.deleteFile(path);
          return {
            success: true,
            message: `File deleted successfully: ${path}`
          };
        } catch (error) {
          return {
            success: false,
            error: error instanceof Error ? error.message : 'Failed to delete file'
          };
        }
      }
    },

    renameFile: {
      name: 'renameFile',
      description: 'Rename or move a file',
      parameters: {
        oldPath: z.string().describe('The current file path'),
        newPath: z.string().describe('The new file path')
      },
      execute: async (args: unknown) => {
        const { oldPath, newPath } = args as { oldPath: string; newPath: string };
        try {
          await fileSystemService.renameFile(oldPath, newPath);
          return {
            success: true,
            message: `File renamed successfully from ${oldPath} to ${newPath}`
          };
        } catch (error) {
          return {
            success: false,
            error: error instanceof Error ? error.message : 'Failed to rename file'
          };
        }
      }
    }
  };
}