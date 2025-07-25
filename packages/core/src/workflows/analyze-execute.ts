import type { WorkflowConfig } from '@devys/types';

export const analyzeExecuteWorkflow: WorkflowConfig = {
  version: '1.0',
  name: 'analyze-execute',
  description: 'Analyze codebase and execute changes',
  steps: [
    {
      id: 'analyze',
      type: 'ai-query',
      config: {
        systemPrompt: `You are an expert code analyst. Your task is to:
1. Analyze the user's request thoroughly
2. Examine the codebase structure and existing patterns
3. Identify all files that need to be modified
4. Consider potential impacts and dependencies
5. Create a detailed analysis of what needs to be done

Focus on understanding:
- The user's intent and requirements
- Existing code patterns and conventions
- Dependencies and potential breaking changes
- Best practices for the technology stack

Output a comprehensive analysis with:
- Summary of the request
- List of files to be modified
- Key implementation considerations
- Potential risks or challenges`,
        tools: [
          'Read',
          'Grep',
          'Glob',
          'LS',
          'WebFetch',
          'WebSearch'
        ],
        maxTurns: 10
      }
    },
    {
      id: 'plan',
      type: 'ai-query',
      depends_on: ['analyze'],
      config: {
        systemPrompt: `Based on the analysis from the previous step, create a detailed implementation plan.

Your plan should include:
1. Step-by-step implementation approach
2. Specific changes to be made in each file
3. Order of operations to avoid breaking the build
4. Testing approach to verify changes
5. Rollback strategy if needed

Be specific about:
- Exact code changes with examples
- New files to be created
- Dependencies to be added
- Configuration changes required

Format your plan clearly with sections and bullet points.`,
        tools: [
          'Read',
          'TodoWrite'
        ],
        maxTurns: 3
      }
    },
    {
      id: 'execute',
      type: 'ai-query',
      depends_on: ['plan'],
      config: {
        systemPrompt: `Execute the implementation plan from the previous step.

Guidelines:
1. Follow the plan exactly as specified
2. Make changes incrementally and test as you go
3. Use existing patterns and conventions in the codebase
4. Ensure code quality and proper error handling
5. Add appropriate comments and documentation

Important:
- Test your changes after each major modification
- Run linting and type checking if available
- Commit changes with clear messages
- Report any deviations from the plan`,
        tools: [
          'Read',
          'Write',
          'Edit',
          'MultiEdit',
          'Bash',
          'TodoWrite'
        ],
        requiresApproval: true,
        maxTurns: 20
      }
    },
    {
      id: 'verify',
      type: 'ai-query',
      depends_on: ['execute'],
      config: {
        systemPrompt: `Verify that the implementation is complete and working correctly.

Verification steps:
1. Check that all planned changes were implemented
2. Run any available tests
3. Verify the build is not broken
4. Test the functionality manually if possible
5. Check for any regressions

Report:
- Summary of changes made
- Test results
- Any issues encountered
- Suggestions for improvement
- Next steps if any`,
        tools: [
          'Read',
          'Bash',
          'Grep'
        ],
        maxTurns: 5
      }
    }
  ]
};