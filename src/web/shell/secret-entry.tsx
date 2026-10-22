import { useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Field } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { api } from "../app/api.ts";
import { keys } from "../app/query.ts";
import { secretBytes, type NewSecret } from "../../vault/contract.ts";

const blankCard = { number: "", expiry: "", cvc: "", name: "", postal: "" };

/**
 * The secure entry sheet: a secret's value, or a card, typed (or filled by the browser) and sent
 * straight to the server, which hands it to the Mac host to seal. The value lives only in this
 * form's state while it is open: never in a query cache, a conversation, a URL or a log, and it is
 * forgotten when the sheet closes. Opened from Settings › Secrets, or from a request in Needs you
 * with the name and kind fixed.
 */
export function SecretEntrySheet({
  businessId,
  open,
  onClose,
  fixed,
}: {
  businessId: string;
  open: boolean;
  onClose: () => void;
  /** What an employee asked for: its name, and whether it is a card. */
  fixed?: { name: string; spend: boolean };
}) {
  const client = useQueryClient();
  const [name, setName] = useState(fixed?.name ?? "");
  const [spend, setSpend] = useState(fixed?.spend ?? false);
  const [value, setValue] = useState("");
  const [card, setCard] = useState(blankCard);
  const [keepCode, setKeepCode] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string>();
  const forget = () => {
    setValue("");
    setCard(blankCard);
    setError(undefined);
    setSaving(false);
  };
  const close = () => {
    forget();
    if (!fixed) setName("");
    onClose();
  };
  const field = (key: keyof typeof blankCard) => ({
    value: card[key],
    onChange: (event: { target: { value: string } }) =>
      setCard((current) => ({ ...current, [key]: event.target.value })),
  });
  const named = /^[A-Z][A-Z0-9_]{0,63}$/.test(name);
  const ready = named && (spend ? card.number && card.expiry && card.name && card.postal : value);
  async function save(event: FormEvent) {
    event.preventDefault();
    if (!ready || saving) return;
    setSaving(true);
    setError(undefined);
    const entry: NewSecret = spend
      ? {
          name,
          kind: "spend",
          card: {
            number: card.number.replace(/[\s-]/g, ""),
            expiry: card.expiry.replace(/\s/g, ""),
            ...(keepCode ? {} : { cvc: card.cvc.trim() }),
            name: card.name.trim(),
            postal: card.postal.trim(),
          },
        }
      : { name, kind: "secret", value };
    try {
      const saved = await api.addSecret(businessId, entry);
      client.setQueryData(keys.secrets(businessId), saved);
      void client.invalidateQueries({ queryKey: keys.business(businessId) });
      close();
    } catch (cause) {
      // The server's refusal never repeats the value.
      setError(cause instanceof Error && cause.message ? cause.message : "It couldn't be saved.");
      setSaving(false);
    }
  }
  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent className="sm:max-w-md" data-testid="secret-entry">
        <DialogTitle>
          {fixed ? `Add ${fixed.name}` : spend ? "Add a card" : "Add a secret"}
        </DialogTitle>
        <form
          className="flex flex-col gap-3"
          onSubmit={(event) => void save(event)}
          autoComplete="off"
        >
          {!fixed && (
            <>
              <Field label="Name" hint={name && !named ? "Capitals, digits and _ only" : undefined}>
                <Input
                  value={name}
                  onChange={(event) => setName(event.target.value.toUpperCase())}
                  placeholder={spend ? "RAMP_CARD" : "STRIPE_KEY"}
                  maxLength={64}
                  spellCheck={false}
                />
              </Field>
              <Switch checked={spend} onCheckedChange={setSpend}>
                <span className="text-detail text-ink-2">A card</span>
              </Switch>
            </>
          )}
          {spend ? (
            <>
              <Field label="Card number">
                <Input
                  inputMode="numeric"
                  autoComplete="cc-number"
                  {...field("number")}
                  maxLength={23}
                />
              </Field>
              <div className="flex gap-2">
                <Field label="Expiry" className="flex-1">
                  <Input
                    autoComplete="cc-exp"
                    placeholder="MM/YY"
                    {...field("expiry")}
                    maxLength={5}
                  />
                </Field>
                {!keepCode && (
                  <Field label="Security code" className="flex-1">
                    <Input
                      type="password"
                      inputMode="numeric"
                      autoComplete="cc-csc"
                      {...field("cvc")}
                      maxLength={4}
                    />
                  </Field>
                )}
              </div>
              <Switch checked={keepCode} onCheckedChange={setKeepCode}>
                <span className="text-detail text-ink-2">Keep the security code to myself</span>
              </Switch>
              <Field label="Name on card">
                <Input autoComplete="cc-name" {...field("name")} maxLength={100} />
              </Field>
              <Field label="Postal code">
                <Input autoComplete="postal-code" {...field("postal")} maxLength={20} />
              </Field>
            </>
          ) : (
            <Field label="Value">
              <Input
                type="password"
                autoComplete="off"
                value={value}
                onChange={(event) => setValue(event.target.value)}
                maxLength={secretBytes}
                spellCheck={false}
              />
            </Field>
          )}
          {error && <span className="text-detail text-ink-2">{error}</span>}
          <Button type="submit" disabled={!ready || saving}>
            Save
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}
