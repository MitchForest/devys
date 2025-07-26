import { Hono } from 'hono';
import { z } from 'zod';
// FileNodeSchema import removed - not used
import * as fs from 'fs/promises';
import * as path from 'path';
import { zValidator } from '@hono/zod-validator';

const filesRoute = new Hono();

// Schema for file operations
const CreateFileSchema = z.object({
  path: z.string(),
  content: z.string().optional(),
  isDirectory: z.boolean().optional()
});

const RenameFileSchema = z.object({
  oldPath: z.string(),
  newPath: z.string()
});

const WriteFileSchema = z.object({
  path: z.string(),
  content: z.string()
});

// Helper to get git status for a file (placeholder for now)
async function getGitStatus(_filePath: string): Promise<'modified' | 'added' | 'deleted' | 'renamed' | 'untracked' | undefined> {
  // TODO: Implement actual git status checking
  return undefined;
}

// Helper to build file node structure
async function buildFileNode(filePath: string, basePath: string, showHidden: boolean = true): Promise<{
  id: string;
  name: string;
  path: string;
  type: 'file' | 'directory';
  children?: Array<{
    id: string;
    name: string;
    path: string;
    type: 'file' | 'directory';
    children?: unknown[];
    gitStatus?: 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked';
  }>;
  gitStatus?: 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked';
}> {
  const stats = await fs.stat(filePath);
  const relativePath = path.relative(basePath, filePath);
  const name = path.basename(filePath);
  
  if (stats.isDirectory()) {
    const children = [];
    const entries = await fs.readdir(filePath);
    
    // Filter out common directories to ignore
    const filtered = entries.filter(entry => {
      // Skip system files
      if (entry === '.DS_Store' || entry === 'Thumbs.db') return false;
      
      // Apply filters based on showHidden parameter
      if (!showHidden) {
        // Hide dot files and common build directories
        return !entry.startsWith('.') && 
               entry !== 'node_modules' && 
               entry !== 'dist' &&
               entry !== 'build' &&
               entry !== 'target' &&
               entry !== 'coverage' &&
               entry !== 'bun.lockb' &&
               !entry.endsWith('.log');
      }
      
      // When showing hidden files, show everything except git objects
      return entry !== '.git/objects';
    });
    
    for (const entry of filtered) {
      const childPath = path.join(filePath, entry);
      try {
        const childNode = await buildFileNode(childPath, basePath, showHidden);
        children.push(childNode);
      } catch (error) {
        // Skip files we can't read
      }
    }
    
    return {
      id: filePath,
      name,
      path: '/' + relativePath.replace(/\\/g, '/'),
      type: 'directory',
      children: children.sort((a, b) => {
        // Directories first, then files
        if (a.type === b.type) return a.name.localeCompare(b.name);
        return a.type === 'directory' ? -1 : 1;
      }),
      gitStatus: await getGitStatus(filePath)
    };
  } else {
    return {
      id: filePath,
      name,
      path: '/' + relativePath.replace(/\\/g, '/'),
      type: 'file',
      gitStatus: await getGitStatus(filePath)
    };
  }
}

// List files in a directory
filesRoute.get('/list', async (c) => {
  const projectPath = c.req.query('path') || process.cwd();
  const showHidden = c.req.query('showHidden') === 'true';
  
  try {
    const stats = await fs.stat(projectPath);
    if (!stats.isDirectory()) {
      return c.json({ error: 'Path is not a directory' }, 400);
    }
    
    const entries = await fs.readdir(projectPath);
    const nodes = [];
    
    for (const entry of entries) {
      // Skip system files
      if (entry === '.DS_Store' || entry === 'Thumbs.db') continue;
      
      // Apply filters based on showHidden parameter
      if (!showHidden) {
        if (entry.startsWith('.') || 
            entry === 'node_modules' || 
            entry === 'dist' || 
            entry === 'build' || 
            entry === 'target' || 
            entry === 'coverage' ||
            entry === 'bun.lockb' ||
            entry.endsWith('.log')) continue;
      } else {
        // When showing hidden files, only skip git objects
        if (entry === '.git/objects') continue;
      }
      
      const fullPath = path.join(projectPath, entry);
      try {
        const node = await buildFileNode(fullPath, projectPath, showHidden);
        nodes.push(node);
      } catch (error) {
        // Skip files we can't read
      }
    }
    
    return c.json({
      nodes: nodes.sort((a, b) => {
        if (a.type === b.type) return a.name.localeCompare(b.name);
        return a.type === 'directory' ? -1 : 1;
      })
    });
  } catch (error) {
    return c.json({ error: 'Failed to list directory' }, 500);
  }
});

// Read file content
filesRoute.get('/read', async (c) => {
  const filePath = c.req.query('path');
  
  if (!filePath) {
    return c.json({ error: 'Path is required' }, 400);
  }
  
  try {
    const content = await fs.readFile(filePath, 'utf-8');
    return c.json({ content });
  } catch (error) {
    return c.json({ error: 'Failed to read file' }, 500);
  }
});

// Create file or directory
filesRoute.post('/create', zValidator('json', CreateFileSchema), async (c) => {
  const { path: filePath, content, isDirectory } = c.req.valid('json');
  
  try {
    if (isDirectory) {
      await fs.mkdir(filePath, { recursive: true });
    } else {
      // Ensure parent directory exists
      const dir = path.dirname(filePath);
      await fs.mkdir(dir, { recursive: true });
      await fs.writeFile(filePath, content || '');
    }
    
    return c.json({ success: true });
  } catch (error) {
    return c.json({ error: 'Failed to create file/directory' }, 500);
  }
});

// Write/update file content
filesRoute.post('/write', zValidator('json', WriteFileSchema), async (c) => {
  const { path: filePath, content } = c.req.valid('json');
  
  try {
    await fs.writeFile(filePath, content);
    return c.json({ success: true });
  } catch (error) {
    return c.json({ error: 'Failed to write file' }, 500);
  }
});

// Rename file or directory
filesRoute.post('/rename', zValidator('json', RenameFileSchema), async (c) => {
  const { oldPath, newPath } = c.req.valid('json');
  
  try {
    await fs.rename(oldPath, newPath);
    return c.json({ success: true });
  } catch (error) {
    return c.json({ error: 'Failed to rename file' }, 500);
  }
});

// Delete file or directory
filesRoute.delete('/delete', async (c) => {
  const filePath = c.req.query('path');
  
  if (!filePath) {
    return c.json({ error: 'Path is required' }, 400);
  }
  
  try {
    const stats = await fs.stat(filePath);
    if (stats.isDirectory()) {
      await fs.rmdir(filePath, { recursive: true });
    } else {
      await fs.unlink(filePath);
    }
    
    return c.json({ success: true });
  } catch (error) {
    return c.json({ error: 'Failed to delete file' }, 500);
  }
});

export default filesRoute;