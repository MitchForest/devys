---
name: using-the-browser
description: Drive the business's own browser with browserScript (DevTools Protocol commands), browserScreenshot and browserTabs to open and read pages, click and type by coordinates, upload files, and work in frames and tabs; fill passwords and cards with browserFill.
---

# Using the browser

The business's browser is Chrome on the business's own profile: the owner signed in to the
business's sites there once, so you are signed in too. The owner can watch it and take over;
when they do, your commands stop until they hand it back.

`browserScript` runs a JavaScript snippet with `session`, which sends any Chrome DevTools
Protocol command (`session.<Domain>.<method>(params)`, parameters exactly as the protocol
documents them) to the current tab. There are no click or goto helpers: the protocol is the
API. Await every call. A single expression is the result; otherwise `return` one, small (the
fields you need, not whole documents). Each script starts fresh; the current tab persists.

The loop: look with `browserScreenshot`, act with one short script, look again.

## Open a page and wait for it

```js
const loaded = session.waitFor("Page.loadEventFired");
await session.Page.navigate({ url: "https://example.com/orders" });
await loaded;
```

`session.waitFor(event, predicate?, timeoutMs?)` waits for an event after your last command.
Only http and https pages open; never `file://`.

## Read the page

```js
(
  await session.Runtime.evaluate({
    expression: `[...document.querySelectorAll("table tr")].map((row) => row.innerText)`,
    returnByValue: true,
  })
).result.value;
```

Use `awaitPromise: true` for an expression that returns a promise. Prefer reading text and
structure over guessing from a screenshot; use the screenshot to find where things are.

## Click and type

A screenshot is in CSS pixels: a point in it is the `x`, `y` to click. Coordinate clicks pass
through frames and shadow DOM.

```js
const at = { x: 412, y: 230, button: "left", clickCount: 1 };
await session.Input.dispatchMouseEvent({ type: "mousePressed", ...at });
await session.Input.dispatchMouseEvent({ type: "mouseReleased", ...at });
await session.Input.insertText({ text: "Quarterly report" });
await session.Input.dispatchKeyEvent({
  type: "keyDown",
  key: "Enter",
  code: "Enter",
  windowsVirtualKeyCode: 13,
  text: "\r",
});
await session.Input.dispatchKeyEvent({
  type: "keyUp",
  key: "Enter",
  code: "Enter",
  windowsVirtualKeyCode: 13,
});
```

To click an element you found in the DOM, get its centre first:

```js
(
  await session.Runtime.evaluate({
    expression: `(() => { const r = document.querySelector("button[type=submit]").getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; })()`,
    returnByValue: true,
  })
).result.value;
```

Scroll with `Input.dispatchMouseEvent({ type: "mouseWheel", x, y, deltaX: 0, deltaY: 600 })`.

## Upload a file

Never click a file input (it opens a dialog the protocol cannot close). Set its files; paths
are absolute and in the business's folder.

```js
const { root } = await session.DOM.getDocument({ depth: -1 });
const { nodeId } = await session.DOM.querySelector({
  nodeId: root.nodeId,
  selector: 'input[type="file"]',
});
await session.DOM.setFileInputFiles({ nodeId, files: ["/Users/…/Devys/<business>/invoice.pdf"] });
```

Downloads land in the business folder's `Downloads`.

## Frames

A same-origin frame is part of the page: reach it with
`document.querySelector("iframe").contentDocument`. A cross-origin frame (payments, captchas,
embedded apps) has its own target: click it by coordinates, or route commands to it and back.

```js
const { targetInfos } = await session.Target.getTargets({});
const frame = targetInfos.find((t) => t.type === "iframe" && t.url.includes("checkout"));
await session.use(frame.targetId);
const value = (
  await session.Runtime.evaluate({ expression: "document.title", returnByValue: true })
).result.value;
await session.use((await listPageTargets()).find((t) => t.current).targetId);
return value;
```

## Tabs

`browserTabs` lists, switches to, opens and closes tabs; the current one is what scripts,
screenshots and the owner's live view show. A link that opens a new tab does not switch:
list the tabs and switch to it.

## Dialogs

`alert` and `confirm` freeze the page. Answer with
`session.Page.handleJavaScriptDialog({ accept: true })`.

## Passwords and cards: browserFill

Never type a password or card yourself. `browserFill` types a secret the business holds by name,
and you never see it:

- A password (or any secret): `{ secret: "SHOP_PASSWORD", fields: [{ selector: "#password",
part: "value" }] }`.
- A card: first `askOwner` `{ kind: "approve", action, counterparty: "<merchant's site, e.g.
namecheap.com>", amount: { cents, currency } }` in the work item's thread, with the total you
  see at checkout. Once it is approved, fill on that site's checkout with its request id:
  `{ secret: "RAMP_CARD", approval: "<request id>", fields: [{ selector: "#name", part: "name" },
{ target: "<payment frame>", selector: "input[name=cardnumber]", part: "number" }, { target,
selector: "input[name=exp-date]", part: "expiry" }, { target, selector: "input[name=cvc]",
part: "cvc" }, { selector: "#zip", part: "postal" }], submit: { selector: "#pay" } }`.
  Parts: number, expiry (MM/YY), month, year, cvc, name, postal. A field inside a payment
  provider's frame (Stripe, Adyen) names that frame's target id from `listPageTargets` /
  `Target.getTargets`; a field can also be a point `{ x, y }` read from a screenshot.
- One approval is one fill. Afterwards the page is hidden from you until it moves on (at most two
  minutes): wait, then take a screenshot to see the result. If the business lacks the secret,
  ask with `askOwner` `{ kind: "secret", name, why, spend? }`.

## Care

- Clicking and typing can submit, buy or send. Do only what the work allows, and read the
  page before a consequential click.
- Never type passwords, codes or card numbers: use `browserFill`, or for a sign-in with 2FA or a
  CAPTCHA ask the owner to take over (`askOwner` take_over).
- If a command is refused, read the message: it says what the browser allows.

Recipes adapted from Browser Use's browser-harness-js interaction skills (MIT).
