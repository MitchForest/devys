import { Navigate } from "@tanstack/react-router";
import { CircleAlert } from "lucide-react";
import { useBusinessId, useMe } from "./data.ts";
import { problemOf } from "./query.ts";
import { FirstBusiness, JoinPrompt, SignIn } from "./sign-in.tsx";
import { WorkspaceProvider } from "./workspace.tsx";
import { Shell } from "../shell/shell.tsx";

/** `/`: signed in, the first business's Home; signed out, "Connect to <Mac>". */
export function Entry() {
  const me = useMe();
  if (me.isPending) return <Busy />;
  if (me.isError) return <Unreachable message={problemOf(me.error, "Devys isn't reachable.")} />;
  if (!me.data) return <SignIn />;
  const first = me.data.businesses[0];
  if (!first)
    return (
      <>
        <FirstBusiness />
        <JoinPrompt />
      </>
    );
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
      <JoinPrompt />
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
