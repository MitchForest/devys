#!/usr/bin/env node

// Final test of chat API after fixes

async function testChat() {
  console.log('Testing chat API after fixes...\n');
  
  try {
    // Test 1: Simple message
    console.log('Test 1: Simple user message');
    const response1 = await fetch('http://localhost:3001/api/chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          {
            id: 'test-' + Date.now(),
            role: 'user',
            content: 'Hello, can you hear me? Please respond with a simple greeting.'
          }
        ],
        sessionId: 'test-session-' + Date.now()
      })
    });
    
    console.log('Status:', response1.status);
    
    if (!response1.ok) {
      const error = await response1.text();
      console.error('Error:', error);
    } else {
      console.log('Success! Reading stream...');
      
      const reader = response1.body.getReader();
      const decoder = new TextDecoder();
      let fullResponse = '';
      
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        
        const chunk = decoder.decode(value);
        fullResponse += chunk;
        process.stdout.write('.');
      }
      
      console.log('\n\nFull response length:', fullResponse.length);
      console.log('First 200 chars:', fullResponse.substring(0, 200) + '...');
    }
    
    console.log('\n---\n');
    
    // Test 2: Message with parts format
    console.log('Test 2: Message with parts array (AI SDK v5 format)');
    const response2 = await fetch('http://localhost:3001/api/chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          {
            id: 'test-parts-' + Date.now(),
            role: 'user',
            parts: [
              {
                type: 'text',
                text: 'Testing parts format - please confirm you received this.'
              }
            ]
          }
        ],
        sessionId: 'test-session-parts-' + Date.now()
      })
    });
    
    console.log('Status:', response2.status);
    
    if (!response2.ok) {
      const error = await response2.text();
      console.error('Error:', error);
    } else {
      console.log('Success!');
    }
    
    console.log('\n---\n');
    
    // Test 3: Message with attachments
    console.log('Test 3: Message with file attachment');
    const response3 = await fetch('http://localhost:3001/api/chat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messages: [
          {
            id: 'test-attach-' + Date.now(),
            role: 'user',
            content: 'What is in the attached file?'
          }
        ],
        sessionId: 'test-session-files-' + Date.now(),
        attachments: [
          {
            path: '/test/file.js',
            name: 'file.js',
            content: 'console.log("Hello from test file");',
            language: 'javascript'
          }
        ]
      })
    });
    
    console.log('Status:', response3.status);
    
    if (!response3.ok) {
      const error = await response3.text();
      console.error('Error:', error);
    } else {
      console.log('Success!');
    }
    
  } catch (error) {
    console.error('Fatal error:', error);
  }
}

// Check server health first
fetch('http://localhost:3001/api/chat/health')
  .then(res => {
    if (res.ok) {
      console.log('Server is healthy\n');
      testChat();
    } else {
      console.error('Server health check failed');
    }
  })
  .catch(() => {
    console.error('Server is not running on port 3001. Please run: bun run dev:server');
  });