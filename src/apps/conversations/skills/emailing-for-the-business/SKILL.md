---
name: emailing-for-the-business
description: Send email for the business (to a supplier, customer or anyone outside it) from the business's own address, with the owner's approval of the exact draft and recipients. Load before writing to anyone outside the business.
---

# Emailing for the business

Email goes out from the business's own address, never from the owner's personal mail (the
Mac's Mail app, a personal Gmail) unless the owner told you to use it for this.

## Find how the business sends email first

1. `recall` how this business does email and its address (for example "Acme uses Google
   Workspace; hello@acme-widgets.com").
2. Look at what is set up: `appSearch` for "email" or "mail" shows a connected mail app;
   the business's browser may already be signed in to its webmail.
3. If nothing is set up, ask the owner once how the business does email. Offer the
   providers you'd expect a business like this to use, by name, and "No business email
   yet", as `suggestReplies`, your recommendation first. `remember` the answer.
   - A provider: connect its app (`askOwner` connect) where one exists, otherwise send from
     its webmail in the business's browser (the owner signs in once with `askOwner`
     take_over).
   - No business email yet: say what you would set up first, and offer to send this one
     another way the owner chooses.

Ask this before writing out the whole email: one question, then wait.

## Draft, then ask once

1. Create the work item if there isn't one (`workCreate`), saying who it goes to and why;
   continue in its thread.
2. Write the draft as a file in the business folder (`drafts/<short-name>.md`): To, CC,
   Subject, then the body. In chat, say who it goes to and what it asks in a sentence; the
   owner reads the draft in the preview.
3. `askOwner` approve with action `Send "<subject>" to <to>, CC <cc>` (every recipient
   exactly), counterparty the recipient, and `preview` the draft's file ref
   (`devys:documents/file/` and its percent-encoded absolute path). Changing the draft or a
   recipient is a new request.

## Send and check

Send exactly the approved draft to exactly those recipients. Check it from outside: it is in
the Sent folder, and a CC'd owner received it. Record it as the work item's results, then
set the item waiting for the reply (`workUpdate` with `wakeAt` a few days ahead) so you look
again. A reply belongs to the same work item.
