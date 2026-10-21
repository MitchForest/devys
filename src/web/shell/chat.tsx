import {
  ArrowUp,
  Check,
  AudioLines,
  CircleAlert,
  Copy,
  CornerUpLeft,
  Hand,
  Eye,
  MessageSquarePlus,
  Mic,
  Reply,
  Smile,
  X,
} from "lucide-react";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import type { Employee } from "../../identity/contract.ts";
import { answerersOf, draft, useDraft, type Conversation } from "../app/conversation.ts";
import { employeeOf } from "../../conversations/contract.ts";
import { capturing, modeOf } from "../app/voice.ts";
import {
  endsGroup,
  startsGroup,
  timeline,
  type Bubble as TimelineBubble,
} from "../app/timeline.ts";
import { useDecisions, useEmployees, useOperations, usePerson, useWork } from "../app/data.ts";
import { useStartThread } from "../app/mutations.ts";
import { usePlace } from "../app/navigation.ts";
import { ui } from "../app/ui.ts";
import {
  useMicLevel,
  useReference,
  useSendDraft,
  useVoice,
  useVoiceActions,
} from "../app/workspace.tsx";
import { templateTitle } from "../app/names.ts";
import { PersonPortrait } from "../design/face.tsx";
import { InlineMarkdown } from "../design/markdown.tsx";
import { EmployeePortrait } from "../design/portrait.tsx";
import { Spinner } from "../design/spinner.tsx";
import { DecisionCard } from "../panel/work.tsx";
import { RecordCard, ViewedRecord } from "../panel/layers/registry.tsx";
import { useRecordTitle } from "../panel/layers/titles.ts";
import { PausedBanner } from "../panel/desk.tsx";
import { Bubble, BubbleContent, BubbleReactions } from "@/components/ui/bubble";
import {
  ContextMenu,
  ContextMenuContent,
  ContextMenuItem,
  ContextMenuSeparator,
  ContextMenuTrigger,
} from "@/components/ui/context-menu";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  InputGroup,
  InputGroupAddon,
  InputGroupButton,
  InputGroupTextarea,
} from "@/components/ui/input-group";
import { Message, MessageAvatar, MessageContent, MessageFooter } from "@/components/ui/message";
import {
  MessageScroller,
  MessageScrollerButton,
  MessageScrollerContent,
  MessageScrollerItem,
  MessageScrollerProvider,
  MessageScrollerViewport,
} from "@/components/ui/message-scroller";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { dateTime, relativeDay } from "../lib/format.ts";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";

const quick = ["👍", "👎", "❤️", "‼️", "❓", "😂"];
const avatarSize = 26;

/** Who wrote a message, for names and quoted replies. */
function useAuthorName() {
  const person = usePerson();
  const employees = useEmployees();
  return (author: string) => {
    const employee = employeeOf(author);
    if (employee) return employees.find((e) => e.id === employee)?.name ?? "A former employee";
    if (author === `person:${person?.id}`) return "You";
    return author === "system" ? "Devys" : "A teammate";
  };
}

/**
 * A conversation laid out like Messages: yours on the right in indigo, everyone else's on
 * the left beside their face and name. Hand-offs show as cards that open the work item.
 */
