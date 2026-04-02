#!/usr/bin/env node
// Generate Shiki fixtures for DevysSyntax parity tests.

import { execSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const FIXTURE_DIR = path.join(
  ROOT_DIR,
  'Packages/Syntax/Tests/SyntaxTests/Fixtures'
);

const FIXTURES = [
  { language: 'swift', file: 'sample.swift' },
  { language: 'javascript', file: 'sample.js' },
  { language: 'jsx', file: 'sample.jsx' },
  { language: 'json', file: 'sample.json' },
  { language: 'markdown', file: 'sample.md' },
  { language: 'yaml', file: 'sample.yaml' },
  { language: 'typescript', file: 'sample.ts' },
  { language: 'html', file: 'sample.html' },
  { language: 'css', file: 'sample.css' },
  { language: 'python', file: 'sample.py' },
  { language: 'shellscript', file: 'sample.sh' },
  { language: 'rust', file: 'sample.rs' },
  { language: 'ruby', file: 'sample.rb' },
  { language: 'go', file: 'sample.go' },
  { language: 'php', file: 'sample.php' },
  { language: 'java', file: 'sample.java' },
  { language: 'csharp', file: 'sample.cs' },
  { language: 'cpp', file: 'sample.cpp' },
  { language: 'c', file: 'sample.c' },
  { language: 'lua', file: 'sample.lua' },
  { language: 'kotlin', file: 'sample.kt' },
  { language: 'make', file: 'sample.mk' }
];

const DEFAULT_THEMES = ['github-light'];
const THEMES = (process.env.DEVYS_SHIKI_THEMES ?? '')
  .split(',')
  .map((theme) => theme.trim())
  .filter(Boolean);

const THEME_IDS = THEMES.length ? THEMES : DEFAULT_THEMES;
const SHIKI_VERSION = process.env.DEVYS_SHIKI_VERSION ?? '3.20.0';
const SHIKI_NODE_MODULES = process.env.DEVYS_SHIKI_NODE_MODULES;

function readFixture(name) {
  return fs.readFileSync(path.join(FIXTURE_DIR, name), 'utf8');
}

function writeJSON(dest, data) {
  const payload = JSON.stringify(data, null, 2) + '\n';
  fs.writeFileSync(dest, payload);
}

async function loadShiki() {
  if (SHIKI_NODE_MODULES) {
    const shikiEntry = path.join(SHIKI_NODE_MODULES, 'shiki/dist/index.mjs');
    return import(pathToFileURL(shikiEntry).href);
  }

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'devys-shiki-'));
  execSync('npm init -y', { cwd: tempDir, stdio: 'ignore' });
  execSync(`npm install shiki@${SHIKI_VERSION}`, {
    cwd: tempDir,
    stdio: 'inherit'
  });

  const shikiEntry = path.join(tempDir, 'node_modules/shiki/dist/index.mjs');
  return import(pathToFileURL(shikiEntry).href);
}

function normalizeScopes(scopes) {
  return (scopes ?? [])
    .map((scope) => {
      if (typeof scope === 'string') {
        return scope;
      }
      return scope?.scopeName ?? null;
    })
    .filter(Boolean);
}

async function main() {
  const shiki = await loadShiki();
  const highlighter = await shiki.createHighlighter({
    themes: THEME_IDS,
    langs: FIXTURES.map((fixture) => fixture.language)
  });

  for (const theme of THEME_IDS) {
    for (const fixture of FIXTURES) {
      const content = readFixture(fixture.file);
      const lines = content.split('\n');
      const lineStarts = [];
      let offset = 0;
      for (const line of lines) {
        lineStarts.push(offset);
        offset += line.length + 1;
      }

      const result = highlighter.codeToTokens(content, {
        lang: fixture.language,
        theme,
        includeExplanation: true
      });

      const tokensByLine = result.tokens ?? [];

      const output = {
        language: fixture.language,
        theme,
        lines: lines.map((line, index) => {
          const segments = [];
          const lineTokens = tokensByLine[index] ?? [];
          for (const token of lineTokens) {
            const lineStart = lineStarts[index] ?? 0;
            const tokenOffset = token.offset ?? lineStart;
            const color = token.color ?? null;
            const fontStyle = token.fontStyle ?? 0;

            if (token.explanation && token.explanation.length) {
              let cursor = tokenOffset;
              for (const exp of token.explanation) {
                const text = exp.content ?? '';
                if (!text.length) {
                  continue;
                }
                const start = cursor - lineStart;
                const end = start + text.length;
                segments.push({
                  start,
                  end,
                  text,
                  scopes: normalizeScopes(exp.scopes),
                  color,
                  fontStyle
                });
                cursor += text.length;
              }
              continue;
            }

            const text = token.content ?? '';
            const start = tokenOffset - lineStart;
            const end = start + text.length;
            segments.push({
              start,
              end,
              text,
              scopes: [],
              color,
              fontStyle
            });
          }
          return { text: line, segments };
        })
      };

      const dest = path.join(
        FIXTURE_DIR,
        `shiki.${theme}.${fixture.file}.json`
      );
      writeJSON(dest, output);
      console.log('[shiki-fixtures] wrote', path.relative(ROOT_DIR, dest));
    }
  }
}

main().catch((error) => {
  console.error('[shiki-fixtures] failed:', error);
  process.exit(1);
});
