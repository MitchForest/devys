#!/bin/bash
set -euo pipefail

# Devys Phase 4 Terminal UI Installation Script
# This script installs the complete terminal-first AI development environment

DEVYS_VERSION="0.4.0"
DEVYS_HOME="${DEVYS_HOME:-$HOME/.config/devys}"
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$INSTALL_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    local missing_deps=()
    
    # Required tools
    for cmd in cargo rustc node npm git; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Optional but recommended tools
    local recommended=()
    for cmd in zellij helix yazi fzf ripgrep fd; do
        if ! command_exists "$cmd"; then
            recommended+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install the missing dependencies and run this script again."
        return 1
    fi
    
    if [[ ${#recommended[@]} -gt 0 ]]; then
        log_warning "Missing recommended tools: ${recommended[*]}"
        log_info "These tools are not required but will enhance your experience."
    fi
    
    log_success "System requirements check passed"
    return 0
}

# Install Rust dependencies
install_rust_deps() {
    log_info "Installing Rust dependencies..."
    
    # Install required Rust targets
    rustup target add wasm32-wasi 2>/dev/null || true
    
    # Install required tools
    if ! command_exists wasm-opt; then
        log_info "Installing wabt (WebAssembly Binary Toolkit)..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command_exists brew; then
                brew install wabt
            else
                log_warning "Homebrew not found. Please install wabt manually."
            fi
        elif [[ "$OSTYPE" == "linux"* ]]; then
            if command_exists apt; then
                sudo apt update && sudo apt install -y wabt
            elif command_exists yum; then
                sudo yum install -y wabt
            else
                log_warning "Package manager not supported. Please install wabt manually."
            fi
        fi
    fi
    
    log_success "Rust dependencies installed"
}

# Install terminal tools
install_terminal_tools() {
    log_info "Installing terminal tools..."
    
    # Install tools based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command_exists brew; then
            log_info "Installing via Homebrew..."
            brew install zellij helix yazi fzf ripgrep fd-find
        else
            log_warning "Homebrew not found. Please install terminal tools manually:"
            log_warning "  - zellij: Terminal multiplexer"
            log_warning "  - helix: Modal text editor" 
            log_warning "  - yazi: Terminal file manager"
            log_warning "  - fzf: Fuzzy finder"
            log_warning "  - ripgrep: Fast grep alternative"
            log_warning "  - fd: Fast find alternative"
        fi
    elif [[ "$OSTYPE" == "linux"* ]]; then
        if command_exists apt; then
            log_info "Installing via apt..."
            sudo apt update
            sudo apt install -y fzf ripgrep fd-find
            
            # Install newer tools via cargo if not available
            if ! command_exists zellij; then
                cargo install zellij
            fi
            if ! command_exists helix; then
                cargo install helix-term
            fi
            if ! command_exists yazi; then
                cargo install --locked yazi-fm
            fi
        else
            log_warning "Using cargo to install terminal tools..."
            cargo install zellij helix-term yazi-fm
        fi
    else
        log_info "Using cargo to install terminal tools..."
        cargo install zellij helix-term yazi-fm
    fi
    
    log_success "Terminal tools installation completed"
}

# Setup directories
setup_directories() {
    log_info "Setting up Devys directories..."
    
    mkdir -p "$DEVYS_HOME"/{bin,config,plugins,logs,cache}
    mkdir -p "$HOME/.config"/{zellij,helix,yazi}
    
    log_success "Directories created"
}

# Build Zellij plugins
build_plugins() {
    log_info "Building Zellij plugins..."
    
    cd "$PROJECT_ROOT/plugins"
    
    # Build all plugins
    cargo build --release --target wasm32-wasi
    
    # Optimize and install plugins
    for plugin in ai-command grunt-status context-viz; do
        local wasm_file="target/wasm32-wasi/release/$(echo $plugin | tr '-' '_')_plugin.wasm"
        local output_file="$HOME/.config/zellij/plugins/$plugin.wasm"
        
        if [[ -f "$wasm_file" ]]; then
            if command_exists wasm-opt; then
                wasm-opt -O "$wasm_file" -o "$output_file"
            else
                cp "$wasm_file" "$output_file"
            fi
            log_success "Built and installed plugin: $plugin"
        else
            log_warning "Plugin build failed: $plugin"
        fi
    done
    
    cd "$PROJECT_ROOT"
}

# Build LSP server
build_lsp_server() {
    log_info "Building Devys LSP server..."
    
    cd "$PROJECT_ROOT/lsp"
    cargo build --release
    
    # Install binary
    cp target/release/devys-lsp "$DEVYS_HOME/bin/"
    chmod +x "$DEVYS_HOME/bin/devys-lsp"
    
    log_success "LSP server built and installed"
    cd "$PROJECT_ROOT"
}

# Build context TUI
build_context_tui() {
    log_info "Building Devys Context TUI..."
    
    cd "$PROJECT_ROOT/tui"
    cargo build --release
    
    # Install binary
    cp target/release/devys-context "$DEVYS_HOME/bin/"
    chmod +x "$DEVYS_HOME/bin/devys-context"
    
    log_success "Context TUI built and installed"
    cd "$PROJECT_ROOT"
}

# Build main terminal UI
build_terminal_ui() {
    log_info "Building Devys Terminal UI core..."
    
    cd "$PROJECT_ROOT"
    cargo build --release
    
    # Install binary
    cp target/release/devys-core "$DEVYS_HOME/bin/"
    chmod +x "$DEVYS_HOME/bin/devys-core"
    
    log_success "Terminal UI core built and installed"
}

# Install configurations
install_configurations() {
    log_info "Installing configurations..."
    
    # Zellij layout
    cp "$PROJECT_ROOT/config/zellij/devys-layout.kdl" "$HOME/.config/zellij/"
    
    # Helix configuration
    cp "$PROJECT_ROOT/config/helix/config.toml" "$HOME/.config/helix/"
    cp "$PROJECT_ROOT/config/helix/languages.toml" "$HOME/.config/helix/"
    
    # Shell integration scripts
    cp "$PROJECT_ROOT/config/shell/"* "$DEVYS_HOME/"
    
    log_success "Configurations installed"
}

# Setup shell integration
setup_shell_integration() {
    log_info "Setting up shell integration..."
    
    local shell_name=$(basename "$SHELL")
    local init_file=""
    local rc_file=""
    
    case "$shell_name" in
        zsh)
            init_file="$DEVYS_HOME/devys-init.zsh"
            rc_file="$HOME/.zshrc"
            ;;
        bash)
            init_file="$DEVYS_HOME/devys-init.bash"
            rc_file="$HOME/.bashrc"
            ;;
        *)
            log_warning "Unsupported shell: $shell_name"
            log_info "You can manually source the appropriate init script:"
            log_info "  - Bash: source $DEVYS_HOME/devys-init.bash"
            log_info "  - Zsh:  source $DEVYS_HOME/devys-init.zsh"
            return
            ;;
    esac
    
    # Check if already integrated
    if grep -q "devys-init" "$rc_file" 2>/dev/null; then
        log_info "Shell integration already present in $rc_file"
    else
        log_info "Adding Devys integration to $rc_file"
        echo "" >> "$rc_file"
        echo "# Devys AI Development Environment" >> "$rc_file"
        echo "source $init_file" >> "$rc_file"
        log_success "Shell integration added"
    fi
    
    # Add to PATH
    if ! echo "$PATH" | grep -q "$DEVYS_HOME/bin"; then
        log_info "Adding $DEVYS_HOME/bin to PATH"
        echo "export PATH=\"$DEVYS_HOME/bin:\$PATH\"" >> "$rc_file"
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check binaries
    for binary in devys-core devys-lsp devys-context; do
        if [[ -x "$DEVYS_HOME/bin/$binary" ]]; then
            log_success "Binary installed: $binary"
        else
            log_error "Binary missing: $binary"
            ((errors++))
        fi
    done
    
    # Check plugins
    for plugin in ai-command grunt-status context-viz; do
        if [[ -f "$HOME/.config/zellij/plugins/$plugin.wasm" ]]; then
            log_success "Plugin installed: $plugin"
        else
            log_error "Plugin missing: $plugin"
            ((errors++))
        fi
    done
    
    # Check configurations
    for config in "$HOME/.config/zellij/devys-layout.kdl" "$HOME/.config/helix/config.toml"; do
        if [[ -f "$config" ]]; then
            log_success "Configuration installed: $(basename "$config")"
        else
            log_error "Configuration missing: $config"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "Installation verification passed!"
        return 0
    else
        log_error "Installation verification failed with $errors errors"
        return 1
    fi
}

