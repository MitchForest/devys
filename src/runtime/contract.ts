import type { Inbound } from "../channels/contract.ts";
import type { ConversationKey } from "../conversations/contract.ts";
import type { Scope } from "../identity/contract.ts";

/** Agent runtime port, one per business employee. Pi owns execution behind it. */
export interface AgentPort extends Rpc.DurableObjectBranded {
  receive(scope: Scope, input: Inbound): Promise<{ accepted: boolean }>;
  stop(scope: Scope): Promise<{ stopped: boolean }>;
  inspect(scope: Scope): Promise<string>;
  /** One conversation's Pi entries; the employee's own direct chat when omitted. */
  history(scope: Scope, before?: number, conversation?: ConversationKey): Promise<string>;
}
