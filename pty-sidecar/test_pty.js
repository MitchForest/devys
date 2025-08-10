#!/usr/bin/env bun
// Test PTY integration with Zellij

const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:8081');

ws.on('open', () => {
    console.log('✅ Connected to PTY server');
});

ws.on('message', (data) => {
    if (data instanceof Buffer) {
        // Binary data from PTY (terminal output)
        process.stdout.write(data);
    } else {
        // Text control messages
        const msg = JSON.parse(data.toString());
        if (msg.cmd === 'session') {
            console.log('\n✅ Session ID:', msg.id);
            console.log('✅ Zellij should be running now');
            
            // Send a test command after 1 second
            setTimeout(() => {
                console.log('\n📝 Sending test input...');
                ws.send(Buffer.from('echo "Hello from PTY!"\r'));
            }, 1000);
            
            // Close after 3 seconds
            setTimeout(() => {
                console.log('\n👋 Closing connection...');
                ws.close();
            }, 3000);
        }
    }
});

ws.on('close', () => {
    console.log('\n✅ Connection closed');
    process.exit(0);
});

ws.on('error', (err) => {
    console.error('❌ Error:', err.message);
    process.exit(1);
});