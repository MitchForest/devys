#!/usr/bin/env node

// Debug the provider directly

import { ClaudeCodeProvider } from './packages/core/dist/index.js';

// Load environment variables from .env file
import dotenv from 'dotenv';
dotenv.config();

async function testProvider() {
  console.log('Testing provider directly...\n');
  
  const provider = new ClaudeCodeProvider({
    apiKey: process.env.ANTHROPIC_API_KEY
  });
  
  const model = provider.languageModel('sonnet');
  
  // Test doStream directly
  const options = {
    prompt: [
      { role: 'user', content: 'Hello, please respond with a greeting' }
    ],
    mode: { type: 'regular' },
    inputFormat: 'messages',
    stopSequences: [],
    maxTokens: 100,
    temperature: 0.7,
    headers: {},
  };
  
  console.log('Calling doStream...');
  const result = await model.doStream(options);
  
  console.log('Got result, reading stream...');
  const reader = result.stream.getReader();
  
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      console.log('Stream part:', value);
    }
  } catch (error) {
    console.error('Stream error:', error);
  }
}

testProvider().catch(console.error);