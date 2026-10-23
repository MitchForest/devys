---
name: shipping-code
description: Take a coding session's work from accepted to live, verified on its URL. Load before publishing, merging or deploying code.
---

# Shipping code

Each stage is its own effect and its own claim: accepted, published (a pull request), checks
passed, merged, deployed, live. Show them as the work item's steps (`workUpdate`) so the owner
can watch, and never report a later stage than you have checked.

1. **Accept**: `codingAccept` the session. Its check must pass; if it fails, steer the session
   (`codingSend`) with what failed and accept again.
2. **Publish**: `codingPublish` opens the pull request (or returns the open one). Note its
   number and head commit.
3. **Wait for CI** without blocking: `gh pr checks <number>`. While checks run, set the work
   waiting with a follow-up (`workUpdate` state waiting, `waitCondition: "CI on the pull
request"`, `wakeAt` a few minutes ahead) and end your turn; you are handed it back. If a
   check fails, read its log (`gh run view <id> --log-failed`), fix it through the session,
   accept and publish again.
4. **Ask once**: with checks green, `askOwner` approve one combined action naming the exact
   commit and where it goes: `{ kind: "approve", action: "Merge pull request #12 and deploy
3f2a9c1 to production", counterparty: "https://acme-widgets.com" }`. A new commit is a new
   request.
5. **Merge** only the commit the owner approved:
   `gh pr merge <number> --match-head-commit <full sha> --squash` (or the repository's usual
   method). If the head moved, stop: that is a different commit.
6. **Deploy** that commit: `deployProduction` with the session's ref and the commit. The
   result arrives in the thread.
7. **Verify live** from outside (see checking-your-work): `curl -sSI <url>`, then the page
   or endpoint the change touched, ideally showing the new commit or behaviour.
8. **Record results** and complete:

```json
[
  { "label": "Pull request #12", "url": "https://github.com/acme/site/pull/12", "ok": true },
  { "label": "Checks", "value": "passed", "ok": true },
  { "label": "Merged", "value": "3f2a9c1", "ok": true },
  { "label": "Live at", "url": "https://acme-widgets.com", "ok": true }
]
```

If a deploy's outcome is unclear, check the live URL before deploying again. To roll back,
deploy the earlier commit this work item deployed, and say so.
