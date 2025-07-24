import { z } from 'zod';
import type { FileNode } from '../types';

export const FileNodeSchema: z.ZodType<FileNode> = z.object({
  id: z.string(),
  name: z.string(),
  path: z.string(),
  type: z.enum(['file', 'directory']),
  children: z.lazy(() => z.array(FileNodeSchema)).optional(),
  isExpanded: z.boolean().optional(),
  gitStatus: z.enum(['modified', 'added', 'deleted', 'renamed', 'untracked']).optional(),
});

export const ChatMessageSchema = z.object({
  id: z.string(),
  role: z.enum(['user', 'assistant', 'system']),
  content: z.string(),
  timestamp: z.date(),
  attachments: z
    .array(
      z.object({
        path: z.string(),
        name: z.string(),
        content: z.string().optional(),
      })
    )
    .optional(),
});

export const WorkflowConfigSchema = z.object({
  version: z.string(),
  name: z.string(),
  description: z.string(),
  steps: z.array(
    z.object({
      id: z.string(),
      type: z.enum(['ai-query', 'command', 'approval']),
      config: z.record(z.unknown()),
    })
  ),
});

export const QueryOptionsSchema = z.object({
  maxTurns: z.number().optional(),
  temperature: z.number().optional(),
  tools: z.array(z.string()).optional(),
  systemPrompt: z.string().optional(),
});