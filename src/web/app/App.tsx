import { CircleAlert } from "lucide-react";
import { useState } from "react";
import { WorkspaceProvider, useWorkspace } from "./workspace.tsx";
import { DevysButton } from "../design/buttons.tsx";
import { Face } from "../design/face.tsx";
import { Shell } from "../shell/shell.tsx";
import { TooltipProvider } from "@/components/ui/tooltip";

export function App() {
  return (
    <TooltipProvider>
      <WorkspaceProvider>
        <Root />
      </WorkspaceProvider>
    </TooltipProvider>
  );
}

function Root() {
  const { signedOut, person } = useWorkspace();
  if (signedOut) return <SignIn />;
  if (!person) return <div className="h-dvh bg-frame" aria-busy />;
  return <Shell />;
}

/** The same sign-in card as the native apps; the browser already knows its server. */
function SignIn() {
  const { actions } = useWorkspace();
  const [code, setCode] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string>();
  return (
    <div className="grid min-h-dvh place-items-center overflow-y-auto bg-frame p-6">
      <form
        className="flex w-full max-w-[440px] flex-col items-center gap-6 rounded-sheet bg-sheet p-8 shadow-raised max-sm:p-6"
        onSubmit={(event) => {
          event.preventDefault();
          setSubmitting(true);
          setError(undefined);
          void actions
            .signIn(code.trim())
            .catch(() =>
              setError("That code didn't work. Codes are single-use and expire after an hour."),
            )
            .finally(() => setSubmitting(false));
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
            Paste the one-time code from{" "}
            <code className="font-mono text-[12px]">bun scripts/enroll.ts</code>.
          </p>
        </div>
        <label className="flex w-full flex-col gap-1.5">
          <span className="text-label font-medium text-ink-3">Enrollment code</span>
          <input
            autoFocus
            autoComplete="one-time-code"
            spellCheck={false}
            placeholder="64-character code"
            value={code}
            onChange={(event) => setCode(event.target.value)}
            className="rounded-[12px] bg-track px-3.5 py-[11px] text-body text-ink outline-none placeholder:text-ink-3 focus-visible:ring-2 focus-visible:ring-indigo/40"
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
        <DevysButton
          kind="aurora"
          type="submit"
          disabled={submitting || code.trim().length !== 64}
          className="w-full justify-center [&>span]:w-full [&>span]:justify-center"
        >
          {submitting ? "Signing in…" : "Sign in"}
        </DevysButton>
      </form>
    </div>
  );
}
