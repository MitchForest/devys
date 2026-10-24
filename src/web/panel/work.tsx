import {
  Check,
  CircleCheck,
  CircleX,
  Clock,
  Hand,
  KeyRound,
  Redo2,
  Undo2,
  Upload,
} from "lucide-react";
import { useRef, useState, type ReactNode } from "react";
import { ownerRequest, spendOf, type Decision } from "../../authority/contract.ts";
import type { NeedsYouRequest } from "../../app/wire.ts";
import type { WorkItem } from "../../work/contract.ts";
import { upcoming } from "../lib/format.ts";
import { accessTitle, chipFor, isOpen, takeoverTitle, templateTitle } from "../app/names.ts";
import { useBusinessId, useEmployeeName, useMembers, usePerson } from "../app/data.ts";
import {
  useAnswer,
  useConnectApp,
  useOpenChrome,
  useSendFile,
  useTakeover,
  useUpdateWorkItem,
} from "../app/mutations.ts";
import { useNav } from "../app/navigation.ts";
import { SecretEntrySheet } from "../shell/secret-entry.tsx";
import { StatusChip, Card } from "../design/primitives.tsx";
import { AppAction, AppLogo, useRemoteApp } from "./layers/team-app.tsx";
import { DraftPreview } from "./layers/preview.tsx";
import { RoutineProposal } from "./routines.tsx";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import { Button } from "@/components/ui/button";

/** The owner's changes to a work item, as the menus and buttons apply them. */
function useWorkChanges() {
  const update = useUpdateWorkItem();
  const takeover = useTakeover();
  return {
    setState: (item: WorkItem, state: WorkItem["state"]) =>
      update.mutate({ item, change: { state }, failure: "That work item changed." }),
    toggleTakeover: (item: WorkItem) => takeover.mutate(item),
  };
}

/**
 * What the owner can do to a work item from a row: take it over or hand it back. Changing it by
 * hand (marking it, cancelling, reopening) is for work they have taken over, which fences its
 * employee; otherwise they ask in its conversation (owner decision 2026-10-21).
 */
function WorkActions({ item, extra }: { item: WorkItem; extra?: ReactNode }) {
  const actions = useWorkChanges();
  const mine = useHandEditing(item);
  const person = usePerson();
  const takeover = item.taken_over_by === null || item.taken_over_by === person?.id;
  return (
    <>
      {isOpen(item.state) && takeover && (
        <ContextMenuItem onClick={() => actions.toggleTakeover(item)}>
          {item.taken_over_by === null ? (
            <>
              <Hand /> Take over
            </>
          ) : (
            <>
              <Undo2 /> Hand back
            </>
          )}
        </ContextMenuItem>
      )}
      {mine && !isOpen(item.state) && (
        <ContextMenuItem onClick={() => actions.setState(item, "ready")}>
          <Undo2 /> Reopen
        </ContextMenuItem>
      )}
      {mine && isOpen(item.state) && (
        <>
          <ContextMenuSeparator />
          {item.state !== "ready" && (
            <ContextMenuItem onClick={() => actions.setState(item, "ready")}>
              <Redo2 /> Mark ready
            </ContextMenuItem>
          )}
          {item.state !== "waiting" && (
            <ContextMenuItem onClick={() => actions.setState(item, "waiting")}>
              <Clock /> Mark waiting
            </ContextMenuItem>
          )}
          <ContextMenuItem onClick={() => actions.setState(item, "completed")}>
            <CircleCheck /> Mark done
          </ContextMenuItem>
          <ContextMenuItem
            variant="destructive"
            onClick={() => actions.setState(item, "cancelled")}
          >
            <CircleX /> Cancel
          </ContextMenuItem>
        </>
      )}
      {extra}
    </>
  );
}

/** Whether the signed-in person has taken this work over, so they may change it by hand. */
function useHandEditing(item: WorkItem) {
  const person = usePerson();
  return item.taken_over_by !== null && item.taken_over_by === person?.id;
}

/** Right-click (or long-press) a work item to act on it. */
export function WithWorkActions({
  item,
  extra,
  children,
}: {
  item: WorkItem;
  extra?: ReactNode;
  children: ReactNode;
}) {
  return (
    <ContextMenu>
      <ContextMenuTrigger render={<div />} className="select-auto">
        {children}
      </ContextMenuTrigger>
      <ContextMenuContent>
        <WorkActions item={item} extra={extra} />
      </ContextMenuContent>
    </ContextMenu>
  );
}

