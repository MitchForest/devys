/** Browser mutations must originate from this deployment. */
export function sameOrigin(request: Request) {
  return request.headers.get("origin") === new URL(request.url).origin;
}
