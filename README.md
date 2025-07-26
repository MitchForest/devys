# Devys

A next-generation IDE designed for AI-powered development that transforms the terminal-based coding experience into a modern, multi-agent development environment.

## 🚀 Quick Start

### Prerequisites
- [Bun](https://bun.sh) >= 1.0.0
- [Rust](https://rustup.rs/) (for Tauri)
- [Node.js](https://nodejs.org/) >= 18 (for some dependencies)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) >= 1.0.59
- Active Claude subscription

### Installation

```bash
# 1. Install Claude Code globally (if not already installed)
bun add -g @anthropic-ai/claude-code

# 2. Authenticate Claude Code (REQUIRED - one-time setup)
claude setup-token
# This will open your browser to authenticate with your Claude subscription

# 3. Install project dependencies
bun install

# Note: Claude Code uses its own authentication system
# No .env file or API keys are needed!
```

### Running the Application

**Option 1 - Run Everything (Recommended):**
```bash
# This runs both server and Tauri desktop app
bun run dev
```

**Option 2 - Run Components Separately:**

Terminal 1 - Backend Server:
```bash
# Start the backend server (required for API and WebSocket)
bun run server
# Server will run on http://localhost:3001
```

Terminal 2 - Desktop App:
```bash
# Start the Tauri desktop application
bun run desktop
# This will open the native desktop app
```

**Option 3 - Web Version Only (for testing):**
```bash
# Run server
bun run server

# In another terminal, run just Vite (web version)
cd apps/desktop && bun run dev
# Access at http://localhost:5173
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

## 🔧 Troubleshooting

### Claude Code Authentication Issues
If you get "Claude Code process exited with code 1":
1. Run `claude setup-token` to authenticate
2. Make sure you have an active Claude subscription
3. Try running `claude` in your terminal to verify it works

### Tauri Desktop App Not Opening
If the desktop app doesn't open:
1. Make sure Rust is installed: `rustc --version`
2. Check Tauri prerequisites: https://tauri.app/v1/guides/getting-started/prerequisites
3. Try running `bun run desktop` separately

### Session Documentation
Claude Code sessions are documented in the `.pm` folder:
- `.pm/index.md` - Session index
- `.pm/sessions/{id}/` - Individual session logs

## 📖 Documentation

- [Phase 1 Plan](.docs/phase-1.md)
- [Phase 1 Tracker](.docs/tracker-1.md)
- [Phase 2 Implementation](.docs/phase-2/implementation-plan.md)
- [Claude Code Authentication](.docs/phase-2/authentication-notes.md)
- [Product Requirements](.docs/prd.md)

## 🤝 Contributing

This is an open-source project. Contributions are welcome!

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.