/** One work item: what, who, what's next and its state. Click to open it beside the conversation. */
export function WorkRow({
  item,
  extra,
  compact,
}: {
  item: WorkItem;
  extra?: ReactNode;
  /** In a panel: smaller, flush with the panel's edge. */
  compact?: boolean;
}) {
  const employeeName = useEmployeeName();
  const nav = useNav();
  const person = usePerson();
  const members = useMembers();
  const takeover = takeoverTitle(item.taken_over_by, person?.id, members);
  const owner = employeeName(item.owner_employee_id);
  const done = item.evidence[item.evidence.length - 1];
  const waiting = item.state === "waiting" ? waitingNote(item) : "";
  const detail = waiting
    ? `${owner} · ${waiting}`
    : done && item.state === "completed"
      ? `${owner} · ${done.note}`
      : item.next_action
        ? `${owner} · ${item.next_action}`
        : owner;
  const chip = chipFor(item.state);
  return (
    <WithWorkActions item={item} extra={extra}>
      <button
        type="button"
        onClick={() => nav.openWork(item.id)}
        className={
          compact
            ? "-mx-2 flex w-[calc(100%+16px)] items-center gap-2.5 rounded-small px-2 py-1.5 text-left transition-colors duration-150 hover:bg-sheet-tint"
            : "flex w-full items-center gap-3 rounded-row px-3 py-2.5 text-left transition-colors duration-150 hover:bg-sheet-tint"
        }
      >
        <div className="flex min-w-0 flex-col gap-0.5">
          <span
            className={
              compact
                ? "truncate text-detail font-medium text-ink"
                : "text-body font-semibold text-ink"
            }
          >
            {item.title}
          </span>
          <span
            className={
              compact ? "truncate text-caption text-ink-3" : "line-clamp-2 text-detail text-ink-2"
            }
          >
            {detail}
          </span>
        </div>
        <span className="ml-auto" />
        {takeover && isOpen(item.state) && (
          <span className="shrink-0 text-caption text-ink-3">{takeover}</span>
        )}
        <StatusChip tone={chip.tone} small={compact}>
          {chip.title}
        </StatusChip>
      </button>
    </WithWorkActions>
  );
}

/**
 * What waiting work waits on and when it looks again, in a row: "waiting on the press kit until
 * Thu 9:00 AM", "waiting until Tomorrow 9:00 AM"; empty when neither is known.
 */
function waitingNote(item: WorkItem) {
  const until = item.wake_at ? `until ${upcoming(item.wake_at)}` : "";
  if (item.wait_condition) return `waiting on ${item.wait_condition}${until ? ` ${until}` : ""}`;
  return until && `waiting ${until}`;
}

/** An amount as the owner reads it: "$12.99", or "12.99 EUR" in another currency. */
const money = (amount: { cents: number; currency: string }) =>
  amount.currency === "USD"
    ? `$${(amount.cents / 100).toFixed(2)}`
    : `${(amount.cents / 100).toFixed(2)} ${amount.currency}`;

/** A decision's exact input as label/value rows; an `askOwner` request in its own words. */
export function decisionFields(decision: Pick<Decision, "kind" | "input">): [string, string][] {
  const request = ownerRequest(decision);
  if (request?.kind === "approve")
    return [
      ["Action", request.action],
      ["With", request.counterparty],
      ...(request.amount ? ([["Amount", money(request.amount)]] as [string, string][]) : []),
      ...(request.renewal ? ([["Renews", request.renewal]] as [string, string][]) : []),
    ];
  // The reason is the card's title; only where it happens is added.
  if (request?.kind === "take_over") return request.url ? [["Site", request.url]] : [];
  // What it is, never the name the employee uses for it.
  if (request?.kind === "secret") return [["Why", request.why]];
  if (request?.kind === "connect") return [["Why", request.why]];
  if (request?.kind === "file")
    return request.accept?.length ? [["Type", request.accept.join(", ")]] : [];
  const { input } = decision;
  if (input && typeof input === "object" && !Array.isArray(input))
    return Object.entries(input).map(([key, value]) => [
      key,
      typeof value === "string" ? value : JSON.stringify(value),
    ]);
  return [["input", JSON.stringify(input)]];
}

