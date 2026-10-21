import { Schema } from "effect";

/** Starting a connection: the provider's consent page the owner is sent to. */
export const Authorization = Schema.Struct({ url: Schema.String });
/** Removing a connection; `revoked` says whether the provider confirmed the revocation. */
export const Disconnected = Schema.Struct({
  disconnected: Schema.Literal(true),
  revoked: Schema.Boolean,
});

/**
 * A business's connection to an outside account, as an app that uses it sees it. The
 * connections component holds the grant and its stored credential; an app gets only a
 * short-lived access token, never the credential itself.
 */
export interface ConnectionAccess {
  /** The connection the token came from; replacing or removing it invalidates the token. */
  id: string;
  token: string;
}

/** One provider's connection for the apps that use it (Documents uses Google's). */
export interface Connection {
  /** A fresh access token for the business's connection; fails when it has none. */
  access(businessId: string): Promise<ConnectionAccess>;
  /** Fails unless `access` still belongs to the business's current connection. */
  assertCurrent(businessId: string, access: ConnectionAccess): Promise<void>;
}
