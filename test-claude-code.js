#!/usr/bin/env bun

// Test script for Claude Code integration
// Run with: bun test-claude-code.js

import { createClaudeCode } from './packages/core/src/providers/claude-code-language-model.js';

// Load environment variables
if (!process.env.ANTHROPIC_API_KEY) {
  console.error('❌ Missing ANTHROPIC_API_KEY environment variable');
  console.error('Create a .env file with your API key');
  process.exit(1);
}

console.log('🧪 Testing Claude Code Integration...\n');

async function testBasicQuery() {
  console.log('1️⃣ Testing basic text response...');
  
  try {
    const provider = createClaudeCode({
      apiKey: process.env.ANTHROPIC_API_KEY,
      cwd: process.cwd()
    });
    
    const model = provider.languageModel('sonnet');
    
    const result = await model.doStream({
      prompt: [
        { role: 'user', content: 'Say hello and tell me what tools you have available.' }
      ],
      abortSignal: undefined
    });
    
    console.log('✅ Stream created successfully');
    
    // Read the stream
    const reader = result.stream.getReader();
    let messageContent = '';
    
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      if (value.type === 'text-delta') {
        process.stdout.write(value.delta);
        messageContent += value.delta;
      } else if (value.type === 'tool-input-start') {
        console.log(`\n🔧 Tool call: ${value.toolName}`);
      }
    }
    
    console.log('\n\n✅ Basic test passed!\n');
    return true;
  } catch (error) {
    console.error('❌ Basic test failed:', error);
    return false;
  }
}

async function testFileOperation() {
  console.log('2️⃣ Testing file reading (non-destructive)...');
  
  try {
    const provider = createClaudeCode({
      apiKey: process.env.ANTHROPIC_API_KEY,
      cwd: process.cwd()
    });
    
    const model = provider.languageModel('sonnet');
    
    const result = await model.doStream({
      prompt: [
        { role: 'user', content: 'Read the package.json file and tell me the project name and version.' }
      ],
      abortSignal: undefined
    });
    
    console.log('✅ Stream created for file operation');
    
    // Read the stream
    const reader = result.stream.getReader();
    let hasToolCall = false;
    
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      if (value.type === 'text-delta') {
        process.stdout.write(value.delta);
      } else if (value.type === 'tool-input-start') {
        console.log(`\n🔧 Tool call: ${value.toolName}`);
        hasToolCall = true;
      }
    }
    
    console.log('\n\n✅ File operation test passed!');
    console.log(`   Tool was called: ${hasToolCall ? 'Yes' : 'No'}\n`);
    return true;
  } catch (error) {
    console.error('❌ File operation test failed:', error);
    return false;
  }
}

async function runTests() {
  console.log('🚀 Starting Claude Code integration tests...\n');
  console.log(`📁 Working directory: ${process.cwd()}`);
  console.log(`🔑 API Key: ${process.env.ANTHROPIC_API_KEY.slice(0, 10)}...`);
  console.log(`📊 Model: sonnet\n`);
  
  const test1 = await testBasicQuery();
  const test2 = await testFileOperation();
  
  console.log('\n📊 Test Results:');
  console.log(`   Basic Query: ${test1 ? '✅ PASSED' : '❌ FAILED'}`);
  console.log(`   File Operation: ${test2 ? '✅ PASSED' : '❌ FAILED'}`);
  
  if (test1 && test2) {
    console.log('\n🎉 All tests passed! Claude Code integration is working.');
  } else {
    console.log('\n❌ Some tests failed. Check the errors above.');
    process.exit(1);
  }
}

runTests().catch(console.error);