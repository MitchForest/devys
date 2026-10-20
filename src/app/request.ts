import { readBounded } from "../protocol/bytes.ts";

export const notFound = () => new Response("Not found", { status: 404 });
export const forbidden = () => new Response("Forbidden", { status: 403 });
export const body = async <T>(request: Request, limit: number) =>
  JSON.parse(new TextDecoder().decode(await readBounded(request.body, limit))) as Partial<T>;
export const label = (value: unknown, max: number) =>
  typeof value === "string" && value.trim().length > 0 && value.trim().length <= max
    ? value.trim()
    : undefined;
