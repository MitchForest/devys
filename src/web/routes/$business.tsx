import { createFileRoute } from "@tanstack/react-router";
import { BusinessApp } from "../app/App.tsx";
import { validateLayerSearch } from "../app/navigation.ts";

/** One business's workspace; its children name the place, the search the layers. */
export const Route = createFileRoute("/$business")({
  validateSearch: validateLayerSearch,
  component: BusinessApp,
});
