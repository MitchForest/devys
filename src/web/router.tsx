import { QueryClientProvider } from "@tanstack/react-query";
import { createRouter } from "@tanstack/react-router";
import { parseSearch, stringifySearch } from "./app/navigation.ts";
import { makeQueryClient } from "./app/query.ts";
import { routeTree } from "./routeTree.gen.ts";

/** One router and one query cache per page load (and per server render). */
export const getRouter = () => {
  const queryClient = makeQueryClient();
  return createRouter({
    routeTree,
    defaultPreload: "intent",
    scrollRestoration: true,
    parseSearch,
    stringifySearch,
    Wrap: ({ children }) => (
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    ),
  });
};
declare module "@tanstack/react-router" {
  interface Register {
    router: ReturnType<typeof getRouter>;
  }
}
