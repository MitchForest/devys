import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { ThemeProvider, WebSocketProvider, TerminalWebSocketProvider } from '@devys/ui';
import './index.css';

const WS_URL = 'ws://localhost:3001';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <ThemeProvider defaultTheme="dark">
      <WebSocketProvider url={WS_URL}>
        <TerminalWebSocketProvider url={WS_URL}>
          <App />
        </TerminalWebSocketProvider>
      </WebSocketProvider>
    </ThemeProvider>
  </React.StrictMode>
);