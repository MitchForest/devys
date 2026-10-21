import { Navigate } from "@tanstack/react-router";
import { CircleAlert } from "lucide-react";
import { useState } from "react";
import { useBusinessId, useMe } from "./data.ts";
import { useSignIn } from "./mutations.ts";
import { problemOf } from "./query.ts";
import { WorkspaceProvider } from "./workspace.tsx";
import { Face } from "../design/face.tsx";
import { NewBusiness } from "../shell/settings.tsx";
import { Shell } from "../shell/shell.tsx";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

/** `/`: signed in, the first business's Home; signed out, the sign-in card. */
export function Entry() {
  const me = useMe();
  if (me.isPending) return <Busy />;
  if (me.isError) return <Unreachable message={problemOf(me.error, "Devys isn't reachable.")} />;
  if (!me.data) return <SignIn />;
  const first = me.data.businesses[0];
  if (!first) return <FirstBusiness />;
  return <Navigate to="/$business" params={{ business: first.id }} replace />;
}

/** One business's workspace; a business this person doesn't belong to goes back to `/`. */
export function BusinessApp() {
  const me = useMe();
  const id = useBusinessId();
  if (me.isPending) return <Busy />;
  if (me.isError) return <Unreachable message={problemOf(me.error, "Devys isn't reachable.")} />;
  if (!me.data) return <SignIn />;
  if (!me.data.businesses.some((b) => b.id === id)) return <Navigate to="/" replace />;
  return (
    <WorkspaceProvider>
      <Shell />
    </WorkspaceProvider>
  );
}

const Busy = () => <div className="h-dvh bg-frame" aria-busy />;

/** The server didn't answer: say so, and keep trying. */
function Unreachable({ message }: { message: string }) {
  return (
    <div className="grid min-h-dvh place-items-center bg-frame p-6">
      <p role="alert" className="flex items-center gap-1.5 text-body text-ink-2">
        <CircleAlert className="size-4 fill-red text-sheet" /> {message} Trying again…
      </p>
    </div>
  );
}

/** Signed in with no business yet: start one. */
function FirstBusiness() {
  return (
    <div className="grid min-h-dvh place-items-center overflow-y-auto bg-frame p-6">
      <div className="flex w-full max-w-[520px] rounded-sheet bg-sheet p-8 shadow-raised">
        <NewBusiness created={() => undefined} />
      </div>
    </div>
  );
}

/** The same sign-in card as the native apps; the browser already knows its server. */
function SignIn() {
  const signIn = useSignIn();
  const [code, setCode] = useState("");
  const [error, setError] = useState<string>();
  const submitting = signIn.isPending;
  return (
    <div className="grid min-h-dvh place-items-center overflow-y-auto bg-frame p-6">
      <form
        className="flex w-full max-w-[440px] flex-col items-center gap-6 rounded-sheet bg-sheet p-8 shadow-raised max-sm:p-6"
        onSubmit={(event) => {
          event.preventDefault();
          setError(undefined);
          signIn.mutate(code.trim(), {
            onError: () =>
              setError("That code didn't work. Codes are single-use and expire after an hour."),
          });
        }}
      >
        <Face
          spec={{ palette: "blue", shape: "roundedSquare", seed: 7 }}
          size={84}
          mood={submitting ? "thinking" : error ? "oops" : "idle"}
          label="Devys"
        />
        <div className="flex flex-col items-center gap-2 text-center">
          <h1 className="text-greeting font-bold tracking-tight text-ink">Welcome to Devys</h1>
          <p className="text-body text-ink-2">
            Run <code className="font-mono text-[12px]">bun run local code</code> on the Mac running
            Devys and paste the code (or open the link it prints).
          </p>
        </div>
        <label className="flex w-full flex-col gap-1.5">
          <span className="text-label font-medium text-ink-3">Enrollment code</span>
          <Input
            autoFocus
            autoComplete="one-time-code"
            spellCheck={false}
            placeholder="64-character code"
            value={code}
            onChange={(event) => setCode(event.target.value)}
            className="rounded-row bg-track px-3.5 py-[11px]"
          />
        </label>
        {error && (
          <p
            role="alert"
            className="flex w-full animate-in items-center gap-1.5 text-detail text-red fade-in"
          >
            <CircleAlert className="size-3.5 fill-red text-sheet" /> {error}
          </p>
        )}
        <Button
          variant="aurora"
          type="submit"
          disabled={submitting || code.trim().length !== 64}
          className="w-full justify-center [&>span]:w-full [&>span]:justify-center"
        >
          {submitting ? "Signing in…" : "Sign in"}
        </Button>
      </form>
    </div>
  );
}
