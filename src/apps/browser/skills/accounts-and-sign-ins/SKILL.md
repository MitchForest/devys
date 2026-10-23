---
name: accounts-and-sign-ins
description: Create and use accounts (registrars, hosting, email, suppliers) in the business's name, hand sign-ins, 2FA and identity checks to the owner, and keep passwords out of notes. Load before signing up for or into any service.
---

# Accounts and sign-ins

## Whose account

- Create accounts in the business's name with the business's own email address (`recall` it;
  for Acme, something like ops@acme-widgets.com), never the owner's personal email or
  accounts, unless the owner told you to use one for this.
- Before creating one, check the business doesn't already have it: `recall`, then
  `secretList` for a saved password by the service's name. Ask the owner if unsure; two
  accounts for one service are hard to undo.
- A command-line tool on the Mac may be signed in to the owner's own account (for a hosting
  or cloud provider, say). That account is not automatically the business's: unless `recall`
  says the business uses it, ask before putting anything of the business's in it, saying
  which account it is.
- Accepting a service's terms on the business's behalf is part of the work only when the work
  item says so; otherwise ask (`askOwner` approve, naming the service and its terms).

## Record who owns it

After creating an account, `remember` the service, the sign-in email, who owns and administers
it (the business, with the owner as admin unless told otherwise) and what it is for. Add it to
the work item's results, for example `{ "label": "Account at Acme Hosting", "value":
"ops@acme-widgets.com, owner is admin", "ok": true }`.

## Passwords

- Never write a password, recovery code or API key in a note, memory, file, message or work
  item. A password lives only as a secret: if the business lacks one, `askOwner` secret with
  the name you will use (ACME_HOSTING_PASSWORD) and why; fill it with `browserFill`.
- When a service generates a key or recovery codes, ask the owner to take over and keep them
  (`askOwner` take_over), or save them as a secret the same way; never read them back.

## What only the owner can do

2FA codes, CAPTCHAs, identity or business verification, a phone or email code sent to the
owner, and a first sign-in to the business's browser are the owner's to do. Ask with
`askOwner` take_over, saying exactly what is needed and the page's address; carry on with
other work, and continue when it is handed back. Never ask for codes in chat.

## Signed in

The business's browser keeps its sign-ins. Prefer an existing session over signing in again,
and sign out only if the work asks for it.
