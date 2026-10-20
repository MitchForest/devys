import { createFileRoute } from "@tanstack/react-router";
import { TerminalWindow } from "../pages/terminal-window.tsx";

/** A terminal on the owner's Mac, in a window of its own. */
export const Route = createFileRoute("/terminal/$business/$id")({
  component: function Terminal() {
    const { business, id } = Route.useParams();
    return <TerminalWindow businessId={business} terminalId={id} />;
  },
});
