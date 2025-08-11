#!/usr/bin/env bash
# Devys Shell Integration for Bash
# Source this file in your ~/.bashrc: source ~/.config/devys/devys-init.bash

# Initialize Devys environment
export DEVYS_HOME="${DEVYS_HOME:-$HOME/.config/devys}"
export DEVYS_CONTROL_PLANE_URL="${DEVYS_CONTROL_PLANE_URL:-http://localhost:3000}"
export DEVYS_SESSION_ID=$(uuidgen 2>/dev/null || date +%s%N)

# Add devys binaries to PATH
if [[ -d "$DEVYS_HOME/bin" ]]; then
    export PATH="$DEVYS_HOME/bin:$PATH"
fi

# Devys status function for prompt
devys_status() {
    if command -v devys-cli >/dev/null 2>&1; then
        local status_output=$(devys-cli status --format=compact 2>/dev/null)
        if [[ $? -eq 0 && -n "$status_output" ]]; then
            echo "[$status_output]"
        fi
    fi
}

# Enhanced prompt with AI status
if [[ -z "$DEVYS_PROMPT_DISABLED" ]]; then
    # Save original prompt
    DEVYS_ORIGINAL_PS1="$PS1"
    
    # Create new prompt with Devys status
    if [[ "$TERM" == "screen"* ]] || [[ "$TERM" == "tmux"* ]] || [[ -n "$ZELLIJ" ]]; then
        # Inside multiplexer - minimal prompt
        PS1='\[\033[36m\]$(devys_status)\[\033[0m\] \w \$ '
    else
        # Regular terminal
        PS1='\[\033[36m\]$(devys_status)\[\033[0m\] \[\033[34m\]\w\[\033[0m\] \$ '
    fi
fi

# Directory change hook for automatic context loading
devys_cd_hook() {
    # Load Devys context if available
    if [[ -f .devys/context.yaml ]]; then
        devys-cli context load .devys/context.yaml >/dev/null 2>&1 &
    elif command -v devys-cli >/dev/null 2>&1; then
        # Auto-build context for the current directory
        devys-cli context build . >/dev/null 2>&1 &
    fi
}

# Override cd to include hook
cd() {
    builtin cd "$@"
    devys_cd_hook
}

# Also hook into pushd and popd
pushd() {
    builtin pushd "$@"
    devys_cd_hook
}

popd() {
    builtin popd "$@"
    devys_cd_hook
}

# Completion for devys commands
if command -v devys-cli >/dev/null 2>&1; then
    # Load completions if available
    eval "$(devys-cli completion bash 2>/dev/null || true)"
fi

# Aliases for common Devys operations
alias dai="devys-cli ai"
alias dplan="devys-cli workflow plan"
alias dedit="devys-cli workflow edit"
alias dreview="devys-cli workflow review"
alias dgrunt="devys-cli grunt"
alias dcontext="devys-cli context"
alias dstatus="devys-cli status"
alias dmodels="devys-cli models"
alias dcost="devys-cli cost"

# AI-powered aliases
alias explain="devys-cli explain"
alias fix="devys-cli fix"
alias refactor="devys-cli refactor"
alias generate="devys-cli generate"
alias optimize="devys-cli optimize"

# Git integration with AI
alias gai="devys-cli git"
alias gcommit="devys-cli git commit-message"
alias gpush="devys-cli git push-with-ai"
alias greview="devys-cli git review"

