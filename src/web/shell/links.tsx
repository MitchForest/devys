import { Link, useRouterState } from "@tanstack/react-router";
import type { ComponentProps } from "react";
import { useBusinessId } from "../app/data.ts";
import { routeOf, usePlace, type Place } from "../app/navigation.ts";
import { ui } from "../app/ui.ts";

type AnchorProps = Omit<ComponentProps<"a">, "href" | "ref">;

/** A link to a place, as the sidebar opens it: the layers close and Back starts over. */
export function PlaceLink({ place, onClick, ...props }: AnchorProps & { place: Place }) {
  const business = useBusinessId();
  return (
    <Link
      {...routeOf(business, place)}
      {...props}
      onClick={(event) => {
        ui.leftPlace();
        onClick?.(event);
      }}
    />
  );
}

/** A link into a work item's thread; Back (⌘[) returns to where it was opened. */
export function ThreadLink({ workId, onClick, ...props }: AnchorProps & { workId: string }) {
  const business = useBusinessId();
  const place = usePlace();
  const trail = useRouterState({ select: (state) => state.location.state.trail });
  const here = place.kind === "thread" && place.workId === workId;
  return (
    <Link
      {...routeOf(business, { kind: "thread", workId })}
      state={{ trail: [...(trail ?? []), place] }}
      {...props}
      onClick={(event) => {
        if (here) event.preventDefault();
        onClick?.(event);
      }}
    />
  );
}
