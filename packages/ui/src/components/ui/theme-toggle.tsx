import React from 'react';
import { Moon, Sun, Monitor } from 'lucide-react';
import { cn } from '../../lib/utils';

interface ThemeToggleProps {
  theme: 'light' | 'dark' | 'system';
  onThemeChange: (theme: 'light' | 'dark' | 'system') => void;
  className?: string;
}

export function ThemeToggle({ theme, onThemeChange, className }: ThemeToggleProps) {
  const cycleTheme = () => {
    const themes: Array<'light' | 'dark' | 'system'> = ['light', 'dark', 'system'];
    const currentIndex = themes.indexOf(theme);
    const nextIndex = (currentIndex + 1) % themes.length;
    onThemeChange(themes[nextIndex]);
  };

  return (
    <button
      onClick={cycleTheme}
      className={cn(
        "rounded-sm transition-zed hover:bg-hover text-muted hover:text-foreground",
        className
      )}
      title={`Theme: ${theme}`}
    >
      {theme === 'light' && <Sun className="h-3.5 w-3.5" />}
      {theme === 'dark' && <Moon className="h-3.5 w-3.5" />}
      {theme === 'system' && <Monitor className="h-3.5 w-3.5" />}
    </button>
  );
}