import type { ReactElement } from "react";
import type { ModelCatalog, ModelOption, Usage } from "../../app/wire.ts";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuLabel,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

/** Whole dollars stay whole ("$5"); anything else shows cents ("$0.30"). */
const price = (dollars: number) =>
  Number.isInteger(dollars) ? `$${dollars}` : `$${dollars.toFixed(2)}`;

/** Dollars to the cent, with spend under a cent shown as such rather than as $0.00. */
export const dollars = (amount: number) =>
  amount > 0 && amount < 0.01 ? "< $0.01" : `$${amount.toFixed(2)}`;

export const perTurn = (model: ModelOption) =>
  model.typical_turn_usd < 0.01
    ? "< $0.01 per turn"
    : `≈ ${dollars(model.typical_turn_usd)} per turn`;

/** Total spend across models, and the share of input served from cache. */
export function spend(models: Record<string, Usage>) {
  const usage = Object.values(models);
  const total = usage.reduce((sum, u) => sum + u.cost.total, 0);
  const cacheRead = usage.reduce((sum, u) => sum + u.cache_read, 0);
  const read = cacheRead + usage.reduce((sum, u) => sum + u.input, 0);
  return { total, cacheShare: read > 0 ? cacheRead / read : undefined };
}

/** The deployment's models grouped by who makes them; choosing one calls `onChange`. */
export function ModelPicker({
  catalog,
  value,
  onChange,
  trigger,
}: {
  catalog: ModelCatalog;
  value: string;
  onChange: (model: string) => void;
  trigger: ReactElement;
}) {
  const vendors = [...new Set(catalog.models.map((m) => m.vendor))];
  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={trigger} />
      <DropdownMenuContent align="end" className="w-[340px] max-w-[calc(100vw-32px)]">
        <DropdownMenuRadioGroup value={value} onValueChange={(model: string) => onChange(model)}>
          {vendors.map((vendor, index) => (
            <DropdownMenuGroup key={vendor}>
              {index > 0 && <DropdownMenuSeparator />}
              <DropdownMenuLabel>{vendor}</DropdownMenuLabel>
              {catalog.models
                .filter((m) => m.vendor === vendor)
                .map((model) => (
                  <DropdownMenuRadioItem
                    key={model.id}
                    value={model.id}
                    aria-label={model.label}
                    closeOnClick
                    className="items-start rounded-[6px] py-1.5"
                  >
                    <span className="flex min-w-0 flex-col gap-0.5">
                      <span className="flex items-baseline gap-1.5">
                        <span className="text-control font-medium text-ink">{model.label}</span>
                        {model.id === catalog.defaults.employee && (
                          <span className="text-caption text-ink-3">Default</span>
                        )}
                      </span>
                      <span className="text-detail text-ink-2">{model.summary}</span>
                      <span className="text-detail text-ink-3">
                        {perTurn(model)} · {price(model.price.input)} in,{" "}
                        {price(model.price.output)} out per 1M · {model.provider}
                      </span>
                    </span>
                  </DropdownMenuRadioItem>
                ))}
            </DropdownMenuGroup>
          ))}
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
