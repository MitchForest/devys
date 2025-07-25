import React, { useEffect, useRef, useState } from 'react';
import { Terminal as XTerm } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebLinksAddon } from 'xterm-addon-web-links';
import { SearchAddon } from 'xterm-addon-search';
import 'xterm/css/xterm.css';
import { cn } from '../../lib/utils';

interface TerminalProps {
  id: string;
  className?: string;
  theme?: 'dark' | 'light';
  fontSize?: number;
  onData?: (data: string) => void;
  onResize?: (cols: number, rows: number) => void;
  onTitleChange?: (title: string) => void;
}

// Terminal with imperative handle
export const TerminalWithRef = React.forwardRef<{
  write: (data: string) => void;
  writeln: (data: string) => void;
  clear: () => void;
  focus: () => void;
  fit: () => void;
  getTerminal: () => XTerm | null;
}, TerminalProps>(({ 
  id: _id,
  className,
  theme = 'dark',
  fontSize = 14,
  onData,
  onResize,
  onTitleChange
}, ref) => {
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<XTerm | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const [isReady, setIsReady] = useState(false);

  useEffect(() => {
    if (!terminalRef.current || xtermRef.current) return;

    // Create terminal instance
    const xterm = new XTerm({
      fontSize,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      theme: theme === 'dark' ? {
        foreground: '#f8f8f2',
        background: '#1e1e1e',
        cursor: '#f8f8f0',
        black: '#272822',
        red: '#f92672',
        green: '#a6e22e',
        yellow: '#f4bf75',
        blue: '#66d9ef',
        magenta: '#ae81ff',
        cyan: '#a1efe4',
        white: '#f8f8f2',
        brightBlack: '#75715e',
        brightRed: '#f92672',
        brightGreen: '#a6e22e',
        brightYellow: '#f4bf75',
        brightBlue: '#66d9ef',
        brightMagenta: '#ae81ff',
        brightCyan: '#a1efe4',
        brightWhite: '#f9f8f5'
      } : {
        foreground: '#383a42',
        background: '#fafafa',
        cursor: '#383a42',
        black: '#383a42',
        red: '#e45649',
        green: '#50a14f',
        yellow: '#c18401',
        blue: '#0184bc',
        magenta: '#a626a4',
        cyan: '#0997b3',
        white: '#fafafa',
        brightBlack: '#4f525d',
        brightRed: '#e45649',
        brightGreen: '#50a14f',
        brightYellow: '#c18401',
        brightBlue: '#0184bc',
        brightMagenta: '#a626a4',
        brightCyan: '#0997b3',
        brightWhite: '#fafafa'
      },
      cursorBlink: true,
      cursorStyle: 'block',
      scrollback: 10000,
      tabStopWidth: 4,
      windowsMode: navigator.platform.includes('Win')
    });

    // Create and load addons
    const fitAddon = new FitAddon();
    const webLinksAddon = new WebLinksAddon();
    const searchAddon = new SearchAddon();

    xterm.loadAddon(fitAddon);
    xterm.loadAddon(webLinksAddon);
    xterm.loadAddon(searchAddon);

    // Open terminal in DOM
    xterm.open(terminalRef.current);

    // Store references
    xtermRef.current = xterm;
    fitAddonRef.current = fitAddon;

    // Fit terminal to container
    fitAddon.fit();

    // Set up event handlers
    if (onData) {
      xterm.onData(onData);
    }

    if (onResize) {
      xterm.onResize(({ cols, rows }) => {
        onResize(cols, rows);
      });
    }

    if (onTitleChange) {
      xterm.onTitleChange(onTitleChange);
    }

    // Write welcome message
    xterm.writeln('Welcome to Claude Code IDE Terminal');
    xterm.writeln('');
    xterm.write('$ ');

    setIsReady(true);

    // Handle window resize
    const handleResize = () => {
      if (fitAddonRef.current) {
        fitAddonRef.current.fit();
      }
    };

    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      xterm.dispose();
      xtermRef.current = null;
      fitAddonRef.current = null;
    };
  }, [fontSize, theme, onData, onResize, onTitleChange]);

  // Update terminal theme when prop changes
  useEffect(() => {
    if (!xtermRef.current) return;

    xtermRef.current.options.theme = theme === 'dark' ? {
      foreground: '#f8f8f2',
      background: '#1e1e1e',
      cursor: '#f8f8f0',
      black: '#272822',
      red: '#f92672',
      green: '#a6e22e',
      yellow: '#f4bf75',
      blue: '#66d9ef',
      magenta: '#ae81ff',
      cyan: '#a1efe4',
      white: '#f8f8f2',
      brightBlack: '#75715e',
      brightRed: '#f92672',
      brightGreen: '#a6e22e',
      brightYellow: '#f4bf75',
      brightBlue: '#66d9ef',
      brightMagenta: '#ae81ff',
      brightCyan: '#a1efe4',
      brightWhite: '#f9f8f5'
    } : {
      foreground: '#383a42',
      background: '#fafafa',
      cursor: '#383a42',
      black: '#383a42',
      red: '#e45649',
      green: '#50a14f',
      yellow: '#c18401',
      blue: '#0184bc',
      magenta: '#a626a4',
      cyan: '#0997b3',
      white: '#fafafa',
      brightBlack: '#4f525d',
      brightRed: '#e45649',
      brightGreen: '#50a14f',
      brightYellow: '#c18401',
      brightBlue: '#0184bc',
      brightMagenta: '#a626a4',
      brightCyan: '#0997b3',
      brightWhite: '#fafafa'
    };
  }, [theme]);

  // Public methods exposed via ref
  React.useImperativeHandle(ref, () => ({
    write: (data: string) => {
      if (xtermRef.current) {
        xtermRef.current.write(data);
      }
    },
    writeln: (data: string) => {
      if (xtermRef.current) {
        xtermRef.current.writeln(data);
      }
    },
    clear: () => {
      if (xtermRef.current) {
        xtermRef.current.clear();
      }
    },
    focus: () => {
      if (xtermRef.current) {
        xtermRef.current.focus();
      }
    },
    fit: () => {
      if (fitAddonRef.current) {
        fitAddonRef.current.fit();
      }
    },
    getTerminal: () => xtermRef.current
  }), []);

  return (
    <div 
      ref={terminalRef}
      className={cn(
        "h-full w-full",
        "xterm-container",
        className
      )}
      style={{
        opacity: isReady ? 1 : 0,
        transition: 'opacity 0.2s'
      }}
    />
  );
});

TerminalWithRef.displayName = 'Terminal';

export const Terminal = TerminalWithRef;