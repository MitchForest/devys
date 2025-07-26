import type { FileNode } from '@devys/types';

export interface FileSystemOptions {
  baseUrl: string;
  showHidden?: boolean;
}

export class FileSystemService {
  private baseUrl: string;
  private showHidden: boolean;

  constructor(options: FileSystemOptions) {
    this.baseUrl = options.baseUrl;
    this.showHidden = options.showHidden ?? true;
  }

  async listFiles(path?: string, showHidden?: boolean): Promise<FileNode[]> {
    const queryParams = new URLSearchParams();
    if (path) queryParams.append('path', path);
    queryParams.append('showHidden', String(showHidden ?? this.showHidden));
    
    const response = await fetch(`${this.baseUrl}/api/files/list?${queryParams}`);
    
    if (!response.ok) {
      throw new Error(`Failed to list files: ${response.statusText}`);
    }
    
    const data = await response.json();
    return data.nodes;
  }

  async readFile(path: string): Promise<string> {
    const response = await fetch(`${this.baseUrl}/api/files/read?path=${encodeURIComponent(path)}`);
    
    if (!response.ok) {
      throw new Error(`Failed to read file: ${response.statusText}`);
    }
    
    const data = await response.json();
    return data.content;
  }

  async createFile(path: string, content?: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/api/files/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path, content, isDirectory: false })
    });
    
    if (!response.ok) {
      throw new Error(`Failed to create file: ${response.statusText}`);
    }
  }

  async createFolder(path: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/api/files/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path, isDirectory: true })
    });
    
    if (!response.ok) {
      throw new Error(`Failed to create folder: ${response.statusText}`);
    }
  }

  async writeFile(path: string, content: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/api/files/write`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path, content })
    });
    
    if (!response.ok) {
      throw new Error(`Failed to write file: ${response.statusText}`);
    }
  }

  async renameFile(oldPath: string, newPath: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/api/files/rename`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ oldPath, newPath })
    });
    
    if (!response.ok) {
      throw new Error(`Failed to rename file: ${response.statusText}`);
    }
  }

  async deleteFile(path: string): Promise<void> {
    const response = await fetch(`${this.baseUrl}/api/files/delete?path=${encodeURIComponent(path)}`, {
      method: 'DELETE'
    });
    
    if (!response.ok) {
      throw new Error(`Failed to delete file: ${response.statusText}`);
    }
  }

  setShowHidden(showHidden: boolean): void {
    this.showHidden = showHidden;
  }

  async watchFile(path: string, ws: WebSocket): Promise<void> {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'file:watch', path }));
    }
  }

  async unwatchFile(path: string, ws: WebSocket): Promise<void> {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'file:unwatch', path }));
    }
  }
}