import { invoke } from '@tauri-apps/api/core';
import { open, save } from '@tauri-apps/plugin-dialog';
import { readTextFile, writeTextFile, readDir, createDir, removeFile, removeDir, rename } from '@tauri-apps/plugin-fs';

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
    await createDir(path, { recursive: true });
  },

  async deleteFile(path: string): Promise<void> {
    await removeFile(path);
  },

  async deleteDirectory(path: string): Promise<void> {
    await removeDir(path, { recursive: true });
  },

  async renameFile(oldPath: string, newPath: string): Promise<void> {
    await rename(oldPath, newPath);
  },

  // Dialog operations
  async openFileDialog(): Promise<string | null> {
    const selected = await open({
      multiple: false,
      directory: false,
    });
    return selected as string | null;
  },

  async openFolderDialog(): Promise<string | null> {
    const selected = await open({
      multiple: false,
      directory: true,
    });
    return selected as string | null;
  },

  async saveFileDialog(defaultPath?: string): Promise<string | null> {
    return await save({
      defaultPath,
    });
  },

  // Custom commands (to be implemented in Rust)
  async getProjectInfo(): Promise<any> {
    return await invoke('get_project_info');
  },

  async runCommand(command: string, args: string[]): Promise<string> {
    return await invoke('run_command', { command, args });
  }
};