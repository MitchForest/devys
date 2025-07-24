# Claude Code IDE

A next-generation IDE specifically designed for Claude Code SDK that transforms the terminal-based AI coding experience into a modern, multi-agent development environment.

## 🚀 Quick Start

### Prerequisites
- [Bun](https://bun.sh) >= 1.0.0
- [Rust](https://rustup.rs/) (for Tauri)
- [Node.js](https://nodejs.org/) >= 18 (for some dependencies)

### Installation

```bash
# Install dependencies
bun install

# Run development server
bun run desktop

# Run the backend server
bun run server
```

### Development Commands

```bash
# Type check all packages
bun run typecheck

# Lint all packages
bun run lint

# Fix lint issues
bun run lint:fix

# Run both typecheck and lint
bun run check

# Clean all build artifacts
bun run clean
```

## 🏗️ Project Structure

```
claude-code-ide/
├── apps/
│   ├── desktop/          # Tauri desktop application
│   └── server/           # Hono backend server
├── packages/
│   ├── core/             # Shared business logic
│   ├── ui/               # Shared React components
│   └── types/            # TypeScript types & Zod schemas
└── configs/              # Configuration files
```

## 🛠️ Technology Stack

- **Runtime**: Bun
- **Desktop**: Tauri 2.0
- **Frontend**: React 19, Vite 5, TypeScript
- **Styling**: Tailwind CSS v4 + shadcn/ui
- **Backend**: Hono + WebSocket
- **Editor**: CodeMirror 6
- **Terminal**: xterm.js

## 📖 Documentation

- [Phase 1 Plan](.docs/phase-1.md)
- [Phase 1 Tracker](.docs/tracker-1.md)
- [Product Requirements](.docs/prd.md)

## 🤝 Contributing

This is an open-source project. Contributions are welcome!

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.