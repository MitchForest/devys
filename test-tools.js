#!/usr/bin/env bun

// Test script for Claude Code tool integration
// Run with: bun test-tools.js

console.log('🧪 Testing Claude Code Tool Integration...\n');

async function testServerWithTools() {
  console.log('1️⃣ Testing tool streaming through server...');
  
  try {
    const response = await fetch('http://localhost:3001/api/chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          {
            id: '1',
            role: 'user',
            content: 'List the files in the current directory and tell me what type of project this is.',
            createdAt: new Date().toISOString()
          }
        ],
        sessionId: 'test-session-' + Date.now()
      })
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    console.log('✅ Got response from server');
    console.log('📊 Headers:', Object.fromEntries(response.headers.entries()));

    // Read the stream
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    let toolCalls = [];

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      buffer += decoder.decode(value, { stream: true });
      
      // Process complete messages (data: lines)
      const lines = buffer.split('\n');
      buffer = lines.pop() || ''; // Keep incomplete line in buffer
      
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = line.slice(6).trim();
          if (data === '[DONE]') continue;
          
          try {
            const parsed = JSON.parse(data);
            
            // Check for different event types
            if (parsed.type === 'text-delta') {
              process.stdout.write(parsed.textDelta || '');
            } else if (parsed.type === 'tool-call') {
              console.log(`\n🔧 Tool call detected: ${parsed.toolName}`);
              toolCalls.push(parsed);
            } else if (parsed.type === 'tool-result') {
              console.log(`\n✅ Tool result for: ${parsed.toolName}`);
            }
          } catch (e) {
            // Not all lines are JSON
          }
        }
      }
    }

    console.log('\n\n📊 Summary:');
    console.log(`   Total tool calls: ${toolCalls.length}`);
    console.log(`   Tools used: ${toolCalls.map(t => t.toolName).join(', ')}`);
    
    return true;
  } catch (error) {
    console.error('❌ Test failed:', error);
    return false;
  }
}

async function testDirectProvider() {
  console.log('\n2️⃣ Testing direct provider tool streaming...');
  
  try {
    const { createClaudeCode } = await import('./packages/core/src/providers/claude-code-language-model.js');
    
    const provider = createClaudeCode({
      apiKey: process.env.ANTHROPIC_API_KEY,
      cwd: process.cwd()
    });
    
    const model = provider.languageModel('sonnet');
    
    const result = await model.doStream({
      prompt: [
        { role: 'user', content: 'Create a simple test.txt file with "Hello World" content.' }
      ],
      abortSignal: undefined
    });
    
    console.log('✅ Stream created successfully');
    
    // Read the stream
    const reader = result.stream.getReader();
    let hasToolCall = false;
    
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      
      if (value.type === 'text-delta') {
        process.stdout.write(value.delta);
      } else if (value.type === 'tool-input-start') {
        console.log(`\n🔧 Tool input start: ${value.toolName}`);
        hasToolCall = true;
      } else if (value.type === 'tool-input-delta') {
        console.log(`   Input: ${value.delta}`);
      } else if (value.type === 'tool-input-end') {
        console.log(`   Tool input end`);
      }
    }
    
    console.log(`\n\n✅ Direct provider test passed!`);
    console.log(`   Tool was called: ${hasToolCall ? 'Yes' : 'No'}`);
    
    return true;
  } catch (error) {
    console.error('❌ Direct provider test failed:', error);
    return false;
  }
}

async function runTests() {
  console.log('🚀 Starting Claude Code tool integration tests...\n');
  console.log(`📁 Working directory: ${process.cwd()}`);
  console.log(`🔑 API Key: ${process.env.ANTHROPIC_API_KEY?.slice(0, 10)}...`);
  
  // Check if server is running
  try {
    const health = await fetch('http://localhost:3001/health');
    if (health.ok) {
      console.log('✅ Server is running\n');
    }
  } catch (e) {
    console.log('⚠️  Server not running. Start it with: bun run server\n');
    console.log('Running direct provider test only...\n');
    
    const test2 = await testDirectProvider();
    console.log('\n📊 Test Results:');
    console.log(`   Direct Provider: ${test2 ? '✅ PASSED' : '❌ FAILED'}`);
    return;
  }
  
  const test1 = await testServerWithTools();
  const test2 = await testDirectProvider();
  
  console.log('\n📊 Test Results:');
  console.log(`   Server Integration: ${test1 ? '✅ PASSED' : '❌ FAILED'}`);
  console.log(`   Direct Provider: ${test2 ? '✅ PASSED' : '❌ FAILED'}`);
  
  if (test1 && test2) {
    console.log('\n🎉 All tests passed! Tool integration is working.');
  } else {
    console.log('\n❌ Some tests failed. Check the errors above.');
    process.exit(1);
  }
}

runTests().catch(console.error);