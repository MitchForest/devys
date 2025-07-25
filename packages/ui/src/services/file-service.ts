import type { FileAttachment, FileNode } from '@devys/types';

export class FileService {
  private apiEndpoint: string;

  constructor(apiEndpoint = 'http://localhost:3001/api/files') {
    this.apiEndpoint = apiEndpoint;
  }

  async readFile(path: string): Promise<string> {
    const response = await fetch(`${this.apiEndpoint}/read?path=${encodeURIComponent(path)}`);
    
    if (!response.ok) {
      throw new Error(`Failed to read file: ${response.statusText}`);
    }
    
    const data = await response.json();
    return data.content;
  }

  async readFileAttachment(file: FileAttachment): Promise<FileAttachment> {
    if (file.content) {
      // Already has content
      return file;
    }

    try {
      const content = await this.readFile(file.path);
      return {
        ...file,
        content,
        language: this.detectLanguage(file.name)
      };
    } catch (error) {
      console.error(`Failed to read file ${file.path}:`, error);
      return {
        ...file,
        content: `[Error reading file: ${error instanceof Error ? error.message : 'Unknown error'}]`
      };
    }
  }

  async readMultipleAttachments(files: FileAttachment[]): Promise<FileAttachment[]> {
    return Promise.all(files.map(file => this.readFileAttachment(file)));
  }

  private detectLanguage(filename: string): string {
    const ext = filename.split('.').pop()?.toLowerCase() || '';
    
    const languageMap: Record<string, string> = {
      ts: 'typescript',
      tsx: 'typescriptreact',
      js: 'javascript',
      jsx: 'javascriptreact',
      py: 'python',
      java: 'java',
      cpp: 'cpp',
      c: 'c',
      cs: 'csharp',
      go: 'go',
      rs: 'rust',
      rb: 'ruby',
      php: 'php',
      swift: 'swift',
      kt: 'kotlin',
      scala: 'scala',
      r: 'r',
      m: 'matlab',
      sql: 'sql',
      sh: 'bash',
      bash: 'bash',
      zsh: 'bash',
      fish: 'bash',
      ps1: 'powershell',
      yml: 'yaml',
      yaml: 'yaml',
      json: 'json',
      xml: 'xml',
      html: 'html',
      css: 'css',
      scss: 'scss',
      sass: 'sass',
      less: 'less',
      md: 'markdown',
      tex: 'latex',
      dockerfile: 'dockerfile',
      makefile: 'makefile',
      cmake: 'cmake',
      gradle: 'gradle',
      toml: 'toml',
      ini: 'ini',
      cfg: 'ini',
      conf: 'ini',
      properties: 'properties',
      env: 'dotenv'
    };

    return languageMap[ext] || 'plaintext';
  }

  async listFiles(dirPath: string): Promise<FileNode[]> {
    const response = await fetch(`${this.apiEndpoint}/list?path=${encodeURIComponent(dirPath)}`);
    
    if (!response.ok) {
      throw new Error(`Failed to list files: ${response.statusText}`);
    }
    
    const data = await response.json();
    return data.nodes || [];
  }
}

// Export singleton instance
export const fileService = new FileService();