export function ConversationView({
  conversation,
  empty,
  className,
}: {
  conversation: Conversation;
  empty: ReactNode;
  className?: string;
}) {
  const person = usePerson();
  const decisions = useDecisions().data;
  const employees = useEmployees();
  const place = usePlace();
  const [loadingOlder, setLoadingOlder] = useState(false);
  const { messages: history, pending, key } = conversation;
  const items = history ? timeline(history, pending, `person:${person?.id}`, new Date()) : [];
  // Requests waiting on the owner: from this DM's employee, or about this work item.
  const ref = key?.slice(key.indexOf(":") + 1);
  // Requests wait where they were asked: a work item's in its thread, others in the DM. A
  // channel shows none; its threads' cards say they need the owner. Home's are in Needs you.
  const waiting = (decisions ?? []).filter((d) =>
    place.kind === "home"
      ? false
      : key?.startsWith("direct:")
        ? d.employee_id === ref && !d.work_item_id
        : key?.startsWith("work:")
          ? d.work_item_id === ref
          : false,
  );
  const lastMine = items.findLastIndex((item) => item.kind !== "heading" && item.bubble.mine);
  return (
    // Opens at the newest message; a message the owner sends moves to the top, with the
    // answer arriving beneath it.
    <MessageScrollerProvider defaultScrollPosition="end" autoScroll>
      <MessageScroller>
        <MessageScrollerViewport>
          <MessageScrollerContent className={cn("mx-auto w-full gap-0 p-3.5", className)}>
            {conversation.status === "pending" ? (
              <div className="flex justify-center pt-16">
                <Spinner />
              </div>
            ) : conversation.status === "error" && !history ? (
              <p role="alert" className="text-body text-ink-3">
                {conversation.problem}
              </p>
            ) : (
              <>
                {items.length === 0 && (
                  <div className="flex flex-col items-center gap-2.5 pt-16 text-center">
                    {empty}
                  </div>
                )}
                {conversation.hasOlder && (
                  <div className="flex justify-center">
                    <Button
                      variant="quiet"
                      size="compact"
                      disabled={loadingOlder}
                      onClick={() => {
                        setLoadingOlder(true);
                        void conversation.loadOlder().finally(() => setLoadingOlder(false));
                      }}
                    >
                      {loadingOlder ? "Loading…" : "Earlier messages"}
                    </Button>
                  </div>
                )}
                {items.map((item, index) =>
                  item.kind === "heading" ? (
                    <MessageScrollerItem key={item.id}>
                      <p className="pt-3.5 pb-0.5 text-center text-caption text-ink-3">
                        {relativeDay(item.date)}
                      </p>
                    </MessageScrollerItem>
                  ) : (
                    <MessageScrollerItem
                      key={item.id}
                      scrollAnchor={item.bubble.mine && index === lastMine}
                      className={startsGroup(item.bubble) ? "pt-2.5" : "pt-0.5"}
                    >
                      {item.bubble.kind === "event" ? (
                        <RecordCard value={item.bubble.ref} text={item.bubble.text} />
                      ) : (
                        <MessageRow bubble={item.bubble} conversation={conversation} />
                      )}
                    </MessageScrollerItem>
                  ),
                )}
                {conversation.working.map((id) => {
                  const employee = employees.find((e) => e.id === id);
                  return (
                    employee && (
                      <MessageScrollerItem key={`working-${id}`} className="pt-2.5">
                        <WorkingRow employee={employee} />
                      </MessageScrollerItem>
                    )
                  );
                })}
                {waiting.map((decision) => (
                  <MessageScrollerItem key={decision.id} className="pt-2.5">
                    <DecisionCard decision={decision} />
                  </MessageScrollerItem>
                ))}
              </>
            )}
          </MessageScrollerContent>
        </MessageScrollerViewport>
        <MessageScrollerButton className="shadow-raised" />
      </MessageScroller>
    </MessageScrollerProvider>
  );
}

/** One bubble. The corner toward the sender's edge tightens inside a group; the group's last bubble keeps the tail. */
function radius(bubble: TimelineBubble) {
  const top = startsGroup(bubble) ? 18 : 6;
  const bottom = endsGroup(bubble) ? 4 : 6;
  return bubble.mine ? `18px ${top}px ${bottom}px 18px` : `${top}px 18px 18px ${bottom}px`;
}

