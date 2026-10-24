import { Link } from "@tanstack/react-router";
import type { ComponentProps } from "react";
import { useBusinessId } from "../app/data.ts";
import { routeOf, type Place } from "../app/navigation.ts";
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