# FZF integration for enhanced search
devys_fzf() {
    local cmd
    cmd=$(
        {
            echo "--- AI Commands ---"
            devys-cli commands list --format simple 2>/dev/null || echo -e "ai-complete\nplan\nedit\nreview\nexplain\nfix"
            echo "--- Recent Commands ---"
            history | tail -20 | cut -c 8- | head -10
            echo "--- Project Files ---"
            devys-cli context files --with-scores 2>/dev/null || find . -type f \( -name "*.rs" -o -name "*.ts" -o -name "*.js" -o -name "*.py" \) | head -20
        } | fzf \
            --preview 'devys-cli explain {} 2>/dev/null || echo "No explanation available"' \
            --preview-window right:50% \
            --bind 'ctrl-a:execute(devys-cli ai-complete {})' \
            --bind 'ctrl-p:execute(devys-cli plan {})' \
            --bind 'ctrl-e:execute(devys-cli edit {})' \
            --bind 'ctrl-r:execute(devys-cli review {})' \
            --header 'ctrl-a: AI complete | ctrl-p: Plan | ctrl-e: Edit | ctrl-r: Review'
    )
    
    if [[ -n "$cmd" ]]; then
        if [[ "$cmd" == "--- "* ]]; then
            return 0  # Skip section headers
        fi
        
        # Execute the command
        if command -v devys-cli >/dev/null 2>&1; then
            devys-cli exec "$cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Helper functions for readline bindings
devys-ai-complete() {
    local current_line="$READLINE_LINE"
    if [[ -n "$current_line" ]]; then
        local completion=$(devys-cli ai-complete --text "$current_line" 2>/dev/null)
        if [[ -n "$completion" ]]; then
            READLINE_LINE="$completion"
            READLINE_POINT=${#READLINE_LINE}
        fi
    fi
}

devys-plan-current() {
    local selection
    if [[ -n "$READLINE_LINE" ]]; then
        selection="$READLINE_LINE"
    else
        selection="$(pwd)"
    fi
    devys-cli workflow plan "$selection"
}

devys-edit-current() {
    devys-cli workflow edit
}

devys-review-current() {
    devys-cli workflow review
}

devys-grunt-menu() {
    local task=$(echo -e "format\nlint\ntest\ncommit\ndocs" | fzf --prompt="Select grunt task: ")
    if [[ -n "$task" ]]; then
        devys-cli grunt "$task"
    fi
}

# Key bindings for Bash readline
if [[ "${DEVYS_KEYBINDINGS:-1}" == "1" ]]; then
    # Bind Ctrl+Space to Devys FZF (using Ctrl+@ which is equivalent)
    bind -x '"\C-@": devys_fzf'
    
    # Alt key bindings (using escape sequences)
    bind -x '"\ea": devys-ai-complete'      # Alt+a
    bind -x '"\ep": devys-plan-current'     # Alt+p  
    bind -x '"\ee": devys-edit-current'     # Alt+e
    bind -x '"\er": devys-review-current'   # Alt+r
    bind -x '"\eg": devys-grunt-menu'       # Alt+g
fi

# Environment detection and optimization
if [[ -n "$ZELLIJ" ]]; then
    export DEVYS_MULTIPLEXER="zellij"
    export DEVYS_SESSION="$ZELLIJ_SESSION_NAME"
elif [[ -n "$TMUX" ]]; then
    export DEVYS_MULTIPLEXER="tmux"
    export DEVYS_SESSION="$(tmux display-message -p '#S')"
else
    export DEVYS_MULTIPLEXER="none"
    export DEVYS_SESSION="terminal"
fi

# Performance monitoring
if [[ "${DEVYS_PERFORMANCE_MONITORING:-0}" == "1" ]]; then
    # Track command execution time using DEBUG trap
    devys_cmd_start_time=""
    
    devys_preexec() {
        devys_cmd_start_time=$(date +%s)
    }
    
    devys_precmd() {
        if [[ -n "$devys_cmd_start_time" ]]; then
            local execution_time=$(($(date +%s) - devys_cmd_start_time))
            if [[ $execution_time -gt 5 ]]; then
                echo "Command took ${execution_time}s"
            fi
            devys_cmd_start_time=""
        fi
    }
    
    # Set up the DEBUG trap to call preexec
    trap 'devys_preexec' DEBUG
    
    # Add precmd to PROMPT_COMMAND
    if [[ -n "$PROMPT_COMMAND" ]]; then
        PROMPT_COMMAND="$PROMPT_COMMAND; devys_precmd"
    else
        PROMPT_COMMAND="devys_precmd"
    fi
fi

# Context auto-refresh (only if enabled)
if [[ "${DEVYS_AUTO_REFRESH:-0}" == "1" ]]; then
    devys_auto_refresh() {
        if command -v devys-cli >/dev/null 2>&1; then
            devys-cli context refresh >/dev/null 2>&1 &
        fi
    }
    
    # Add to PROMPT_COMMAND to refresh every prompt
    if [[ -n "$PROMPT_COMMAND" ]]; then
        PROMPT_COMMAND="$PROMPT_COMMAND; devys_auto_refresh"
    else
        PROMPT_COMMAND="devys_auto_refresh"
    fi
fi

# Startup message (only show once per session)
if [[ -z "$DEVYS_INIT_SHOWN" && "${DEVYS_QUIET:-0}" != "1" ]]; then
    export DEVYS_INIT_SHOWN=1
    
    if command -v devys-cli >/dev/null 2>&1; then
        echo "🚀 Devys AI Development Environment initialized"
        echo "   Use Ctrl+Space for command palette, or type 'dai help' for commands"
        
        # Show status if available
        local status=$(devys-cli status --format=oneline 2>/dev/null)
        if [[ -n "$status" ]]; then
            echo "   Status: $status"
        fi
    else
        echo "⚠️  Devys CLI not found. Please install Devys first."
    fi
fi