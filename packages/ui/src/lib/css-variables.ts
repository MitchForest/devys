/**
 * Get a CSS variable value from the document root
 * @param varName The CSS variable name (e.g. '--color-foreground')
 * @returns The computed value of the CSS variable
 */
export function getCSSVariable(varName: string): string {
  return getComputedStyle(document.documentElement)
    .getPropertyValue(varName)
    .trim();
}

/**
 * Get a CSS color variable value, converting HSL to hex if needed
 * @param varName The CSS variable name (e.g. '--color-foreground')
 * @returns The color value (HSL or hex format)
 */
export function getCSSColorVariable(varName: string): string {
  const value = getCSSVariable(varName);
  
  // If it's already a hex color or rgb, return as is
  if (value.startsWith('#') || value.startsWith('rgb')) {
    return value;
  }
  
  // If it's HSL values (e.g. "0 0% 20%"), convert to hsl() format
  if (value && !value.startsWith('hsl')) {
    return `hsl(${value})`;
  }
  
  return value;
}

/**
 * Get terminal theme colors from CSS variables
 * @param fallbackTheme 'dark' or 'light' for fallback values
 */
export function getTerminalTheme(fallbackTheme: 'dark' | 'light' = 'dark') {
  const fallbacks = {
    dark: {
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
    },
    light: {
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
    }
  };

  return {
    foreground: getCSSColorVariable('--color-terminal-fg'),
    background: getCSSColorVariable('--color-terminal-bg'),
    cursor: getCSSColorVariable('--color-foreground'),
    black: getCSSVariable('--color-terminal-black') || fallbacks[fallbackTheme].black,
    red: getCSSVariable('--color-terminal-red') || fallbacks[fallbackTheme].red,
    green: getCSSVariable('--color-terminal-green') || fallbacks[fallbackTheme].green,
    yellow: getCSSVariable('--color-terminal-yellow') || fallbacks[fallbackTheme].yellow,
    blue: getCSSVariable('--color-terminal-blue') || fallbacks[fallbackTheme].blue,
    magenta: getCSSVariable('--color-terminal-magenta') || fallbacks[fallbackTheme].magenta,
    cyan: getCSSVariable('--color-terminal-cyan') || fallbacks[fallbackTheme].cyan,
    white: getCSSVariable('--color-terminal-white') || fallbacks[fallbackTheme].white,
    brightBlack: getCSSVariable('--color-terminal-bright-black') || fallbacks[fallbackTheme].brightBlack,
    brightRed: getCSSVariable('--color-terminal-bright-red') || fallbacks[fallbackTheme].brightRed,
    brightGreen: getCSSVariable('--color-terminal-bright-green') || fallbacks[fallbackTheme].brightGreen,
    brightYellow: getCSSVariable('--color-terminal-bright-yellow') || fallbacks[fallbackTheme].brightYellow,
    brightBlue: getCSSVariable('--color-terminal-bright-blue') || fallbacks[fallbackTheme].brightBlue,
    brightMagenta: getCSSVariable('--color-terminal-bright-magenta') || fallbacks[fallbackTheme].brightMagenta,
    brightCyan: getCSSVariable('--color-terminal-bright-cyan') || fallbacks[fallbackTheme].brightCyan,
    brightWhite: getCSSVariable('--color-terminal-bright-white') || fallbacks[fallbackTheme].brightWhite
  };
}