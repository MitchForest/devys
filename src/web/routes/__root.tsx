import { createRootRoute, HeadContent, Outlet, Scripts } from "@tanstack/react-router";
import css from "../styles.css?url";
import { themeScript } from "../app/theme.ts";
export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1, viewport-fit=cover" },
      { title: "Devys" },
    ],
    links: [{ rel: "stylesheet", href: css }],
  }),
  component: () => (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
        <HeadContent />
      </head>
      <body>
        <Outlet />
        <Scripts />
      </body>
    </html>
  ),
});
