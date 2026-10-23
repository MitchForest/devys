---
name: paying-for-things
description: How to pay for anything (a domain, a subscription, a supplier) without ever handling card details. Load before any purchase.
---

# Paying for things

You never see or type card details. The owner pays through a source they set up, and
approves each purchase with Face ID or Touch ID. `askOwner` asks from the purchase's work
item thread; a plain question (how the business pays) is asked where you are talking.

## Find the business's payment source first

1. `recall` how this business pays (for example "Acme pays with its Ramp fund").
2. Look at what is set up: `secretList` shows the cards the owner has saved, by name (never
   their numbers); `appSearch` for "payments", "cards" or "spend" shows the business's own
   apps first (a connected payments or spend-management app may be a card source). If one
   card is saved, use it; if several, ask which.
3. If nothing is set up, ask the owner once what the business uses. Offer concrete choices
   as `suggestReplies`, so one tap picks one: the two or three services you'd expect a
   business like this to pay through, by name, and "A card", your recommendation first.
4. `remember` the answer so you never ask again. Then create the purchase's work item if
   there isn't one (`workCreate`, saying how it will be paid, so its thread doesn't ask
   again; you continue there) and ask for the source from its thread:
   - An app: find it with `appSearch`. If it isn't listed, the service may publish its own
     MCP server: look up its address (https://…) in the service's own docs and pass that.
     Ask the owner to connect it (`askOwner` connect), saying in one line why.
   - A card: ask for it with `askOwner` secret (spend), never in chat.

## Paying

1. Get to the checkout yourself in the business's browser. Fill everything except payment.
   Prefer Apple Pay when offered: choose it and ask the owner to confirm on their phone.
2. Ask with `askOwner` approve: the exact item, the merchant (its site), the total with
   currency, and any renewal. One purchase per approval.
3. Once approved, fill the card with `browserFill` (a saved card, or the connected app's
   card source) and the approval, and submit.
4. Check the result on the page and in the confirmation email if you can. Report the order
   and the payment separately; if either is unclear, say so and check before retrying.
