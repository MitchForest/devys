import { createFileRoute } from "@tanstack/react-router";
import { Entry } from "../app/App.tsx";

/** Signed in, the first business's Home; signed out, the sign-in card. */
export const Route = createFileRoute("/")({ component: Entry });
