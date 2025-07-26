# Claude Code Authentication

## Important: Claude Code Authentication

Claude Code **does NOT use the standard ANTHROPIC_API_KEY**. Instead, it has its own authentication system.

### How to Authenticate

1. **First-time setup**:
   ```bash
   claude setup-token
   ```
   This will:
   - Open your browser
   - Prompt you to log in with your Claude subscription
   - Store credentials securely (macOS: in Keychain)

2. **Check authentication**:
   ```bash
   claude /login
   ```
   This shows current account status and allows switching accounts.

### What This Means for Our Integration

1. **No API key in .env**: The `ANTHROPIC_API_KEY` in `.env.example` is not used by Claude Code
2. **User must authenticate**: Each user needs to run `claude setup-token` on their machine
3. **Credentials are stored locally**: Authentication persists across sessions

### Testing the Integration

1. **Authenticate Claude Code**:
   ```bash
   # Run this once per machine
   claude setup-token
   ```

2. **Start the server**:
   ```bash
   bun run server
   ```

3. **Test in UI**:
   ```bash
   bun run desktop
   ```
   Or run the full dev environment:
   ```bash
   bun run dev
   ```

4. **Test via script**:
   ```bash
   bun run test-chat-bun.ts
   ```

### Troubleshooting

If you get authentication errors:

1. **Run setup-token again**:
   ```bash
   claude setup-token
   ```

2. **Check Claude subscription**: You need an active Claude subscription

3. **Check credentials**:
   - On macOS: Stored in Keychain
   - Credentials refresh every 5 minutes or on HTTP 401

### Key Differences from Standard Anthropic API

| Feature | Standard API | Claude Code |
|---------|--------------|-------------|
| Authentication | API Key in env | Browser-based flow |
| Storage | .env file | OS Keychain |
| Setup | Export env var | `claude setup-token` |
| Multi-account | Switch API keys | `/login` command |

### Security Benefits

1. **No plaintext keys**: Credentials stored in OS secure storage
2. **Browser-based auth**: Standard OAuth-like flow
3. **Automatic refresh**: Credentials refresh automatically
4. **Per-machine auth**: Each developer authenticates their own machine

This is why our implementation doesn't set or use `ANTHROPIC_API_KEY` - Claude Code handles its own authentication!