function MessageRow({
  bubble,
  conversation,
}: {
  bubble: TimelineBubble;
  conversation: Conversation;
}) {
  const employees = useEmployees();
  const operations = useOperations();
  const work = useWork().data;
  const place = usePlace();
  const start = useStartThread();
  const nameOf = useAuthorName();
  const [picking, setPicking] = useState(false);
  // A thread starts from a message anywhere but inside a thread.
  const threads = place.kind !== "thread" && !bubble.delivery;
  /** A work item owned by whoever the message addressed, in the project it was said in. */
  const startThread = () => {
    const mentions = conversation.messages?.find((m) => m.id === bubble.id)?.mentions ?? [];
    const author = employeeOf(bubble.author);
    const owner =
      author ??
      mentions[0] ??
      answerersOf(conversation, draft.get(conversation.key).text, employees).to[0] ??
      operations?.id;
    if (!owner) return;
    const projectId =
      place.kind === "project"
        ? place.id
        : place.kind === "thread"
          ? (work?.find((w) => w.id === place.workId)?.project_id ?? undefined)
          : undefined;
    start.mutate({ text: bubble.text, owner, ...(projectId ? { projectId } : {}) });
  };
  const mine = bubble.mine;
  const speaker = employees.find((e) => e.id === employeeOf(bubble.author));
  const reacts = Boolean(speaker) && !bubble.delivery;
  const replies = !bubble.delivery;
  const align = mine ? "end" : "start";
  const replied = bubble.replyTo
    ? conversation.messages?.find((m) => m.id === bubble.replyTo)
    : undefined;
  return (
    <Message align={align} className="group/row items-end gap-2 text-body">
      {!mine && (
        <MessageAvatar className="min-w-0 self-end bg-transparent" style={{ width: avatarSize }}>
          {endsGroup(bubble) &&
            (speaker ? (
              <EmployeePortrait employee={speaker} size={avatarSize} />
            ) : (
              <PersonPortrait name={nameOf(bubble.author)} size={avatarSize} />
            ))}
        </MessageAvatar>
      )}
      <MessageContent className="gap-[3px]">
        {!mine && startsGroup(bubble) && (
          <span className="px-3 text-caption text-ink-3" data-testid="speaker">
            {nameOf(bubble.author)}
          </span>
        )}
        {replied && (
          <div
            className={cn("flex items-center gap-1.5", mine ? "justify-end pl-16" : "pr-16")}
            data-testid="quoted"
          >
            <CornerUpLeft className="size-3 shrink-0 text-ink-3" />
            <span className="line-clamp-2 rounded-workspace border border-hairline px-2.5 py-[5px] text-detail text-ink-2">
              <span className="font-medium text-ink">{nameOf(replied.author)}</span>{" "}
              {replied.text.slice(0, 200)}
            </span>
          </div>
        )}
        <div className={cn("flex items-end gap-1", mine ? "flex-row-reverse pl-12" : "pr-12")}>
          <Popover open={picking} onOpenChange={setPicking}>
            <ContextMenu>
              <ContextMenuTrigger
                render={
                  <Bubble
                    align={align}
                    variant={mine ? "default" : "muted"}
                    className={cn("max-w-full", bubble.reactions.length > 0 && "mt-3")}
                    title={bubble.sentAt && dateTime(bubble.sentAt)}
                  />
                }
              >
                <BubbleContent
                  className={cn(
                    "rounded-none px-3 py-[7px] text-body leading-[1.4] select-text",
                    mine
                      ? "bg-indigo! text-white! [&_a]:text-white"
                      : "bg-track! text-ink [&_a]:text-indigo",
                    bubble.delivery === "sending" && "opacity-75",
                    bubble.delivery === "failed" && "opacity-55",
                  )}
                  style={{ borderRadius: radius(bubble) }}
                >
                  <InlineMarkdown text={bubble.text} />
                </BubbleContent>
                {bubble.reactions.length > 0 && (
                  <BubbleReactions
                    side="top"
                    align={mine ? "start" : "end"}
                    className="-translate-y-[60%] border border-hairline bg-sheet px-1.5 py-[3px] text-[13px] shadow-raised ring-0"
                    aria-label={`Reacted ${bubble.reactions.join("")}`}
                  >
                    {bubble.reactions.join("")}
                  </BubbleReactions>
                )}
              </ContextMenuTrigger>
              <ContextMenuContent>
                {reacts && (
                  <>
                    {quick.map((emoji) => (
                      <ContextMenuItem
                        key={emoji}
                        onClick={() => conversation.react(bubble.id, emoji)}
                      >
                        {bubble.reactions.includes(emoji) ? `${emoji} Remove` : emoji}
                      </ContextMenuItem>
                    ))}
                    <ContextMenuSeparator />
                  </>
                )}
                {replies && (
                  <ContextMenuItem onClick={() => conversation.reply(bubble.id)}>
                    <Reply /> Reply
                  </ContextMenuItem>
                )}
                {threads && (
                  <ContextMenuItem onClick={startThread}>
                    <MessageSquarePlus /> Start a thread
                  </ContextMenuItem>
                )}
                <ContextMenuItem
                  onClick={() =>
                    void navigator.clipboard.writeText(bubble.text).catch(() => undefined)
                  }
                >
                  <Copy /> Copy
                </ContextMenuItem>
              </ContextMenuContent>
            </ContextMenu>
            {/* Hover affordances; the context menu carries the same actions. */}
            {replies && (
              <div className="flex shrink-0 opacity-0 transition-opacity duration-150 group-hover/row:opacity-100 focus-within:opacity-100">
                {reacts && (
                  <PopoverTrigger render={<ChatActionButton label="React" />}>
                    <Smile />
                  </PopoverTrigger>
                )}
                <ChatActionButton label="Reply" onClick={() => conversation.reply(bubble.id)}>
                  <Reply />
                </ChatActionButton>
                {threads && (
                  <ChatActionButton label="Start a thread" onClick={startThread}>
                    <MessageSquarePlus />
                  </ChatActionButton>
                )}
              </div>
            )}
            <PopoverContent side="top" className="w-auto flex-row gap-1 rounded-full p-2">
              {quick.map((emoji) => (
                <button
                  key={emoji}
                  type="button"
                  aria-label={emoji}
                  className={cn(
                    "grid size-[34px] place-items-center rounded-full text-[20px] hover:bg-well",
                    bubble.reactions.includes(emoji) && "bg-indigo/18",
                  )}
                  onClick={() => {
                    setPicking(false);
                    conversation.react(bubble.id, emoji);
                  }}
                >
                  {emoji}
                </button>
              ))}
            </PopoverContent>
          </Popover>
        </div>
        {bubble.ref && (
          <div className={cn("flex px-3", mine && "justify-end")}>
            <ViewedRecord value={bubble.ref} />
          </div>
        )}
        {(bubble.delivery || (bubble.viaVoice && endsGroup(bubble))) && (
          <MessageFooter className="px-0 text-caption font-normal text-ink-3">
            {bubble.delivery === "sending" ? (
              "Sending…"
            ) : bubble.delivery === "delivered" ? (
              "Delivered"
            ) : bubble.delivery === "failed" ? (
              <button
                type="button"
                role={bubble.error ? "alert" : undefined}
                className="inline-flex items-center gap-1 text-left text-red"
                onClick={() => conversation.retry(bubble.id)}
              >
                <CircleAlert className="size-3 shrink-0 fill-red text-sheet" />
                {bubble.error ?? "Not delivered"} · Try again
              </button>
            ) : (
              "Dictated"
            )}
          </MessageFooter>
        )}
      </MessageContent>
    </Message>
  );
}

