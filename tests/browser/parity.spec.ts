import { test, expect } from "@playwright/test";
import { localStores } from "../fixtures/local.ts";
import { sidebar, signIn } from "./helpers.ts";

/** A recognizer that hears one sentence, so dictation runs without a microphone. */
const fakeSpeech = () => {
  class FakeRecognition extends EventTarget {
    continuous = false;
    interimResults = false;
    lang = "en";
    onresult: ((event: unknown) => void) | null = null;
    onerror: ((event: unknown) => void) | null = null;
    onend: (() => void) | null = null;
    onaudiostart: (() => void) | null = null;
    start() {
      setTimeout(() => this.onaudiostart?.(), 10);
      setTimeout(() => {
        const result = Object.assign([{ transcript: "What is due today?" }], {
          isFinal: true,
        });
        this.onresult?.({ resultIndex: 0, results: [result] });
        if (!this.continuous) this.onend?.();
      }, 50);
    }
    stop() {
      setTimeout(() => this.onend?.(), 10);
    }
    abort() {
      this.onend?.();
    }
  }
  Object.assign(window, { SpeechRecognition: FakeRecognition });
};

test("looks, the owner's photo, voice and settings work on the web as on native", async ({
  page,
}) => {
  const stores = await localStores();
  const { sql } = stores;
  const owner = await stores.owner("Riley", "Acme");
  await page.addInitScript(fakeSpeech);
  try {
    await signIn(page, sql, owner.person);

    // Settings has the same panes as the native Settings window.
    await page.getByRole("button", { name: "Account" }).click();
    await page.getByRole("menuitem", { name: "Settings…" }).click();
    const settings = page.getByRole("dialog", { name: "Settings" });
    for (const section of [
      "Account",
      "Apps",
      "Team",
      "Businesses",
      "Devices",
      "Voice",
      "Appearance",
    ])
      await expect(settings.getByRole("button", { name: section, exact: true })).toBeVisible();

    // The owner's photo uploads to the server.
    await settings.getByLabel("Add photo").setInputFiles({
      name: "me.png",
      mimeType: "image/png",
      buffer: Buffer.from(
        Uint8Array.from(
          atob(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
          ),
          (char) => char.charCodeAt(0),
        ),
      ),
    });
    await expect(settings.getByRole("button", { name: "Remove" })).toBeVisible();

    // An employee's look is set in Team and stored on the server for every client.
    await settings.getByRole("button", { name: "Team", exact: true }).click();
    await settings.getByRole("tab", { name: "Emoji" }).click();
    await settings.getByRole("button", { name: "🦉" }).click();
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ look: unknown }>("SELECT look FROM employees WHERE id = $1", [
              owner.operations,
            ])
          )?.look,
      )
      .toEqual({ kind: "emoji", emoji: "🦉", tint: "blue" });

    // A business's look too.
    await settings.getByRole("button", { name: "Businesses", exact: true }).click();
    await settings.getByRole("tab", { name: "Emoji" }).click();
    await settings.getByRole("button", { name: "Purple" }).click();
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ look: unknown }>("SELECT look FROM businesses WHERE id = $1", [
              owner.business,
            ])
          )?.look,
      )
      .toEqual({ kind: "emoji", emoji: "🙂", tint: "purple" });

    await settings.getByRole("button", { name: "Voice", exact: true }).click();
    await expect(settings.getByLabel("Reply voice")).toBeVisible();
    await settings.getByText("Read replies aloud").click();
    expect(
      await page.evaluate(() => JSON.parse(localStorage.getItem("voiceSettings")!).speaksReplies),
    ).toBe(true);
    await page.keyboard.press("Escape");

    // Dictation fills the direct chat's draft; sending marks the message as dictated.
    await sidebar(page).getByRole("button", { name: "Head of Operations" }).click();
    await page.getByRole("button", { name: "Dictate" }).click();
    await expect(page.getByLabel("Message Head of Operations")).toHaveValue("What is due today?");
    const sent = page.waitForResponse(
      (response) =>
        decodeURIComponent(response.url()).endsWith(
          `/conversations/direct:${owner.operations}/messages`,
        ) && response.request().method() === "POST",
    );
    await page.getByRole("button", { name: "Send" }).click();
    const response = await sent;
    expect(response.request().postDataJSON()).toMatchObject({
      text: "What is due today?",
      viaVoice: true,
    });
    // The server stores it as dictated, in Operations' DM.
    expect(await response.json()).toMatchObject({
      message: { text: "What is due today?", via_voice: true },
      to: [owner.operations],
    });
    await expect(page.getByText("What is due today?")).toBeVisible();

    // ⌘K jumps to any conversation, or opens an app beside the one on screen.
    await page.keyboard.press("Meta+k");
    await page.keyboard.type("Home");
    await page.keyboard.press("Enter");
    await expect(page.getByTestId("place-title")).toHaveText("Home");
    await expect(page.getByRole("dialog", { name: "Jump to" })).toBeHidden();
    await page.keyboard.press("Meta+k");
    await page.keyboard.type("Documents");
    await page.keyboard.press("Enter");
    await expect(page.getByRole("region", { name: "Documents" })).toBeVisible();
    await expect(page.getByTestId("place-title")).toHaveText("Home");
  } finally {
    // Stop the page's polling and read receipts before its business is removed.
    await page.close();
    await stores.remove([owner]);
    await stores.dispose();
  }
});
