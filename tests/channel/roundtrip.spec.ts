import { test, expect } from "@playwright/test";
import { createServer } from "node:http";
import { randomUUID, createHmac, createHash } from "node:crypto";
import { localStores } from "../fixtures/local.ts";

test("native Pi admission and channel delivery deduplicate input and respect a stop during preparation", async ({
  request,
}) => {
  const messageId = randomUUID();
  const sender = "+15555550101",
    chat = `any;-;${sender}`;
  const outputs = new Map<string, string>();
  const messages = new Map<string, string>([
    [
      messageId,
      "Use your remember capability to save key favorite-color with content sea-green and source user. Then confirm briefly.",
    ],
  ]);
  const reads = new Map<string, number>();
  let blockedMessage: string | undefined;
  let preparationStarted = false;
  let releasePreparation!: () => void;
  const preparation = new Promise<void>((resolve) => {
    releasePreparation = resolve;
  });
  let sendAttempts = 0;
  const server = createServer(async (incoming, response) => {
    response.setHeader("content-type", "application/json");
    const requestedId = /^\/v1\/messages\/([^/?]+)/.exec(incoming.url ?? "")?.[1];
    if (requestedId && messages.has(requestedId)) {
      const count = (reads.get(requestedId) ?? 0) + 1;
      reads.set(requestedId, count);
      if (requestedId === blockedMessage && count === 2) {
        preparationStarted = true;
        await preparation;
      }
      response.end(
        JSON.stringify({
          message: {
            guid: requestedId,
            chatGuids: [chat],
            sender: { address: sender },
            dateCreated: new Date().toISOString(),
            isFromMe: false,
            content: {
              text: messages.get(requestedId),
            },
          },
        }),
      );
      return;
    }
    if (incoming.url === "/v1/messages:sendText") {
      let raw = "";
      for await (const chunk of incoming) raw += chunk;
      const body = JSON.parse(raw) as { clientMessageId: string; text: string };
      sendAttempts++;
      if (outputs.has(body.clientMessageId)) {
        response.statusCode = 409;
        response.end(
          JSON.stringify({
            errorCode: "duplicateMessage",
            code: "already_exists",
            message: "Already sent",
            retryable: false,
          }),
        );
        return;
      }
      outputs.set(body.clientMessageId, body.text);
      // Lose the first response after accepting the send. The outbox must reconcile it.
      incoming.socket.destroy();
      return;
    }
    response.statusCode = 404;
    response.end("{}");
  });
  await new Promise<void>((resolve) => server.listen(55433, "127.0.0.1", resolve));
  const stores = await localStores(true);
  const { sql } = stores;
  const fixture = await stores.owner("Channel test");
  const owner = fixture.business;
  await sql.run(
    "INSERT INTO channel_bindings(id,business_id,employee_id,person_id,channel,sender_id,chat_id) VALUES($1,$2,$3,$4,'imessage',$5,$6)",
    [randomUUID(), fixture.business, fixture.operations, fixture.person, sender, chat],
  );
  const status = `/api/businesses/${fixture.business}/employees/${fixture.operations}/status`;
  const access = createHash("sha256").update(randomUUID()).digest("hex");
  await sql.run(
    "INSERT INTO web_sessions(token_hash,person_id,expires_at) VALUES($1,$2,now() + interval '1 hour')",
    [createHash("sha256").update(access).digest("hex"), fixture.person],
  );
  try {
    const post = async (id: string) => {
      const body = JSON.stringify({
        event: "messages",
        message: { id, direction: "inbound", sender: { id: sender } },
        space: { id: chat, type: "dm" },
      });
      const timestamp = String(Math.floor(Date.now() / 1_000));
      const signature = `v0=${createHmac("sha256", "channel-test-secret").update(`v0:${timestamp}:${body}`).digest("hex")}`;
      expect(
        (
          await request.post("/webhooks/photon", {
            data: body,
            headers: {
              "content-type": "application/json",
              "x-spectrum-timestamp": timestamp,
              "x-spectrum-signature": signature,
            },
          })
        ).status(),
      ).toBe(204);
    };
    const outputId = (id: string) => createHash("sha256").update(`imessage:${id}`).digest("hex");
    await post(messageId);
    await post(messageId);
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ content: string }>(
              "SELECT content FROM memories WHERE scope_id=$1 AND key='favorite-color'",
              [owner],
            )
          )?.content,
        { timeout: 90_000 },
      )
      .toBe("sea-green");
    await expect.poll(() => sendAttempts, { timeout: 30_000 }).toBeGreaterThanOrEqual(2);
    await expect
      .poll(async () => {
        const response = await request.get(status, {
          headers: { cookie: `__Host-devys=${access}` },
        });
        const result = (await response.json()) as { state: { outbox: { status: string }[] } };
        return result.state.outbox[0]?.status;
      })
      .toBe("sent");
    const personal = await request.get(`/api/businesses/${fixture.business}/memory`, {
      headers: { cookie: `__Host-devys=${access}` },
    });
    const saved = (await personal.json()).items.find(
      (item: { key: string }) => item.key === "favorite-color",
    );
    expect(saved.source_kind).toBe("user");
    expect(saved.evidence[0].id).toMatch(/^pi:/);
    expect(saved.evidence[0].kind).toBe("owner");
    expect(outputs.size).toBe(1);
    expect([...outputs.values()][0]?.length).toBeGreaterThan(0);
    expect(
      (
        await sql.row<{ revision: number }>(
          "SELECT revision FROM memories WHERE scope_id=$1 AND key='favorite-color'",
          [owner],
        )
      )?.revision,
    ).toBe(1);

    // Stop while the channel is preparing an input, before Pi owns it.
    blockedMessage = randomUUID();
    messages.set(
      blockedMessage,
      "Remember key must-not-run with content unwanted and source user.",
    );
    await post(blockedMessage);
    await expect.poll(() => preparationStarted).toBe(true);
    const stopId = randomUUID();
    messages.set(stopId, "stop");
    await post(stopId);
    await expect.poll(() => outputs.has(outputId(stopId)), { timeout: 15_000 }).toBe(true);
    releasePreparation();
    await expect.poll(() => outputs.has(outputId(blockedMessage!)), { timeout: 15_000 }).toBe(true);
    expect(
      await sql.run("SELECT 1 FROM memories WHERE scope_id=$1 AND key='must-not-run'", [owner]),
    ).toBe(0);

    // A replayed old stop cannot cancel a later message.
    const laterId = randomUUID();
    messages.set(
      laterId,
      "Use remember to correct favorite-color to deep-blue, source user. Then confirm briefly.",
    );
    await post(laterId);
    await post(stopId);
    await expect
      .poll(
        async () =>
          (
            await sql.row<{ content: string }>(
              "SELECT content FROM memories WHERE scope_id=$1 AND key='favorite-color'",
              [owner],
            )
          )?.content,
        { timeout: 90_000 },
      )
      .toBe("deep-blue");
    await expect.poll(() => outputs.has(outputId(laterId)), { timeout: 15_000 }).toBe(true);
  } catch (error) {
    const response = await request.get(status, {
      headers: { cookie: `__Host-devys=${access}` },
    });
    const diagnostic = (await response.json()) as {
      state?: { run?: unknown; messages?: unknown[]; outbox?: unknown };
    };
    console.log(JSON.stringify({ run: diagnostic.state?.run, outbox: diagnostic.state?.outbox }));
    throw error;
  } finally {
    releasePreparation();
    await sql.run("UPDATE people SET revoked_at=now() WHERE id=$1", [fixture.person]);
    await stores.remove([fixture]);
    await stores.dispose();
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
});
