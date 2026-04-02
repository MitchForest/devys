#!/usr/bin/env node
// Sync DevysSyntax grammars/themes with Shiki bundled assets.

import { execSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const GRAMMAR_DIR = path.join(
  ROOT_DIR,
  'Packages/Syntax/Sources/Syntax/Resources/Grammars'
);
const THEME_DIR = path.join(
  ROOT_DIR,
  'Packages/Syntax/Sources/Syntax/Resources/Themes'
);

const LANGUAGE_IDS = [
  'swift',
  'python',
  'javascript',
  'typescript',
  'tsx',
  'jsx',
  'html',
  'css',
  'json',
  'yaml',
  'markdown',
  'ruby',
  'rust',
  'c',
  'cpp',
  'go',
  'php',
  'java',
  'csharp',
  'lua',
  'kotlin',
  'make',
  'shellscript',
];

const THEME_IDS = [
  'github-dark',
  'github-dark-dimmed',
  'github-light',
  'vitesse-dark',
  'vitesse-light',
  'one-dark-pro',
  'tokyo-night',
  'dracula',
  'nord',
  'monokai',
  'catppuccin-mocha',
  'catppuccin-latte',
];

const SHIKI_VERSION = process.env.DEVYS_SHIKI_VERSION ?? '3.20.0';
const SHIKI_NODE_MODULES = process.env.DEVYS_SHIKI_NODE_MODULES;

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function writeJSON(dest, data) {
  const payload = JSON.stringify(data, null, 2) + '\n';
  fs.writeFileSync(dest, payload);
}

function resolveLanguageInfo(infoList, id) {
  if (infoList.find((entry) => entry.id === id)) {
    return infoList.find((entry) => entry.id === id);
  }
  return infoList.find((entry) => entry.aliases?.includes(id));
}

function mapLanguageId(id) {
  if (id === 'plaintext') {
    return 'text';
  }
  return id;
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
    stdio: 'inherit',
  });

  const shikiEntry = path.join(tempDir, 'node_modules/shiki/dist/index.mjs');
  return import(pathToFileURL(shikiEntry).href);
}

async function main() {
  ensureDir(GRAMMAR_DIR);
  ensureDir(THEME_DIR);

  const shiki = await loadShiki();
  const { bundledLanguagesInfo, bundledThemesInfo } = shiki;

  const grammarResults = [];
  for (const id of LANGUAGE_IDS) {
    const shikiId = mapLanguageId(id);
    const info = resolveLanguageInfo(bundledLanguagesInfo, shikiId);
    if (!info) {
      console.warn(`[shiki-sync] Missing language: ${id}`);
      continue;
    }

    const module = await info.import();
    const candidates = Array.isArray(module.default)
      ? module.default
      : [module.default];
    const grammar =
      candidates.find((entry) => entry?.name === shikiId) ??
      candidates.find((entry) => entry?.aliases?.includes?.(shikiId)) ??
      candidates[0];
    if (!grammar) {
      console.warn(`[shiki-sync] Empty grammar for: ${id}`);
      continue;
    }

    const dest = path.join(GRAMMAR_DIR, `${id}.json`);
    writeJSON(dest, grammar);
    grammarResults.push(dest);
  }

  const themeResults = [];
  for (const id of THEME_IDS) {
    const info = bundledThemesInfo.find((entry) => entry.id === id);
    if (!info) {
      console.warn(`[shiki-sync] Missing theme: ${id}`);
      continue;
    }

    const module = await info.import();
    const theme = module.default ?? module;
    if (!theme) {
      console.warn(`[shiki-sync] Empty theme for: ${id}`);
      continue;
    }

    const dest = path.join(THEME_DIR, `${id}.json`);
    writeJSON(dest, theme);
    themeResults.push(dest);
  }

  console.log('[shiki-sync] Updated grammars:', grammarResults.length);
  grammarResults.forEach((entry) => console.log(` - ${path.relative(ROOT_DIR, entry)}`));
  console.log('[shiki-sync] Updated themes:', themeResults.length);
  themeResults.forEach((entry) => console.log(` - ${path.relative(ROOT_DIR, entry)}`));
}

main().catch((error) => {
  console.error('[shiki-sync] Failed:', error);
  process.exit(1);
});
