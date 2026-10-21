import type { Business } from "../identity/contract.ts";
import type { OwnerInput } from "../browser/contract.ts";
import type { Env } from "./env.ts";
import { modeOf } from "./mode.ts";
import { body, forbidden, notFound } from "./request.ts";

/**
 * The business's browser for its owner (local mode): where it is and which work drives it, a
 * live picture, and the owner's own clicks and typing. Taking over is the work item's takeover,
 * which stops employees acting; the owner's input is not recorded.
 */
export async function browserRoute(
  request: Request,
  env: Env,
  access: { business: Business; trusted: boolean; path: string },
) {
  const { business, trusted, path } = access;
  if (path !== "/browser" && !path.startsWith("/browser/")) return undefined;
  const browser = modeOf(env).browser(business.id);
  if (path === "/browser" && request.method === "GET") return Response.json(await browser.status());
  if (path === "/browser/screenshot" && request.method === "GET")
    return Response.json(await browser.screenshot());
  if (path === "/browser/input" && request.method === "POST") {
    if (!trusted) return forbidden();
    const action = await body<OwnerInput>(request, 8_000);
    try {
      return Response.json(await browser.input(action as OwnerInput));
    } catch (error) {
      return new Response(error instanceof Error ? error.message : "The page refused that", {
        status: 409,
      });
    }
  }
  return notFound();
}
