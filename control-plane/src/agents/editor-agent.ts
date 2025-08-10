import { BaseAgent } from './base-agent';
import { 
  AgentCapabilities, 
  AgentContext, 
  AgentResult,
  EditTask,
  EditResult,
  FileOperation,
  Diff
} from '../types/agents';
import { Database } from 'bun:sqlite';
import { $ } from 'bun';

export class EditorAgent extends BaseAgent {
  constructor(workspace: string, db: Database) {
    super('editor', workspace, db);
  }
  
  defineCapabilities(): AgentCapabilities {
    return {
      maxTokens: 4000,
      preferredModel: 'claude-3-sonnet',
      fallbackModels: ['gpt-4', 'claude-3-haiku'],
      temperature: 0.1,
      systemPromptTemplate: 'editor-system-v1',
      tools: ['file_read', 'file_write', 'symbol_lookup']
    };
  }
  
  validateInput(context: AgentContext): boolean {
    // Must have an EditTask as the task
    if (!context.task || typeof context.task !== 'object') {
      return false;
    }
    
    const editTask = context.task as EditTask;
    
    // Must have file operations
    if (!editTask.fileOperations || editTask.fileOperations.length === 0) {
      return false;
    }
    
    return true;
  }
  
  async formatContext(context: AgentContext): Promise<any> {
    const editTask = context.task as EditTask;
    
    // Get only relevant files for this edit
    const targetContext = await this.contextGenerator.generateContext({
      files: editTask.context.targetFiles,
      maxTokens: 3000,
      includeFileMap: false,
      includeCodeMap: true,
      includeContent: true // Need full content for editing
    });
    
    return {
      step: editTask.stepId,
      operations: editTask.fileOperations,
      files: targetContext.selectedFiles,
      symbols: editTask.context.relevantSymbols || [],
      codeMap: targetContext.codeMap,
      examples: editTask.context.examples || []
    };
  }
  
  async execute(context: AgentContext): Promise<AgentResult> {
    const startTime = Date.now();
    const editTask = context.task as EditTask;
    const results: EditResult[] = [];
    
    try {
      // Group operations by file for efficiency
      const operationsByFile = this.groupOperationsByFile(editTask.fileOperations);
      
      // Execute edits in parallel when possible
      const parallelGroups = this.identifyParallelEdits(operationsByFile);
      
      for (const group of parallelGroups) {
        const groupResults = await Promise.all(
          group.map(fileOps => this.executeFileOperations(fileOps, context))
        );
        results.push(...groupResults);
      }
      
      // Merge results
      const merged = this.mergeEditResults(results);
      
      return {
        success: merged.errors.length === 0,
        output: merged,
        tokensUsed: results.reduce((sum, r) => sum + (r.tokensUsed || 0), 0),
        modelUsed: this.capabilities.preferredModel,
        duration: Date.now() - startTime,
        errors: merged.errors,
        nextSteps: merged.errors.length === 0 ? ['review'] : ['fix_errors']
      };
      
    } catch (error) {
      return {
        success: false,
        output: null,
        tokensUsed: 0,
        modelUsed: this.capabilities.preferredModel,
        duration: Date.now() - startTime,
        errors: [error.message]
      };
    }
  }
  
  processResult(rawResult: any): AgentResult {
    // This is handled in execute() for EditorAgent
    // since we need to process multiple sub-results
    return rawResult;
  }
  
  private groupOperationsByFile(operations: FileOperation[]): Map<string, FileOperation[]> {
    const grouped = new Map<string, FileOperation[]>();
    
    for (const op of operations) {
      const existing = grouped.get(op.path) || [];
      existing.push(op);
      grouped.set(op.path, existing);
    }
    
    return grouped;
  }
  
  private identifyParallelEdits(
    operationsByFile: Map<string, FileOperation[]>
  ): Array<Array<[string, FileOperation[]]>> {
    // For now, simple implementation - each file is independent
    // In the future, we could analyze dependencies between files
    const groups: Array<Array<[string, FileOperation[]]>> = [];
    
    // Batch files into groups of 4 for parallel processing
    const files = Array.from(operationsByFile.entries());
    const batchSize = 4;
    
    for (let i = 0; i < files.length; i += batchSize) {
      groups.push(files.slice(i, i + batchSize));
    }
    
    return groups;
  }
  
  private async executeFileOperations(
    fileOps: [string, FileOperation[]],
    context: AgentContext
  ): Promise<EditResult> {
    const [filePath, operations] = fileOps;
    const result: EditResult = {
      filesModified: [],
      filesCreated: [],
      filesDeleted: [],
      diffs: [],
      errors: [],
      tokensUsed: 0
    };
    
    try {
      // Determine the primary operation type
      const primaryOp = operations[0];
      
      switch (primaryOp.type) {
        case 'create':
          await this.handleCreateFile(filePath, operations, context, result);
          break;
          
        case 'edit':
          await this.handleEditFile(filePath, operations, context, result);
          break;
          
        case 'delete':
          await this.handleDeleteFile(filePath, result);
          break;
          
        case 'move':
          await this.handleMoveFile(filePath, operations, result);
          break;
      }
      
    } catch (error) {
      result.errors.push(`Error processing ${filePath}: ${error.message}`);
    }
    
    return result;
  }
  
