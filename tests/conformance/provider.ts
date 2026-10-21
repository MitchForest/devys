import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { expect, it } from "vitest";
import type { ProviderAdapter, ProviderEvents } from "../../src/apps/code/host/provider.ts";

type Ended = Parameters<ProviderEvents["turnEnded"]>[0];

/** An adapter with its reported events. Stand-in harnesses reply "did: <texts>" per turn. */
export interface ProviderHarness {
  adapter: ProviderAdapter;
  ended: Ended[];
  lost: string[];
  /** The next turn end reported from now on. */
  next(): Promise<Ended>;
}

/** Wraps a provider adapter factory with recorded events. */
export function recorded(make: (events: ProviderEvents) => ProviderAdapter): ProviderHarness {
  const ended: Ended[] = [];
  const lost: string[] = [];
  let waiting: ((value: Ended) => void) | undefined;
  const adapter = make({
    turnEnded: (event) => {
      ended.push(event);
      waiting?.(event);
    },
    lost: (ids) => lost.push(...ids),
  });
  return { adapter, ended, lost, next: () => new Promise((resolve) => (waiting = resolve)) };
}

/**
 * What every coding delegate adapter guarantees (.docs/COMPONENTS.md#coding-delegates): a turn
 * ends with its reply; a message during a turn steers it and one after starts the next;
 * interrupting ends the turn as interrupted; a session resumes by id in a new process; a
 * harness that dies mid-turn is reported lost; close stops its processes.
 */
export function providerConformance(name: string, harness: () => ProviderHarness) {
  const cwd = mkdtempSync(join(tmpdir(), "devys-provider-"));
  const begin = (adapter: ProviderAdapter, prompt: string) =>
    adapter.start({ cwd, instructions: "Work only here.", prompt, readOnly: false });

  it(`${name}: a message during a turn steers it; one after starts the next turn`, async () => {
    const { adapter, next } = harness();
    let ended = next();
    const started = await begin(adapter, "slow build");
    expect(
      await adapter.send({ sessionId: started.sessionId, cwd, text: "add tests", readOnly: false }),
    ).toEqual({ turnId: started.turnId, steered: true });
    expect(await ended).toMatchObject({
      sessionId: started.sessionId,
      turnId: started.turnId,
      status: "completed",
      reply: "did: slow build + add tests",
    });
    ended = next();
    const following = await adapter.send({
      sessionId: started.sessionId,
      cwd,
      text: "rename",
      readOnly: false,
    });
    expect(following.steered).toBe(false);
    expect(following.turnId).not.toBe(started.turnId);
    expect(await ended).toMatchObject({ turnId: following.turnId, reply: "did: rename" });
    await adapter.close();
  });

  it(`${name}: interrupting reports interrupted, and the session resumes by id in a new process`, async () => {
    const first = harness();
    let ended = first.next();
    const started = await begin(first.adapter, "slow work");
    await first.adapter.interrupt(started.sessionId);
    expect(await ended).toMatchObject({ status: "interrupted", reply: null });
    await first.adapter.close();
    const second = harness();
    ended = second.next();
    const resumed = await second.adapter.send({
      sessionId: started.sessionId,
      cwd,
      text: "continue",
      readOnly: false,
    });
    expect(resumed.steered).toBe(false);
    expect(await ended).toMatchObject({ sessionId: started.sessionId, reply: "did: continue" });
    await second.adapter.close();
  });

  it(`${name}: the transcript reads what it was told and what it replied`, async () => {
    const { adapter, next } = harness();
    const ended = next();
    const started = await begin(adapter, "build it");
    await ended;
    const entries = await adapter.transcript({ sessionId: started.sessionId, cwd });
    expect(entries).toEqual(
      expect.arrayContaining([
        { kind: "prompt", text: "build it" },
        { kind: "reply", text: "did: build it" },
      ]),
    );
    await adapter.close();
  });

  it(`${name}: a harness that exits mid-turn is reported lost`, async () => {
    const { adapter, lost } = harness();
    const started = await begin(adapter, "slow work");
    await adapter
      .send({ sessionId: started.sessionId, cwd, text: "crash", readOnly: false })
      .catch(() => undefined);
    for (let attempt = 0; attempt < 50 && !lost.length; attempt++)
      await new Promise((resolve) => setTimeout(resolve, 20));
    expect(lost).toEqual([started.sessionId]);
    await adapter.close();
  });
}