/**
 * A request's details on its card: its fields, the exact steps an approval covers, and the draft
 * it shows. `compact` is the work card's smaller type.
 */
export function RequestDetails({
  decision,
  compact,
}: {
  decision: Pick<Decision, "kind" | "input">;
  compact?: boolean;
}) {
  const request = ownerRequest(decision);
  const fields = decisionFields(decision);
  const steps = request?.kind === "approve" ? (request.steps ?? []) : [];
  const preview = request?.kind === "approve" ? request.preview : undefined;
  const text = compact ? "text-detail" : "text-body";
  if (!fields.length && !steps.length && !preview) return null;
  return (
    <div className="flex w-full flex-col gap-2">
      {(fields.length > 0 || steps.length > 0) && (
        <div className="flex w-full flex-col gap-1 rounded-control bg-well p-2.5">
          {fields.map(([key, value]) => (
            <div key={key} className="flex items-baseline gap-2">
              <span className={`${compact ? "min-w-14" : "min-w-16"} text-caption text-ink-3`}>
                {key}
              </span>
              <span className={`line-clamp-6 min-w-0 ${text} break-words text-ink select-text`}>
                {value}
              </span>
            </div>
          ))}
          {steps.length > 0 && (
            <div className="flex items-baseline gap-2">
              <span className={`${compact ? "min-w-14" : "min-w-16"} text-caption text-ink-3`}>
                Steps
              </span>
              <ol
                data-testid="request-steps"
                className={`flex min-w-0 list-decimal flex-col gap-0.5 pl-4 ${text} text-ink select-text`}
              >
                {steps.map((step) => (
                  <li key={step} className="break-words">
                    {step}
                  </li>
                ))}
              </ol>
            </div>
          )}
        </div>
      )}
      {preview && <DraftPreview value={preview} />}
    </div>
  );
}

/**
 * What a decision asks for, in words: a proposed hire names the person and role; an `askOwner`
 * request says what to approve, or what to do in the browser.
 */
function decisionTitle(decision: Decision) {
  const request = ownerRequest(decision);
  if (request?.kind === "approve")
    return request.amount ? `Spend ${money(request.amount)}: ${request.action}` : request.action;
  if (request?.kind === "take_over") return request.reason;
  if (request?.kind === "secret") return request.spend ? "Your card" : "A secret";
  if (request?.kind === "connect") return "Connect an app";
  if (request?.kind === "file") return request.purpose;
  if (
    decision.capability === "hireEmployee" &&
    decision.input &&
    typeof decision.input === "object"
  ) {
    const input = decision.input as { name?: unknown; template?: unknown };
    const template = typeof input.template === "string" ? templateTitle(input.template) : "";
    const name = typeof input.name === "string" && input.name ? input.name : template;
    return template && template !== name ? `Hire ${name} · ${template}` : `Hire ${name}`;
  }
  return accessTitle(decision.capability);
}

/** A request's title as the owner reads it: "Connect Ramp", "Ramp: Pay a bill", "Your card". */
export const requestTitle = (decision: NeedsYouRequest) =>
  decision.app
    ? decision.kind === "connect"
      ? `Connect ${decision.app.name}`
      : decision.title
    : decisionTitle(decision);

/**
 * How the owner answers a request: Approve or Decline; a connect is its app's Connect (or
 * Review); a take over takes the work over and brings the business's Chrome to the front; a
 * spend approval is signed on the owner's Mac or iPhone, so the web only says so
 * (.docs/AUTHORITY.md).
 */
