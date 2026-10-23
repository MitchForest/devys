---
name: shipping-code
description: Change a repository's code in a coding session and take it from accepted to live, verified on its URL. Load before changing, publishing, merging or deploying code, or putting a site live.
---

# Shipping code

Each stage is its own effect and its own claim: accepted, published (a pull request), checks
passed, merged, deployed, live. Show them as the work item's steps (`workUpdate`) so the owner
can watch, and never report a later stage than you have checked.

## Change code in a coding session

Every change to a repository, even one line, is made by a coding session (`codingStart` on the
repository, with a complete brief), never by editing its files yourself: the session's
worktree, check and accepted commit are what the owner approves and what is deployed. To put a
repository live as it is, start a session whose brief is to make it deployable (a production
deploy command, if it has none) and check it; accept it, then deploy that commit.

Hosting and its account belong to the business: `recall` where it hosts and in which account.
If that isn't known, ask once (`suggestReplies`, your recommendation first) before setting
anything up. A command-line tool already signed in on the Mac is the owner's own account,
not automatically the business's: before the first deploy into it, say which account it is
and ask whether the business should use it.

## From accepted to live

1. **Accept**: `codingAccept` the session. Its check must pass; if it fails, steer the session
   (`codingSend`) with what failed and accept again.
2. **Publish**: `codingPublish` opens the pull request (or returns the open one). Note its
   number and head commit. It needs the business's GitHub repository as the repository's
   origin: if there is none, say so and ask (`suggestReplies`) whether to create one for the
   business or to deploy the accepted commit without a pull request. Create nothing before the
   owner answers; without a pull request, skip to step 4 and ask only for the deploy.
3. **Wait for CI** without blocking: `gh pr checks <number>`. While checks run, set the work
   waiting with a follow-up (`workUpdate` state waiting, `waitCondition: "CI on the pull
request"`, `wakeAt` a few minutes ahead) and end your turn; you are handed it back. If a
   check fails, read its log (`gh run view <id> --log-failed`), fix it through the session,
   accept and publish again.
4. **Ask once**: with checks green, `askOwner` approve one combined action naming the exact
   commit and where it goes, with each step exactly (the deploy step as `deployProduction`
   says, so the approval covers it): `{ kind: "approve", action: "Merge pull request #12 and
deploy 3f2a9c1 to production", counterparty: "https://acme-widgets.com", steps: ["Merge pull
request #12 at 3f2a9c1", "Deploy 3f2a9c1 of acme-site to production"] }`. A new commit is a
   new request.
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
