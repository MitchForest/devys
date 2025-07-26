import React, { useCallback, useMemo } from 'react';
import CodeMirror from '@uiw/react-codemirror';
import { javascript } from '@codemirror/lang-javascript';
import { python } from '@codemirror/lang-python';
import { json } from '@codemirror/lang-json';
import { html } from '@codemirror/lang-html';
import { css } from '@codemirror/lang-css';
import { markdown } from '@codemirror/lang-markdown';
import { EditorView } from '@codemirror/view';
import { createEditorTheme } from './editor-theme';

interface CodeEditorProps {
  value: string;
  onChange?: (value: string) => void;
  language?: string;
  theme?: 'light' | 'dark';
  readOnly?: boolean;
  height?: string;
  className?: string;
}

export function CodeEditor({
  value,
  onChange,
  language = 'text',
  theme = 'dark',
  readOnly = false,
  height: _height = '100%',
  className = ''
}: CodeEditorProps) {
  const handleChange = useCallback((val: string) => {
    onChange?.(val);
  }, [onChange]);

  // Get language extension based on language prop
  const languageExtension = useMemo(() => {
    switch (language) {
      case 'javascript':
      case 'typescript':
      case 'jsx':
      case 'tsx':
        return javascript({ jsx: true, typescript: language.includes('typescript') });
      case 'python':
        return python();
      case 'json':
        return json();
      case 'html':
        return html();
      case 'css':
        return css();
      case 'markdown':
      case 'md':
        return markdown();
      default:
        return [];
    }
  }, [language]);

  // Editor extensions
  const extensions = useMemo(() => {
    const baseExtensions = [
      createEditorTheme(theme === 'dark'),
      EditorView.lineWrapping
    ];

    if (languageExtension) {
      return [...baseExtensions, languageExtension];
    }
    
    return baseExtensions;
  }, [theme, languageExtension]);

  return (
    <div className={`h-full ${className}`}>
      <CodeMirror
        value={value}
        onChange={handleChange}
        theme={undefined}
        extensions={extensions}
        editable={!readOnly}
        height="100%"
        basicSetup={{
          lineNumbers: true,
          foldGutter: true,
          dropCursor: true,
          allowMultipleSelections: true,
          indentOnInput: true,
          bracketMatching: true,
          closeBrackets: true,
          autocompletion: true,
          rectangularSelection: true,
          highlightSelectionMatches: true,
          searchKeymap: true,
          defaultKeymap: true,
          historyKeymap: true,
          completionKeymap: true,
          lintKeymap: true
        }}
      />
    </div>
  );
}