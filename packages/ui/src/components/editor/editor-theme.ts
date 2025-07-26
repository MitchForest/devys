import { EditorView } from '@codemirror/view';
import { Extension } from '@codemirror/state';
import { HighlightStyle, syntaxHighlighting } from '@codemirror/language';
import { tags as t } from '@lezer/highlight';

// Define the editor theme using CSS variables
export const createEditorTheme = (isDark: boolean): Extension => {
  const theme = EditorView.theme({
    '&': {
      color: 'var(--color-foreground)',
      backgroundColor: 'transparent',
      height: '100%',
      fontSize: 'var(--font-size-base)',
      fontFamily: '"Zed Mono", ui-monospace, SFMono-Regular, "SF Mono", Consolas, "Liberation Mono", Menlo, monospace',
    },
    
    '&.cm-editor': {
      backgroundColor: 'hsl(var(--color-editor-bg))',
    },
    
    '&.cm-editor.cm-focused': {
      outline: 'none',
    },
    
    '.cm-content': {
      caretColor: 'hsl(var(--color-primary))',
      padding: 'var(--spacing-4)',
      lineHeight: 'var(--line-height-base)',
    },
    
    '.cm-cursor, .cm-dropCursor': {
      borderLeftColor: 'hsl(var(--color-primary))',
    },
    
    '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection': {
      backgroundColor: 'hsl(var(--color-editor-selection))',
    },
    
    '.cm-panels': {
      backgroundColor: 'hsl(var(--color-surface-2))',
      color: 'hsl(var(--color-foreground))',
    },
    
    '.cm-panels.cm-panels-top': {
      borderBottom: '1px solid hsl(var(--color-border))',
    },
    
    '.cm-panels.cm-panels-bottom': {
      borderTop: '1px solid hsl(var(--color-border))',
    },
    
    '.cm-searchMatch': {
      backgroundColor: 'hsl(var(--color-accent) / 0.3)',
      outline: '1px solid hsl(var(--color-accent) / 0.5)',
    },
    
    '.cm-searchMatch.cm-searchMatch-selected': {
      backgroundColor: 'hsl(var(--color-accent) / 0.5)',
    },
    
    '.cm-activeLine': {
      backgroundColor: 'hsl(var(--color-editor-active-line))',
    },
    
    '.cm-selectionMatch': {
      backgroundColor: 'hsl(var(--color-accent) / 0.2)',
    },
    
    '&.cm-focused .cm-matchingBracket, &.cm-focused .cm-nonmatchingBracket': {
      backgroundColor: 'hsl(var(--color-accent) / 0.3)',
      outline: '1px solid hsl(var(--color-accent) / 0.5)',
    },
    
    '.cm-gutters': {
      backgroundColor: 'hsl(var(--color-editor-bg))',
      color: 'hsl(var(--color-muted))',
      border: 'none',
      borderRight: '1px solid hsl(var(--color-border))',
    },
    
    '.cm-activeLineGutter': {
      backgroundColor: 'hsl(var(--color-editor-active-line))',
      color: 'hsl(var(--color-foreground))',
    },
    
    '.cm-foldPlaceholder': {
      backgroundColor: 'transparent',
      border: 'none',
      color: 'hsl(var(--color-muted))',
    },
    
    '.cm-tooltip': {
      border: '1px solid hsl(var(--color-border))',
      backgroundColor: 'hsl(var(--color-tooltip))',
      color: 'hsl(var(--color-tooltip-foreground))',
    },
    
    '.cm-tooltip .cm-tooltip-arrow:before': {
      borderTopColor: 'transparent',
      borderBottomColor: 'transparent',
    },
    
    '.cm-tooltip .cm-tooltip-arrow:after': {
      borderTopColor: 'hsl(var(--color-tooltip))',
      borderBottomColor: 'hsl(var(--color-tooltip))',
    },
    
    '.cm-tooltip-autocomplete': {
      '& > ul > li[aria-selected]': {
        backgroundColor: 'hsl(var(--color-accent))',
        color: 'hsl(var(--color-accent-foreground))',
      },
    },
    
    '.cm-lineNumbers .cm-gutterElement': {
      padding: '0 var(--spacing-2)',
      minWidth: 'var(--spacing-8)',
    },
    
    '.cm-editor': {
      height: '100%',
    },
    
    '.cm-scroller': {
      fontFamily: '"Zed Mono", ui-monospace, SFMono-Regular, "SF Mono", Consolas, "Liberation Mono", Menlo, monospace',
      scrollbarWidth: 'thin',
      scrollbarColor: 'hsl(var(--color-border)) transparent',
      overflow: 'auto',
    },
    
    '.cm-scroller::-webkit-scrollbar': {
      width: '8px',
      height: '8px',
    },
    
    '.cm-scroller::-webkit-scrollbar-track': {
      background: 'transparent',
    },
    
    '.cm-scroller::-webkit-scrollbar-thumb': {
      backgroundColor: 'hsl(var(--color-border))',
      borderRadius: 'var(--radius-sm)',
      border: '2px solid transparent',
      backgroundClip: 'content-box',
    },
    
    '.cm-scroller::-webkit-scrollbar-thumb:hover': {
      backgroundColor: 'hsl(var(--color-muted))',
    },
    
    '.cm-foldGutter .cm-gutterElement': {
      cursor: 'pointer',
      padding: '0 var(--spacing-1)',
    },
  }, { dark: isDark });

  // Syntax highlighting theme
  const highlightStyle = HighlightStyle.define([
    { tag: t.keyword, color: isDark ? '#FF79C6' : '#D73A49' },
    { tag: t.operator, color: isDark ? '#FF79C6' : '#D73A49' },
    { tag: t.special(t.variableName), color: isDark ? '#FF79C6' : '#D73A49' },
    
    { tag: [t.function(t.variableName), t.function(t.propertyName)], color: isDark ? '#50FA7B' : '#6F42C1' },
    { tag: t.definition(t.variableName), color: isDark ? '#8BE9FD' : '#005CC5' },
    { tag: t.definition(t.propertyName), color: isDark ? '#8BE9FD' : '#005CC5' },
    
    { tag: t.typeName, color: isDark ? '#8BE9FD' : '#005CC5' },
    { tag: t.className, color: isDark ? '#8BE9FD' : '#005CC5' },
    { tag: t.namespace, color: isDark ? '#8BE9FD' : '#005CC5' },
    
    { tag: t.string, color: isDark ? '#F1FA8C' : '#032F62' },
    { tag: t.character, color: isDark ? '#F1FA8C' : '#032F62' },
    { tag: t.regexp, color: isDark ? '#F1FA8C' : '#032F62' },
    
    { tag: t.number, color: isDark ? '#BD93F9' : '#005CC5' },
    { tag: t.bool, color: isDark ? '#BD93F9' : '#005CC5' },
    { tag: t.null, color: isDark ? '#BD93F9' : '#005CC5' },
    
    { tag: t.comment, color: 'hsl(var(--color-muted))', fontStyle: 'italic' },
    { tag: t.meta, color: 'hsl(var(--color-muted))' },
    { tag: t.documentMeta, color: 'hsl(var(--color-muted))' },
    
    { tag: t.propertyName, color: isDark ? '#F8F8F2' : '#24292E' },
    { tag: t.variableName, color: isDark ? '#F8F8F2' : '#24292E' },
    { tag: t.labelName, color: isDark ? '#F8F8F2' : '#24292E' },
    
    { tag: t.link, color: isDark ? '#8BE9FD' : '#005CC5', textDecoration: 'underline' },
    { tag: t.url, color: isDark ? '#8BE9FD' : '#005CC5', textDecoration: 'underline' },
    
    { tag: t.heading, fontWeight: 'bold', color: isDark ? '#BD93F9' : '#005CC5' },
    { tag: t.emphasis, fontStyle: 'italic', color: isDark ? '#F1FA8C' : '#22863A' },
    { tag: t.strong, fontWeight: 'bold', color: isDark ? '#FFB86C' : '#E36209' },
    
    { tag: t.atom, color: isDark ? '#BD93F9' : '#005CC5' },
    { tag: t.invalid, color: isDark ? '#FF5555' : '#CB2431' },
  ]);

  return [theme, syntaxHighlighting(highlightStyle)];
};