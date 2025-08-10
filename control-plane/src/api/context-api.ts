import { z } from 'zod';
import type { ContextGenerator } from '../services/context/context-generator';
import { ContextServer } from '../server';

// Validation schemas
const GenerateContextSchema = z.object({
  workspace: z.string().min(1),
  files: z.array(z.string()).optional(),
  folders: z.array(z.string()).optional(),
  patterns: z.array(z.string()).optional(),
  excludePatterns: z.array(z.string()).optional(),
  maxTokens: z.number().positive().optional(),
  useGitignore: z.boolean().optional(),
  useAiIgnore: z.boolean().optional(),
  maxFiles: z.number().positive().optional()
});

const InvalidateCacheSchema = z.object({
  workspace: z.string().min(1),
  files: z.array(z.string()).optional()
});

export class ContextAPI {
  constructor(private contextServer: ContextServer) {}
  
  async handleRequest(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace('/api/context/', '');
    
    try {
      switch (path) {
        case 'generate':
          if (req.method !== 'POST') {
            return new Response('Method not allowed', { status: 405 });
          }
          return await this.handleGenerateContext(req);
          
        case 'file-map':
          if (req.method !== 'GET') {
            return new Response('Method not allowed', { status: 405 });
          }
          return await this.handleGetFileMap(req);
          
        case 'code-map':
          if (req.method !== 'GET') {
            return new Response('Method not allowed', { status: 405 });
          }
          return await this.handleGetCodeMap(req);
          
        case 'invalidate':
          if (req.method !== 'POST') {
            return new Response('Method not allowed', { status: 405 });
          }
          return await this.handleInvalidateCache(req);
          
        case 'metrics':
          if (req.method !== 'GET') {
            return new Response('Method not allowed', { status: 405 });
          }
          return await this.handleGetMetrics(req);
          
        default:
          return new Response('Not found', { status: 404 });
      }
    } catch (error) {
      console.error('Context API error:', error);
      
      if (error instanceof z.ZodError) {
        return Response.json(
          { error: 'Validation error', details: error.errors },
          { status: 400 }
        );
      }
      
      return Response.json(
        { error: error instanceof Error ? error.message : 'Internal server error' },
        { status: 500 }
      );
    }
  }
  
  private async handleGenerateContext(req: Request): Promise<Response> {
    const body = await req.json();
    const validated = GenerateContextSchema.parse(body);
    
    // Get the generator for this workspace
    const generator = (this.contextServer as any).getGenerator(validated.workspace);
    
    // Generate context with options
    const context = await generator.generateContext({
      files: validated.files,
      folders: validated.folders,
      patterns: validated.patterns,
      excludePatterns: validated.excludePatterns,
      maxTokens: validated.maxTokens,
      useGitignore: validated.useGitignore ?? true,
      useAiIgnore: validated.useAiIgnore ?? true,
      maxFiles: validated.maxFiles
    });
    
    return Response.json(context, {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache'
      }
    });
  }
  
  private async handleGetFileMap(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const workspace = url.searchParams.get('workspace');
    
    if (!workspace) {
      return Response.json(
        { error: 'workspace parameter required' },
        { status: 400 }
      );
    }
    
    const generator = (this.contextServer as any).getGenerator(workspace);
    const context = await generator.generateContext({
      maxTokens: 10000 // Small limit for file map only
    });
    
    return Response.json(context.fileMap, {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'max-age=60'
      }
    });
  }
  
  private async handleGetCodeMap(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const workspace = url.searchParams.get('workspace');
    const files = url.searchParams.get('files')?.split(',');
    
    if (!workspace) {
      return Response.json(
        { error: 'workspace parameter required' },
        { status: 400 }
      );
    }
    
    const generator = (this.contextServer as any).getGenerator(workspace);
    const context = await generator.generateContext({
      files,
      maxTokens: 50000 // Reasonable limit for code map
    });
    
    return Response.json(context.codeMap, {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'max-age=60'
      }
    });
  }
  
  private async handleInvalidateCache(req: Request): Promise<Response> {
    const body = await req.json();
    const validated = InvalidateCacheSchema.parse(body);
    
    const generator = (this.contextServer as any).getGenerator(validated.workspace);
    
    if (validated.files && validated.files.length > 0) {
      // Invalidate specific files
      for (const file of validated.files) {
        await generator.cacheManager.invalidateFile(file);
      }
    } else {
      // Clear entire cache for workspace
      generator.clearCache();
    }
    
    return Response.json(
      { success: true, message: 'Cache invalidated' },
      { status: 200 }
    );
  }
  
  private async handleGetMetrics(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const workspace = url.searchParams.get('workspace');
    
    if (!workspace) {
      return Response.json(
        { error: 'workspace parameter required' },
        { status: 400 }
      );
    }
    
    const metrics = await this.contextServer.getMetrics(workspace);
    
    return Response.json(metrics, {
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache'
      }
    });
  }
}