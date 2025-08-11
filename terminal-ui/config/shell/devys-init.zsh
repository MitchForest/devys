#!/usr/bin/env zsh
# Devys Shell Integration for Zsh
# Source this file in your ~/.zshrc: source ~/.config/devys/devys-init.zsh

# Initialize Devys environment
export DEVYS_HOME="${DEVYS_HOME:-$HOME/.config/devys}"
export DEVYS_CONTROL_PLANE_URL="${DEVYS_CONTROL_PLANE_URL:-http://localhost:3000}"
export DEVYS_SESSION_ID=$(uuidgen)

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
        PS1='%F{cyan}$(devys_status)%f %~ %# '
    else
        # Regular terminal
        PS1='%F{cyan}$(devys_status)%f %F{blue}%~%f %# '
    fi
fi

# Directory hooks for automatic context loading
chpwd() {
    # Call original chpwd functions if they exist
    if typeset -f chpwd_functions >/dev/null; then
        local f
        for f in $chpwd_functions; do
            $f
        done
    fi
    
    # Load Devys context if available
    if [[ -f .devys/context.yaml ]]; then
        devys-cli context load .devys/context.yaml >/dev/null 2>&1 &
    elif command -v devys-cli >/dev/null 2>&1; then
        # Auto-build context for the current directory
        devys-cli context build . >/dev/null 2>&1 &
    fi
}

# Completion for devys commands
if command -v devys-cli >/dev/null 2>&1; then
    # Load completions
    eval "$(devys-cli completion zsh)"
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
            devys-cli commands list --format simple 2>/dev/null || echo "ai-complete\nplan\nedit\nreview\nexplain\nfix"
            echo "--- Recent Commands ---"
            history | tail -20 | cut -c 8- | head -10
            echo "--- Project Files ---"
            devys-cli context files --with-scores 2>/dev/null || find . -type f -name "*.rs" -o -name "*.ts" -o -name "*.js" -o -name "*.py" | head -20
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

# Key bindings
if [[ "${DEVYS_KEYBINDINGS:-1}" == "1" ]]; then
    # Ctrl+Space for Devys command palette
    bindkey '^@' devys_fzf
    
    # Alt+a for AI completion
    bindkey '^[a' devys-ai-complete
    
    # Alt+p for planning
    bindkey '^[p' devys-plan-current
    
    # Alt+e for editing
    bindkey '^[e' devys-edit-current
    
    # Alt+r for review
    bindkey '^[r' devys-review-current
    
    # Alt+g for grunt tasks
    bindkey '^[g' devys-grunt-menu
fi

# Helper functions for key bindings
devys-ai-complete() {
    local current_line="$BUFFER"
    if [[ -n "$current_line" ]]; then
        local completion=$(devys-cli ai-complete --text "$current_line" 2>/dev/null)
        if [[ -n "$completion" ]]; then
            BUFFER="$completion"
            CURSOR=${#BUFFER}
        fi
    fi
    zle reset-prompt
}

devys-plan-current() {
    local selection
    if [[ -n "$BUFFER" ]]; then
        selection="$BUFFER"
    else
        selection="$(pwd)"
    fi
    devys-cli workflow plan "$selection"
    zle reset-prompt
}

devys-edit-current() {
    devys-cli workflow edit
    zle reset-prompt
}

devys-review-current() {
    devys-cli workflow review
    zle reset-prompt
}

devys-grunt-menu() {
    local task=$(echo "format\nlint\ntest\ncommit\ndocs" | fzf --prompt="Select grunt task: ")
    if [[ -n "$task" ]]; then
        devys-cli grunt "$task"
    fi
    zle reset-prompt
}

# Register functions as widgets
zle -N devys-ai-complete
zle -N devys-plan-current
zle -N devys-edit-current
zle -N devys-review-current
zle -N devys-grunt-menu
zle -N devys_fzf

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
    # Track command execution time
    devys_preexec() {
        devys_cmd_start_time=$SECONDS
    }
    
    devys_precmd() {
        if [[ -n "$devys_cmd_start_time" ]]; then
            local execution_time=$((SECONDS - devys_cmd_start_time))
            if [[ $execution_time -gt 5 ]]; then
                echo "Command took ${execution_time}s"
            fi
            unset devys_cmd_start_time
        fi
    }
    
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec devys_preexec
    add-zsh-hook precmd devys_precmd
fi

# Context auto-refresh (only if enabled)
if [[ "${DEVYS_AUTO_REFRESH:-0}" == "1" ]]; then
    devys_auto_refresh() {
        if command -v devys-cli >/dev/null 2>&1; then
            devys-cli context refresh >/dev/null 2>&1 &
        fi
    }
    
    # Refresh context every 30 seconds
    TMOUT=30
    TRAPALRM() {
        devys_auto_refresh
        TMOUT=30
    }
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

# Clean up temporary variables
unset DEVYS_TEMP_*