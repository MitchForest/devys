import React, { useEffect, useRef, useState } from 'react';
import { Terminal as XTerm } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import { WebLinksAddon } from 'xterm-addon-web-links';
import { SearchAddon } from 'xterm-addon-search';
import 'xterm/css/xterm.css';
import { cn } from '../../lib/utils';
import { getTerminalTheme } from '../../lib/css-variables';

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
    if (!terminalRef.current) return;
    
    // Clean up any existing terminal first
    if (xtermRef.current) {
      try {
        xtermRef.current.dispose();
      } catch (e) {
        // Ignore disposal errors
      }
      xtermRef.current = null;
    }
    
    // Additional guard for React StrictMode
    const existingTerminal = terminalRef.current.querySelector('.xterm');
    if (existingTerminal) {
      existingTerminal.remove();
    }

    // Create terminal instance
    const xterm = new XTerm({
      fontSize,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      cols: 80,
      rows: 24,
      theme: getTerminalTheme(theme),
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

    // Store references first
    xtermRef.current = xterm;
    fitAddonRef.current = fitAddon;

    // Use requestAnimationFrame to ensure DOM is ready
    requestAnimationFrame(() => {
      if (terminalRef.current && terminalRef.current.offsetWidth > 0 && terminalRef.current.offsetHeight > 0) {
        try {
          xterm.open(terminalRef.current);
          // Fit after opening
          setTimeout(() => {
            if (fitAddonRef.current && xtermRef.current?.element) {
              try {
                fitAddonRef.current.fit();
              } catch (e) {
                // Ignore fit errors on initial render
              }
            }
          }, 50);
        } catch (error) {
          console.error('Failed to open terminal:', error);
          // Try again after a delay
          setTimeout(() => {
            if (terminalRef.current && !xterm.element && terminalRef.current.offsetWidth > 0) {
              try {
                xterm.open(terminalRef.current);
                // Fit after retry
                setTimeout(() => {
                  if (fitAddonRef.current && xtermRef.current?.element) {
                    try {
                      fitAddonRef.current.fit();
                    } catch (e) {
                      // Ignore fit errors
                    }
                  }
                }, 50);
              } catch (e) {
                console.error('Failed to open terminal on retry:', e);
              }
            }
          }, 100);
        }
      } else {
        // Terminal container not ready, wait and retry
        setTimeout(() => {
          if (terminalRef.current && !xterm.element && terminalRef.current.offsetWidth > 0) {
            try {
              xterm.open(terminalRef.current);
              setTimeout(() => {
                if (fitAddonRef.current && xtermRef.current?.element) {
                  try {
                    fitAddonRef.current.fit();
                  } catch (e) {
                    // Ignore fit errors
                  }
                }
              }, 50);
            } catch (e) {
              console.error('Failed to open terminal after waiting:', e);
            }
          }
        }, 200);
      }
    });

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

    // Set ready state
    setIsReady(true);
    
    // Focus terminal after it's ready
    requestAnimationFrame(() => {
      xterm.focus();
    });

    // Use ResizeObserver to handle fitting when container has dimensions
    const resizeObserver = new ResizeObserver(() => {
      if (
        fitAddonRef.current &&
        terminalRef.current?.isConnected &&
        terminalRef.current.offsetWidth > 0 &&
        terminalRef.current.offsetHeight > 0 &&
        xtermRef.current?.element
      ) {
        try {
          fitAddonRef.current.fit();
        } catch (error) {
          console.warn('Failed to fit terminal:', error);
        }
      }
    });

    // Start observing after terminal is opened
    requestAnimationFrame(() => {
      if (terminalRef.current) {
        resizeObserver.observe(terminalRef.current);
      }
    });

    return () => {
      resizeObserver.disconnect();
      if (xtermRef.current) {
        try {
          xtermRef.current.dispose();
        } catch (error) {
          // Ignore disposal errors
        }
        xtermRef.current = null;
      }
      fitAddonRef.current = null;
    };
  }, [fontSize, theme, onData, onResize, onTitleChange]);

  // Update terminal theme when prop changes
  useEffect(() => {
    if (!xtermRef.current) return;
    xtermRef.current.options.theme = getTerminalTheme(theme);
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
      if (
        fitAddonRef.current &&
        terminalRef.current?.isConnected &&
        terminalRef.current.offsetWidth > 0 &&
        terminalRef.current.offsetHeight > 0 &&
        xtermRef.current?.element
      ) {
        try {
          fitAddonRef.current.fit();
        } catch (error) {
          console.warn('Failed to fit terminal:', error);
        }
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
      data-ready={isReady}
    />
  );
});

TerminalWithRef.displayName = 'Terminal';

export const Terminal = TerminalWithRef;