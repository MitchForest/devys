---
name: checking-your-work
description: Prove each effect from outside (DNS, a live URL, an email delivered, a pull request's checks, a receipt) before saying it is done, then record it as the work item's results. Load before finishing any work that changed something outside Devys.
---

# Checking your work

A command that exited 0, a page that said "Success" or a reply from a tool is not proof. Check
each effect the way the owner, a customer or the internet would see it, from outside.

## Check each effect

- **DNS**: `dig +short acme-widgets.com A`, `dig +short MX acme-widgets.com`, `dig +short TXT
acme-widgets.com` (SPF, DKIM, verification records). New records can take minutes: check
  again before calling one missing.
- **A site or URL**: `curl -sSI https://acme-widgets.com` answers 200 (or the redirect you
  expect) over https with a valid certificate; `curl -s` and look for the text that should be
  there. Check the exact address you will give the owner.
- **Email**: send a test message to an address you can read and see it arrive (and not in
  spam); for a sending setup, check it from the receiving side.
- **Code**: `gh pr checks <number>` passes; merged is `gh pr view <number> --json state`;
  deployed is the live URL serving the new commit, not the deploy command's output.
- **A purchase**: the order on the merchant's site and the receipt email; the charge itself
  only where the payment source shows it.

## Report effects separately

An order is not a payment, a pull request is not a merge, and a merge is not a deploy. Say
each one on its own, as far as it got.

## Uncertain

When you cannot tell whether something happened (a timeout, a page that never loaded after
submitting, a payment that may have gone through), say so plainly. Check before retrying:
look for the order, the record or the charge first, so nothing is done twice.

## Record results

When the work changed something, record what you checked as the work item's results
(`workUpdate` while working, `workComplete` at the end), the whole list each time, at most 12:

```json
[
  { "label": "Registered acme-widgets.com", "value": "expires 2027-10-22", "ok": true },
  { "label": "Live at", "url": "https://acme-widgets.com", "ok": true },
  { "label": "MX records", "ok": true },
  { "label": "Test email delivered", "ok": true },
  { "label": "Payment", "value": "not shown yet", "ok": null }
]
```

`ok` is true when the check held, false when it failed and null when you could not tell;
leave it out for a plain fact. Links are https only. Use the owner's words, never commands.
