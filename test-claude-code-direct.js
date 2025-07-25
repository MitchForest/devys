#!/usr/bin/env node

// Test Claude Code SDK directly without our wrapper

import { query } from '@anthropic-ai/claude-code';

// Load environment variables from .env file
import dotenv from 'dotenv';
dotenv.config();

async function testClaudeCode() {
  console.log('Testing Claude Code SDK directly...\n');
  
  try {
    const response = query({
      prompt: 'Hello! Please respond with a simple greeting.',
      options: {
        model: 'sonnet',
        maxTurns: 1,
        cwd: process.cwd()
      }
    });
    
    console.log('Streaming response:');
    
    for await (const message of response) {
      console.log('\nMessage type:', message.type);
      
      if (message.type === 'assistant') {
        console.log('Assistant message:', JSON.stringify(message.message, null, 2));
      } else if (message.type === 'system') {
        console.log('System message:', {
          subtype: message.subtype,
          sessionId: message.session_id,
          model: message.model
        });
      } else if (message.type === 'result') {
        console.log('Result:', {
          subtype: message.subtype,
          isError: message.is_error,
          duration: message.duration_ms
        });
      }
    }
    
    console.log('\nTest completed successfully');
    
  } catch (error) {
    console.error('Error:', error);
    if (error.stack) {
      console.error('Stack:', error.stack);
    }
  }
}

testClaudeCode();