# Create desktop entry (Linux only)
create_desktop_entry() {
    if [[ "$OSTYPE" == "linux"* ]]; then
        log_info "Creating desktop entry..."
        
        cat > "$HOME/.local/share/applications/devys.desktop" << EOF
[Desktop Entry]
Name=Devys AI Development Environment
Comment=Terminal-first AI-powered development environment
Exec=$DEVYS_HOME/bin/devys-core
Icon=terminal
Terminal=true
Type=Application
Categories=Development;IDE;
EOF
        
        log_success "Desktop entry created"
    fi
}

# Main installation function
main() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║  Devys Phase 4: Terminal UI Integration Installation        ║"
    echo "║  Version: $DEVYS_VERSION                                           ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    log_info "Starting Devys Phase 4 installation..."
    log_info "Installation directory: $DEVYS_HOME"
    
    # Check requirements
    if ! check_requirements; then
        exit 1
    fi
    
    # Install dependencies
    install_rust_deps
    install_terminal_tools
    
    # Setup
    setup_directories
    
    # Build components
    build_plugins
    build_lsp_server
    build_context_tui
    build_terminal_ui
    
    # Install configurations
    install_configurations
    
    # Setup shell integration
    setup_shell_integration
    
    # Create desktop entry
    create_desktop_entry
    
    # Verify installation
    if verify_installation; then
        echo -e "${GREEN}"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                                                              ║"
        echo "║  🎉 Devys Phase 4 Installation Complete! 🎉                ║"
        echo "║                                                              ║"
        echo "║  Next steps:                                                 ║"
        echo "║  1. Restart your terminal or run: source ~/.${shell_name:-bash}rc        ║"
        echo "║  2. Start Devys: devys-core                                  ║"
        echo "║  3. Launch Zellij session with Devys layout                 ║"
        echo "║                                                              ║"
        echo "║  Key bindings:                                               ║"
        echo "║  - Ctrl+Space: AI command palette                           ║"
        echo "║  - Alt+a: AI completion                                      ║"
        echo "║  - Alt+p: Plan with AI                                       ║"
        echo "║  - Alt+e: Edit with AI                                       ║"
        echo "║  - Alt+r: Review with AI                                     ║"
        echo "║                                                              ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        
        log_info "For help and documentation, run: devys-core --help"
        log_info "Join our community: https://github.com/devys/devys"
    else
        log_error "Installation completed with errors. Please check the output above."
        exit 1
    fi
}

# Run installation
main "$@"