// Components
export * from './components/ui/button';
export * from './components/ui/tabs';
export * from './components/ui/theme-toggle';
export * from './components/ui/context-menu';
export * from './components/ui/toast';
export * from './components/ui/card';
export * from './components/ui/progress';
export * from './components/ui/badge';
export * from './components/ui/dialog';
export * from './components/ui/scroll-area';
export * from './components/layout/resizable-panels';
export * from './components/file-explorer/file-explorer';
export * from './components/file-explorer/file-tree';
export * from './components/editor';
export * from './components/chat';
export * from './components/terminal';
export * from './components/workflow';
export * from './components/menu/menu-bar';
export * from './components/welcome/welcome-page';

// Services
export * from './services/file-service';
export * from './services/terminal-service';

// Hooks
export * from './hooks/use-chat-session';
export * from './hooks/use-app-websocket';
export * from './hooks/use-terminal-websocket';

// Contexts
export * from './contexts';

// Utils
export * from './lib/utils';

// Re-export terminal service instance
import { terminalService } from './services/terminal-service';
export { terminalService };