  private async handleCreateFile(
    filePath: string,
    operations: FileOperation[],
    context: AgentContext,
    result: EditResult
  ): Promise<void> {
    // Check if file already exists
    const fullPath = `${this.workspace}/${filePath}`;
    const file = Bun.file(fullPath);
    
    if (await file.exists()) {
      result.errors.push(`File ${filePath} already exists`);
      return;
    }
    
    // Generate file content using AI
    const content = await this.generateFileContent(filePath, operations, context);
    
    // Create directory if needed
    const dir = fullPath.substring(0, fullPath.lastIndexOf('/'));
    await $`mkdir -p ${dir}`.quiet();
    
    // Write file
    await Bun.write(fullPath, content);
    
    result.filesCreated.push(filePath);
    result.diffs.push({
      file: filePath,
      lineStart: 1,
      lineEnd: content.split('\n').length,
      content
    });
  }
  
  private async handleEditFile(
    filePath: string,
    operations: FileOperation[],
    context: AgentContext,
    result: EditResult
  ): Promise<void> {
    const fullPath = `${this.workspace}/${filePath}`;
    const file = Bun.file(fullPath);
    
    if (!await file.exists()) {
      result.errors.push(`File ${filePath} does not exist`);
      return;
    }
    
    // Read current content
    const originalContent = await file.text();
    
    // Generate edited content using AI
    const editedContent = await this.generateEditedContent(
      filePath,
      originalContent,
      operations,
      context
    );
    
    // Write updated content
    await Bun.write(fullPath, editedContent);
    
    result.filesModified.push(filePath);
    
    // Generate diff (simplified - in production would use proper diff library)
    result.diffs.push({
      file: filePath,
      lineStart: 1,
      lineEnd: editedContent.split('\n').length,
      content: editedContent
    });
  }
  
  private async handleDeleteFile(
    filePath: string,
    result: EditResult
  ): Promise<void> {
    const fullPath = `${this.workspace}/${filePath}`;
    const file = Bun.file(fullPath);
    
    if (!await file.exists()) {
      result.errors.push(`File ${filePath} does not exist`);
      return;
    }
    
    // Delete file
    await $`rm ${fullPath}`.quiet();
    
    result.filesDeleted.push(filePath);
  }
  
  private async handleMoveFile(
    filePath: string,
    operations: FileOperation[],
    result: EditResult
  ): Promise<void> {
    // Find the target path from operations
    const moveOp = operations.find(op => op.type === 'move');
    if (!moveOp || !moveOp.description.includes('to')) {
      result.errors.push(`Move operation for ${filePath} missing target path`);
      return;
    }
    
    // Extract target path from description (format: "Move to path/to/new/file.ts")
    const targetMatch = moveOp.description.match(/to\s+(\S+)/);
    if (!targetMatch) {
      result.errors.push(`Invalid move operation description for ${filePath}`);
      return;
    }
    
    const targetPath = targetMatch[1];
    const sourceFull = `${this.workspace}/${filePath}`;
    const targetFull = `${this.workspace}/${targetPath}`;
    
    // Create target directory if needed
    const targetDir = targetFull.substring(0, targetFull.lastIndexOf('/'));
    await $`mkdir -p ${targetDir}`.quiet();
    
    // Move file
    await $`mv ${sourceFull} ${targetFull}`.quiet();
    
    result.filesDeleted.push(filePath);
    result.filesCreated.push(targetPath);
  }
  
  private async generateFileContent(
    filePath: string,
    operations: FileOperation[],
    context: AgentContext
  ): Promise<string> {
    // Build prompt for file generation
    const prompt = await this.promptManager.buildPrompt('editor-create-v1', {
      filePath,
      operations: operations.map(op => op.description).join('\n'),
      context: context.task
    });
    
    // Call model to generate content
    const response = await this.modelRouter.route({
      prompt,
      preferredModel: this.capabilities.preferredModel,
      fallbackModels: this.capabilities.fallbackModels,
      maxTokens: 2000,
      temperature: 0.1,
      complexity: 'moderate'
    });
    
    return response.content;
  }
  
  private async generateEditedContent(
    filePath: string,
    originalContent: string,
    operations: FileOperation[],
    context: AgentContext
  ): Promise<string> {
    // Build prompt for file editing
    const prompt = await this.promptManager.buildPrompt('editor-edit-v1', {
      filePath,
      originalContent,
      operations: operations.map(op => op.description).join('\n'),
      context: context.task
    });
    
    // Call model to generate edited content
    const response = await this.modelRouter.route({
      prompt,
      preferredModel: this.capabilities.preferredModel,
      fallbackModels: this.capabilities.fallbackModels,
      maxTokens: 3000,
      temperature: 0.1,
      complexity: 'moderate'
    });
    
    return response.content;
  }
  
  private mergeEditResults(results: EditResult[]): EditResult {
    const merged: EditResult = {
      filesModified: [],
      filesCreated: [],
      filesDeleted: [],
      diffs: [],
      errors: [],
      tokensUsed: 0
    };
    
    for (const result of results) {
      merged.filesModified.push(...result.filesModified);
      merged.filesCreated.push(...result.filesCreated);
      merged.filesDeleted.push(...result.filesDeleted);
      merged.diffs.push(...result.diffs);
      merged.errors.push(...result.errors);
      merged.tokensUsed += result.tokensUsed || 0;
    }
    
    // Remove duplicates
    merged.filesModified = [...new Set(merged.filesModified)];
    merged.filesCreated = [...new Set(merged.filesCreated)];
    merged.filesDeleted = [...new Set(merged.filesDeleted)];
    
    return merged;
  }
}