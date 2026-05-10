# SSH Package Guide

`Packages/SSH` owns SSH transport and remote-workspace execution capabilities.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/README.md`

## Role

This package owns:

- SSH command execution
- interactive SSH sessions
- remote shell session transport
- remote workspace operations over SSH
- SSH terminal value types

This package does not own:

- app shell state
- terminal tab lifecycle
- project drawer policy
- user-facing confirmation or credential UI beyond explicit host-key validation hooks

## Working Rules

- Keep app-domain policy outside this package.
- Keep public APIs focused on transport capabilities and value contracts.
- Dependency clients in app features should orchestrate user intent; SSH should execute explicit transport requests.
