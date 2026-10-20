import type { ConversationContext, Inbound } from "../channels/contract.ts";
import type { Scope } from "../identity/contract.ts";

/** Agent runtime port, one per business employee. Pi owns execution behind it. */
export interface AgentPort extends Rpc.DurableObjectBranded {
  receive(scope: Scope, input: Inbound): Promise<{ accepted: boolean }>;
  stop(scope: Scope): Promise<{ stopped: boolean }>;
  inspect(scope: Scope): Promise<string>;
  /** One context's Pi entries; the direct chat when `context` is omitted. */
  history(scope: Scope, before?: number, context?: ConversationContext): Promise<string>;
}
