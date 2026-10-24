import { ArrowUp } from "lucide-react";
import { useState } from "react";
import type { ConversationKey } from "../../conversations/contract.ts";
import { useBusinessId, useEmployees, useWork } from "../app/data.ts";
import { useConversation } from "../app/conversation.ts";
import { ConversationView } from "../shell/chat.tsx";
import { Button } from "@/components/ui/button";
import { WorkCard } from "./work-card.tsx";

/**
 * A work item beside the conversation on screen, whichever it is: its card (the plan, what its
 * employee is doing now, the one thing asked of the owner, the results), then what was said
 * about it (hand-offs, answers, a question card), and a field to reply to whoever is on it.
 */
export function WorkView({ id }: { id: string }) {
  const businessId = useBusinessId();
  const employees = useEmployees();
  const item = useWork().data?.find((w) => w.id === id);
  const owner = employees.find((e) => e.id === item?.owner_employee_id);
  const key: ConversationKey = `work:${id}`;
  const conversation = useConversation(key, { businessId, employees, visible: true });
  return (
    <div className="flex h-full flex-col" data-testid="work-view">
      <div className="shrink-0">
        <WorkCard id={id} />
      </div>
      <div className="min-h-0 flex-1">
        <ConversationView
          conversation={conversation}
          empty={<span className="text-body text-ink-3">Nothing said about this yet.</span>}
        />
      </div>
      <WorkReply
        label={`Reply to ${owner?.name ?? "them"}`}
        send={(text) => conversation.send(text)}
      />
    </div>
  );
}

/** One line to answer whoever is on the work; Enter sends, Shift-Enter starts a new line. */
function WorkReply({ label, send }: { label: string; send: (text: string) => void }) {
  const [text, setText] = useState("");
  const submit = () => {
    if (!text.trim()) return;
    send(text);
    setText("");
  };
  return (
    <form
      className="mx-3 mb-3 flex shrink-0 items-end gap-2 rounded-[20px] bg-well py-1.5 pr-1.5 pl-3.5"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
    >
      <textarea
        aria-label={label}
        placeholder={label}
        rows={1}
        value={text}
        onChange={(event) => setText(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
            event.preventDefault();
            submit();
          }
        }}
        className="max-h-32 min-h-7 flex-1 resize-none bg-transparent py-1 text-body leading-[1.4] text-ink outline-none placeholder:text-ink-3 [field-sizing:content]"
      />
      <Button
        type="submit"
        aria-label="Send"
        disabled={!text.trim()}
        className="size-7 rounded-full bg-indigo p-0 text-white hover:bg-[color-mix(in_oklab,var(--indigo),black_12%)] hover:text-white disabled:bg-ink-3/30 disabled:opacity-100 [&_svg]:size-3.5"
      >
        <ArrowUp />
      </Button>
    </form>
  );
}