function ChatActionButton({
  label,
  children,
  ...props
}: React.ComponentProps<"button"> & { label: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className="grid size-6 place-items-center rounded-full text-ink-3 hover:text-ink-2 [&_svg]:size-[14px]"
      {...props}
    >
      {children}
    </button>
  );
}

/** An employee answering: their face, three dots, and their name. */
function WorkingRow({ employee }: { employee: Employee }) {
  return (
    <div className="flex items-end gap-2" role="status">
      <EmployeePortrait employee={employee} size={avatarSize} mood="thinking" />
      <div className="flex flex-col gap-[3px]">
        <span className="px-3 text-caption text-ink-3">{employee.name} is working…</span>
        <div
          className="flex w-fit gap-1 bg-track px-3 py-2.5"
          style={{ borderRadius: "18px 18px 18px 4px" }}
        >
          {[0, 1, 2].map((i) => (
            <span
              key={i}
              className="size-1.5 animate-pulse rounded-full bg-ink-3"
              style={{ animationDelay: `${i * 175}ms` }}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

/** Shown above the composer while replying to a message. */
function ReplyBanner({ name, text, cancel }: { name: string; text: string; cancel: () => void }) {
  return (
    <div className="flex animate-in items-center gap-2 px-2 fade-in slide-in-from-bottom-1">
      <span className="h-[26px] w-[3px] rounded-full bg-indigo" />
      <div className="flex min-w-0 flex-col gap-px">
        <span className="text-label font-medium text-indigo">Replying to {name}</span>
        <span className="truncate text-detail text-ink-2">{text}</span>
      </div>
      <button
        type="button"
        aria-label="Cancel reply"
        className="ml-auto text-ink-3 hover:text-ink-2"
        onClick={cancel}
      >
        <X className="size-4" />
      </button>
    </div>
  );
}

/**
 * The composer: who answers (the To chip), a tinted field with @-mentions, the mic and the
 * aurora send button, as native `Composer`.
 */
export function Composer({
  conversation,
  label,
  className,
}: {
  conversation: Conversation;
  /** "Message <name>", for the field. */
  label: string;
  className?: string;
}) {
  const employees = useEmployees();
  const voice = useVoice((state) => state.phase);
  const conversationMode = useVoice((state) => state.conversationMode);
  const volatileText = useVoice((state) => state.volatileText);
  const voiceError = useVoice((state) => state.error);
  const voiceActions = useVoiceActions();
  const reference = useReference();
  const recordTitle = useRecordTitle();
  const sendDraft = useSendDraft();
  const nameOf = useAuthorName();
  const field = useRef<HTMLTextAreaElement>(null);
  const { replyingTo } = conversation;
  const text = useDraft(conversation.key);
  const setDraft = (next: string) => draft.set(conversation.key, next);
  const { mentions, to } = answerersOf(conversation, text, employees);
  useEffect(() => {
    if (replyingTo) field.current?.focus();
  }, [replyingTo]);
  const served = true;
  const listening = served && modeOf(voice) === "dictation";
  // Typing "@name" at the end of the draft offers matching employees, as in Slack.
  const typed = /(?:^|\s)@([^\s@]*)$/.exec(text)?.[1];
  const choose = (employee: Employee) => {
    setDraft(text.replace(/@([^\s@]*)$/, `@${employee.name} `));
    field.current?.focus();
  };
  const matches =
    typed === undefined
      ? []
      : employees.filter(
          (e) => !mentions.includes(e.id) && e.name.toLowerCase().includes(typed.toLowerCase()),
        );
  // The highlighted match: arrows move it, Enter or Tab chooses it.
  const [active, setActive] = useState(0);
  const pickerId = useId();
  const highlighted = matches[Math.min(active, matches.length - 1)];
  useEffect(() => setActive(0), [typed]);
  const pickWithKeys = (event: React.KeyboardEvent) => {
    if (!highlighted) return false;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      const step = event.key === "ArrowDown" ? 1 : matches.length - 1;
      setActive((index) => (Math.min(index, matches.length - 1) + step) % matches.length);
    } else if (event.key === "Enter" || event.key === "Tab") choose(highlighted);
    else return false;
    event.preventDefault();
    return true;
  };
  const answerer = to.length === 1 ? employees.find((e) => e.id === to[0]) : undefined;
  // The field names who answers, so no separate "To" row is needed.
  const answering = to.flatMap((id) => employees.find((e) => e.id === id)?.name ?? []).join(", ");
  const placeholder = !answering
    ? label
    : label === "Reply"
      ? `Reply to ${answering}`
      : `Message ${answering}`;
  return (
    <div className={cn("mx-auto flex w-full flex-col gap-2 p-2.5", className)}>
      {served && voiceError && (
        <div role="alert" className="flex items-center gap-2 px-1.5">
          <CircleAlert className="size-4 shrink-0 fill-amber text-sheet" />
          <span className="text-detail text-ink-2">{voiceError}</span>
          <button
            type="button"
            aria-label="Dismiss"
            className="ml-auto text-ink-3 hover:text-ink-2"
            onClick={voiceActions.dismissError}
          >
            <X className="size-3.5" />
          </button>
        </div>
      )}
      {replyingTo && !(served && conversationMode) && (
        <ReplyBanner
          name={nameOf(replyingTo.author)}
          text={replyingTo.text}
          cancel={conversation.cancelReply}
        />
      )}
      {matches.length > 0 && (
        <MentionPicker id={pickerId} matches={matches} active={highlighted?.id} choose={choose} />
      )}
      {reference && (
        <div className="flex items-center px-1">
          {reference && (
            <span
              className="flex min-w-0 items-center gap-1 rounded-full bg-sheet-tint py-0.5 pr-1 pl-2 text-caption text-ink-2"
              data-testid="reference-chip"
              title="What you're looking at goes with your message"
            >
              <Eye className="size-3 shrink-0 text-ink-3" />
              <span className="truncate">Viewing {recordTitle(reference)}</span>
              <button
                type="button"
                aria-label="Don't send what you're viewing"
                onClick={() => ui.setReferencing(false)}
                className="grid size-4 place-items-center rounded-full text-ink-3 hover:text-ink-2"
              >
                <X className="size-3" />
              </button>
            </span>
          )}
        </div>
      )}
      {answerer?.paused && <PausedBanner employee={answerer} />}
      {served && conversationMode ? (
        <ConversationStrip />
      ) : (
        <div className="flex flex-col gap-1.5">
          {listening && volatileText && (
            <p
              className="line-clamp-2 px-3.5 text-body text-ink-3"
              aria-label={`Hearing: ${volatileText}`}
            >
              {volatileText}
            </p>
          )}
          <InputGroup
            className={cn(
              "h-auto items-end gap-1.5 rounded-bubble border-[1.5px] bg-sheet-tint py-[5px] pr-[5px] pl-[5px] has-[[data-slot=input-group-control]:focus-visible]:ring-0",
              listening ? "border-indigo/45" : "border-transparent focus-within:border-indigo/30",
            )}
          >
            <InputGroupAddon align="inline-start" className="p-0">
              <AnswererPicker conversation={conversation} to={to} />
            </InputGroupAddon>
            <InputGroupTextarea
              ref={field}
              aria-label={label}
              placeholder={listening ? "Listening…" : placeholder}
              rows={1}
              value={text}
              onChange={(event) => setDraft(event.target.value)}
              aria-controls={matches.length > 0 ? pickerId : undefined}
              aria-activedescendant={highlighted ? `${pickerId}-${highlighted.id}` : undefined}
              onKeyDown={(event) => {
                if (event.nativeEvent.isComposing || pickWithKeys(event)) return;
                if (event.key === "Enter" && !event.shiftKey) {
                  event.preventDefault();
                  sendDraft();
                }
              }}
              className="max-h-[132px] min-h-7 resize-none p-0 py-[5px] text-body leading-[1.35] text-ink placeholder:text-ink-3"
            />
            <InputGroupAddon align="inline-end" className="gap-1 p-0">
              <MicButton listening={listening} />
              {/* An empty field offers talking instead of sending, as in ChatGPT. */}
              {text.trim() ? (
                <InputGroupButton
                  aria-label="Send"
                  onClick={sendDraft}
                  className="aurora size-7 rounded-full p-0 text-white [&_svg]:size-3.5"
                >
                  <ArrowUp strokeWidth={3} />
                </InputGroupButton>
              ) : (
                <InputGroupButton
                  aria-label="Talk hands-free"
                  title="Talk hands-free: speak, hear the answer, keep talking"
                  onClick={voiceActions.conversationToggled}
                  className="aurora size-7 rounded-full p-0 text-white [&_svg]:size-3.5"
                >
                  <AudioLines strokeWidth={2.6} />
                </InputGroupButton>
              )}
            </InputGroupAddon>
          </InputGroup>
        </div>
      )}
    </div>
  );
}

/**
 * Who answers the next message, as the server decides (those mentioned, else the author of
 * the message replied to, else whoever spoke last): their face inside the field. Tap to have
 * someone else answer.
 */
function AnswererPicker({
  conversation,
  to: answering,
}: {
  conversation: Conversation;
  to: readonly string[];
}) {
  const employees = useEmployees();
  const to = answering.flatMap((id) => employees.find((e) => e.id === id) ?? []);
  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        aria-label={`Change who answers, now ${to.map((e) => e.name).join(", ") || "no one"}`}
        title="Who answers"
        data-testid="to-chip"
        className="flex h-7 items-center rounded-full px-[3px] transition-colors hover:bg-track"
      >
        {to.length === 0 ? (
          <span className="grid size-[22px] place-items-center rounded-full border border-dashed border-ink-3/50" />
        ) : (
          <span
            className="flex -space-x-1.5"
            data-testid="to-names"
            data-names={to.map((e) => e.name).join(", ")}
          >
            {to.slice(0, 3).map((employee) => (
              <EmployeePortrait key={employee.id} employee={employee} size={22} />
            ))}
          </span>
        )}
      </DropdownMenuTrigger>
      <DropdownMenuContent side="top" align="start" className="w-auto min-w-52">
        <DropdownMenuGroup>
          <DropdownMenuLabel className="text-caption font-normal text-ink-3">
            Who answers
          </DropdownMenuLabel>
          {employees.map((employee) => (
            <DropdownMenuItem key={employee.id} onClick={() => conversation.pick(employee.id)}>
              <EmployeePortrait employee={employee} size={18} />
              {employee.name}
              {answering.includes(employee.id) && <Check className="ml-auto size-3.5 text-ink-2" />}
            </DropdownMenuItem>
          ))}
        </DropdownMenuGroup>
        {conversation.picked && (
          <>
            <DropdownMenuSeparator />
            <DropdownMenuItem onClick={() => conversation.pick(undefined)}>
              <X /> Whoever would answer
            </DropdownMenuItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** Employees matching what follows "@"; choosing one inserts "@Name " and mentions them. */
function MentionPicker({
  id,
  matches,
  active,
  choose,
}: {
  id: string;
  matches: Employee[];
  active: string | undefined;
  choose: (employee: Employee) => void;
}) {
  return (
    <div
      id={id}
      role="listbox"
      aria-label="Mention"
      className="flex animate-in flex-col gap-0.5 rounded-row border border-hairline bg-sheet p-1 shadow-raised fade-in slide-in-from-bottom-1"
    >
      {matches.map((employee) => (
        <button
          key={employee.id}
          id={`${id}-${employee.id}`}
          type="button"
          role="option"
          tabIndex={-1}
          aria-selected={employee.id === active}
          onMouseDown={(event) => event.preventDefault()}
          onClick={() => choose(employee)}
          className={cn(
            "flex items-center gap-2 rounded-small px-2 py-1.5 text-left text-control text-ink hover:bg-sheet-tint",
            employee.id === active && "bg-sheet-tint",
          )}
        >
          <EmployeePortrait employee={employee} size={20} />
          {employee.name}
          <span className="ml-auto pl-3 text-caption text-ink-3">
            {templateTitle(employee.template)}
          </span>
        </button>
      ))}
    </div>
  );
}

/** Tap to dictate into the field; the words stay there to edit before sending. */
function MicButton({ listening }: { listening: boolean }) {
  const voice = useVoiceActions();
  // The level changes every frame while listening; only this button redraws for it.
  const level = useMicLevel(listening);
  return (
    <button
      type="button"
      aria-label={listening ? "Stop dictating" : "Dictate"}
      title={listening ? "Stop dictating" : "Dictate"}
      onClick={voice.micTapped}
      className={cn(
        "relative grid size-7 place-items-center rounded-full",
        listening ? "text-indigo" : "text-ink-2 hover:text-ink",
      )}
    >
      <span
        className="absolute inset-0 rounded-full bg-indigo transition-[opacity,scale] duration-100"
        style={{
          opacity: listening ? 0.12 + level * 0.35 : 0,
          scale: listening ? 1 + level * 0.5 : 1,
        }}
      />
      <Mic className={cn("relative size-[15px]", listening && "fill-current")} strokeWidth={2.2} />
    </button>
  );
}

/** Hands-free conversation: what's happening, a live level, and a way out. */
function ConversationStrip() {
  const voice = useVoice((state) => state.phase);
  const volatileText = useVoice((state) => state.volatileText);
  const actions = useVoiceActions();
  const active = capturing(voice);
  const level = useMicLevel(active);
  const phase =
    voice.kind === "starting"
      ? "Getting ready…"
      : voice.kind === "listening"
        ? "Listening"
        : voice.kind === "finishing"
          ? "Sending…"
          : voice.kind === "awaitingReply"
            ? "Thinking…"
            : voice.kind === "speaking"
              ? "Speaking"
              : "Paused";
  return (
    <div
      className={cn(
        "flex items-center gap-3 rounded-bubble border-[1.5px] bg-sheet-tint px-3.5 py-2.5",
        active ? "border-indigo/45" : "border-indigo/15",
      )}
    >
      <span className="flex size-7 items-center justify-center gap-[3px]" aria-hidden>
        {[14, 22, 18, 10].map((height, index) => (
          <span
            key={index}
            className={cn(
              "w-1 rounded-full bg-indigo transition-[height] duration-100",
              !active && "opacity-35",
            )}
            style={{ height: 6 + (active ? level : 0) * height }}
          />
        ))}
      </span>
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="text-body font-semibold text-ink" role="status">
          {phase}
        </span>
        {volatileText && (
          <span className="line-clamp-2 text-detail text-ink-3">{volatileText}</span>
        )}
      </div>
      <span className="ml-auto" />
      {voice.kind === "speaking" && (
        <Button size="compact" onClick={actions.stopSpeaking}>
          <Hand /> Interrupt
        </Button>
      )}
      <Button variant="quiet" size="compact" onClick={actions.conversationToggled}>
        <X /> End
      </Button>
    </div>
  );
}
