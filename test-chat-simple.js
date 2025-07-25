#!/usr/bin/env node

// Simple test of chat API

async function testChat() {
  console.log('Testing chat API...\n');
  
  const response = await fetch('http://localhost:3001/api/chat', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messages: [
        {
          id: 'msg-' + Date.now(),
          role: 'user',
          content: 'Say hello'
        }
      ],
      sessionId: 'test-' + Date.now()
    })
  });
  
  console.log('Status:', response.status);
  console.log('Headers:', response.headers.get('content-type'));
  
  if (!response.ok) {
    const error = await response.text();
    console.error('Error:', error);
    return;
  }
  
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  
  console.log('\nStreaming response:');
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    
    const chunk = decoder.decode(value);
    console.log('Chunk:', chunk);
  }
}

testChat().catch(console.error);