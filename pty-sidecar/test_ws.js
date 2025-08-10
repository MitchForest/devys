#!/usr/bin/env node
// Simple WebSocket test client for Day 1-2 validation

const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:8081');

ws.on('open', () => {
    console.log('✅ Connected to WebSocket server');
    
    // Test ping
    ws.send(JSON.stringify({ cmd: 'ping' }));
    
    // Test metrics
    setTimeout(() => {
        ws.send(JSON.stringify({ cmd: 'metrics' }));
    }, 100);
    
    // Test binary data
    setTimeout(() => {
        const buffer = Buffer.from('Hello from test client');
        ws.send(buffer);
    }, 200);
    
    // Close after tests
    setTimeout(() => {
        ws.close();
    }, 500);
});

ws.on('message', (data) => {
    if (data instanceof Buffer) {
        console.log('📦 Received binary:', data.toString());
    } else {
        console.log('📨 Received:', data.toString());
        const msg = JSON.parse(data.toString());
        if (msg.cmd === 'session') {
            console.log('✅ Session ID received:', msg.id);
        } else if (msg.cmd === 'pong') {
            console.log('✅ Pong received');
        } else if (msg.status) {
            console.log('✅ Metrics received:', msg);
        }
    }
});

ws.on('close', () => {
    console.log('✅ Connection closed gracefully');
    process.exit(0);
});

ws.on('error', (err) => {
    console.error('❌ WebSocket error:', err.message);
    process.exit(1);
});