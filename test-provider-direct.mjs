#!/usr/bin/env node

// Test our Claude Code provider directly

import { createClaudeCode } from './packages/core/dist/index.js';
import { streamText } from 'ai';

// Load environment variables from .env file
import dotenv from 'dotenv';
dotenv.config();

async function testProvider() {
  console.log('Testing Claude Code provider directly...\n');
  
  try {
    // Create provider
    const provider = createClaudeCode({
      apiKey: process.env.ANTHROPIC_API_KEY,
      cwd: process.cwd()
    });
    
    // Get language model
    const model = provider.languageModel('sonnet');
    
    // Test with streamText
    const result = await streamText({
      model,
      messages: [
        { role: 'user', content: 'Hello! Please respond with a simple greeting.' }
      ]
    });
    
    console.log('Streaming response:');
    
    let responseText = '';
    for await (const chunk of result.textStream) {
      responseText += chunk;
      process.stdout.write(chunk);
    }
    
    console.log('\n\nFull response:', responseText);
    
  } catch (error) {
    console.error('Error:', error);
    console.error('Stack:', error.stack);
  }
}

testProvider();