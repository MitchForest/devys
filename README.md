# Devys

A next-generation IDE designed for AI-powered development that transforms the terminal-based coding experience into a modern, multi-agent development environment.

## 🚀 Quick Start

### Prerequisites
- [Bun](https://bun.sh) >= 1.0.0
- [Rust](https://rustup.rs/) (for Tauri)
- [Node.js](https://nodejs.org/) >= 18 (for some dependencies)

### Installation

```bash
# Install dependencies
bun install

# Create .env file from example and add your Anthropic API key
cp .env.example .env
# Edit .env and add your ANTHROPIC_API_KEY
```

### Running the Application

You need to run both the server and desktop app in separate terminals:

**Terminal 1 - Backend Server:**
```bash
# Start the backend server (required for API and WebSocket)
bun run server
# Server will run on http://localhost:3001
```

**Terminal 2 - Desktop App:**
```bash
# Start the desktop application
bun run desktop
# Desktop app will run on http://localhost:5173
```

**Alternative - Run both concurrently:**
```bash
# Install concurrently if needed
bun add -d concurrently

# Run both server and desktop
bunx concurrently "bun run server" "bun run desktop"
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
devys/
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