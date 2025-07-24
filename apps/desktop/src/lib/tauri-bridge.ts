import { invoke } from '@tauri-apps/api/core';
import { readTextFile, writeTextFile, readDir, create, remove, rename } from '@tauri-apps/plugin-fs';

export const tauriBridge = {
  // File operations
  async readFile(path: string): Promise<string> {
    return await readTextFile(path);
  },

  async writeFile(path: string, content: string): Promise<void> {
    await writeTextFile(path, content);
  },

  async listFiles(path: string): Promise<any[]> {
    return await readDir(path);
  },

  async createDirectory(path: string): Promise<void> {
    await create(path);
  },

  async deleteFile(path: string): Promise<void> {
    await remove(path);
  },

  async deleteDirectory(path: string): Promise<void> {
    await remove(path);
  },

  async renameFile(oldPath: string, newPath: string): Promise<void> {
    await rename(oldPath, newPath);
  },

  // Dialog operations - TODO: Implement when dialog plugin is added
  async openFileDialog(): Promise<string | null> {
    // TODO: Add @tauri-apps/plugin-dialog when needed
    return null;
  },

  async openFolderDialog(): Promise<string | null> {
    // TODO: Add @tauri-apps/plugin-dialog when needed
    return null;
  },

  async saveFileDialog(defaultPath?: string): Promise<string | null> {
    // TODO: Add @tauri-apps/plugin-dialog when needed
    return null;
  },

  // Custom commands (to be implemented in Rust)
  async getProjectInfo(): Promise<any> {
    return await invoke('get_project_info');
  },

  async runCommand(command: string, args: string[]): Promise<string> {
    return await invoke('run_command', { command, args });
  }
};