export function RequestActions({
  decision,
  compact,
  children,
}: {
  decision: NeedsYouRequest;
  compact?: boolean;
  children?: ReactNode;
}) {
  const answer = useAnswer();
  const openChrome = useOpenChrome();
  const businessId = useBusinessId();
  const [entering, setEntering] = useState(false);
  const size = compact ? "compact" : "regular";
  const asked = ownerRequest(decision);
  if (spendOf(decision))
    return (
      <div className="flex w-full items-center gap-1.5">
        <span className="text-detail text-ink-2" data-testid="sign-elsewhere">
          Approve on your Mac or iPhone
        </span>
        <span className="ml-auto" />
        {children}
      </div>
    );
  return (
    <div className="flex w-full items-center gap-1.5">
      {asked?.kind === "secret" ? (
        <>
          <Button variant="aurora" size={size} onClick={() => setEntering(true)}>
            <KeyRound /> Add {asked.spend ? "card" : "secret"}
          </Button>
          <SecretEntrySheet
            businessId={businessId}
            open={entering}
            onClose={() => setEntering(false)}
            fixed={{ name: asked.name, spend: asked.spend ?? false, why: asked.why }}
          />
        </>
      ) : asked?.kind === "file" ? (
        <ChooseFile decision={decision} accept={asked.accept} size={size} />
      ) : decision.kind === "connect" ? (
        decision.app && <Connect app={decision.app} size={size} />
      ) : decision.kind === "take_over" ? (
        <Button
          variant="aurora"
          size={size}
          disabled={!decision.work_item_id || openChrome.isPending}
          onClick={() => decision.work_item_id && openChrome.mutate(decision.work_item_id)}
        >
          <Hand /> Open Chrome
        </Button>
      ) : (
        <Button
          variant="aurora"
          size={size}
          onClick={() => answer.mutate({ id: decision.id, approve: true })}
          title="Allows this exact request once."
        >
          <Check /> Approve
        </Button>
      )}
      <Button
        variant={decision.kind === "approve" || decision.kind === "decision" ? "raised" : "quiet"}
        size={size}
        onClick={() => answer.mutate({ id: decision.id, approve: false })}
      >
        Decline
      </Button>
      <span className="ml-auto" />
      {children}
    </div>
  );
}

/** A connect request's action: the app's own Connect or Review, as its state calls for. */
function Connect({ app, size }: { app: { id: string }; size: "compact" | "regular" }) {
  const installed = useRemoteApp(app.id);
  const connect = useConnectApp();
  if (installed) return <AppAction app={installed} compact={size === "compact"} />;
  return (
    <Button variant="aurora" size={size} onClick={() => connect(app.id)}>
      Connect
    </Button>
  );
}

/**
 * A file request's answer: the owner picks a file, which goes into the business folder and
 * answers the request with it.
 */
function ChooseFile({
  decision,
  accept,
  size,
}: {
  decision: Decision;
  accept: readonly string[] | undefined;
  size: "compact" | "regular";
}) {
  const send = useSendFile();
  const input = useRef<HTMLInputElement>(null);
  return (
    <>
      <Button
        variant="aurora"
        size={size}
        disabled={send.isPending}
        onClick={() => input.current?.click()}
      >
        <Upload /> {send.isPending ? "Sending…" : "Choose file"}
      </Button>
      <input
        ref={input}
        type="file"
        hidden
        data-testid="choose-file"
        accept={accept?.join(",")}
        onChange={(event) => {
          const file = event.target.files?.[0];
          event.target.value = "";
          if (file) send.mutate({ id: decision.id, file });
        }}
      />
    </>
  );
}

/**
 * A request not bound to a work item (a hire, a routine's activation, an app to connect), as
 * one card where it was asked: what it is, and its one action. A routine's activation reads as
 * its proposal.
 */
export function DecisionCard({ decision }: { decision: NeedsYouRequest }) {
  if (decision.routine) return <RoutineProposal decision={decision} routine={decision.routine} />;
  return <RequestCard decision={decision} />;
}

function RequestCard({ decision }: { decision: NeedsYouRequest }) {
  const employeeName = useEmployeeName();
  return (
    <Card>
      <div className="flex flex-col items-start gap-2.5" data-testid="request-card">
        <span className="flex items-center gap-2 text-heading font-semibold text-ink">
          {decision.kind === "connect" && decision.app && (
            <AppLogo logo={decision.app.logo} name={decision.app.name} size={24} />
          )}
          {requestTitle(decision)}
        </span>
        <span className="text-detail text-ink-2">
          {employeeName(decision.employee_id)}{" "}
          {decision.kind === "decision" ? "asked to run this exactly:" : "asks you"}
        </span>
        {decision.kind !== "connect" && <RequestDetails decision={decision} />}
        <RequestActions decision={decision} />
      </div>
    </Card>
  );
}
