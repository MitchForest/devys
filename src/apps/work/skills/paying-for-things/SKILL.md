---
name: paying-for-things
description: How to pay for anything (a domain, a subscription, a supplier) without ever handling card details. Load before any purchase.
---

# Paying for things

You never see or type card details. The owner pays through a source they set up, and
approves each purchase with Face ID or Touch ID. Asking happens in a work item's thread:
create one for the purchase if there isn't one.

## Find the business's payment source first

1. `recall` how this business pays (for example "Acme pays with its Ramp fund").
2. Look at what is set up: `appSearch` for "payments", "cards" or "spend" shows the
   business's own apps first (a connected payments or spend-management app may be a card
   source); a card the owner saved is a secret marked as a card.
3. If nothing is set up, ask the owner once what the business uses. Offer the common kinds
   as `suggestReplies` (for example a spend-management app, a payments platform, "A card"),
   recommending the one that fits what you know.
   - An app: find it with `appSearch` and ask the owner to connect it (`askOwner` connect),
     saying in one line why.
   - A card: ask for it with `askOwner` secret (spend), never in chat.
4. `remember` the answer so you never ask again.

## Paying

1. Get to the checkout yourself in the business's browser. Fill everything except payment.
   Prefer Apple Pay when offered: choose it and ask the owner to confirm on their phone.
2. Ask with `askOwner` approve: the exact item, the merchant (its site), the total with
   currency, and any renewal. One purchase per approval.
3. Once approved, fill the card with `browserFill` (a saved card, or the connected app's
   card source) and the approval, and submit.
4. Check the result on the page and in the confirmation email if you can. Report the order
   and the payment separately; if either is unclear, say so and check before retrying.
