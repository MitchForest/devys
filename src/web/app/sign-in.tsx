/**
 * Signing in on the web, with nothing to type (.docs/PRODUCT_EXPERIENCE.md "Signing in"): a
 * one-time link from the Mac app or `bun run local install` signs a browser on the Mac in; any
 * other browser shows one button, "Connect to <Mac>", and is let in from a signed-in device, both
 * screens showing the same two emoji. Signed in with no business yet: name it, and start.
 */
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { api, type StartingRole } from "./api.ts";
import { useCreateBusiness } from "./mutations.ts";
import { keys } from "./query.ts";
import { Face } from "../design/face.tsx";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";

/** The Devys mark: the same Face on every sign-in screen, native and web. */
const mark = { palette: "blue", shape: "roundedSquare", seed: 7 } as const;

/** The one centered column every sign-in screen is. */
function Centered({ children }: { children: React.ReactNode }) {
  return (
    <main className="grid min-h-dvh place-items-center bg-frame p-6">
      <div className="flex w-full max-w-[320px] flex-col items-center gap-7 text-center">
        {children}
      </div>
    </main>
  );
}

/** One short line under the button: what is happening, or what went wrong. */
const Line = ({ children, alert }: { children?: React.ReactNode; alert?: boolean }) => (
  <p role={alert ? "alert" : undefined} className="min-h-5 text-body text-ink-3">
    {children}
  </p>
);

const hex = (bytes: ArrayBuffer | Uint8Array) =>
  Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");

/** What this browser calls itself in the prompt and the device list: "Safari on iPad". */
export function browserName(agent: string) {
  const browser = /Edg\//.test(agent)
    ? "Edge"
    : /Firefox\//.test(agent)
      ? "Firefox"
      : /Chrome\//.test(agent)
        ? "Chrome"
        : /Safari\//.test(agent)
          ? "Safari"
          : "A browser";
  const place = /iPhone/.test(agent)
    ? "iPhone"
    : /iPad/.test(agent)
      ? "iPad"
      : /Android/.test(agent)
        ? "Android"
        : /Mac OS X/.test(agent)
          ? "Mac"
          : /Windows/.test(agent)
            ? "Windows"
            : /Linux/.test(agent)
              ? "Linux"
              : undefined;
  return place ? `${browser} on ${place}` : browser;
}

/** A one-time link's token in the address (`/#signin=<token>`), removed once read. */
function linkToken() {
  const token = /^#signin=([a-f0-9]{64})$/.exec(location.hash)?.[1];
  if (token) history.replaceState(null, "", location.pathname + location.search);
  return token;
}

type Phase =
  | { kind: "ready" }
  | { kind: "asking" }
  | { kind: "waiting"; id: string; token: string; match: readonly string[] };

/** Signed out: one button, "Connect to <Mac>". */
export function SignIn() {
  const client = useQueryClient();
  const hello = useQuery({ queryKey: ["hello"], queryFn: api.hello, retry: true });
  const [phase, setPhase] = useState<Phase>({ kind: "ready" });
  const [problem, setProblem] = useState<string>();
  const signedIn = () => client.refetchQueries({ queryKey: keys.me });

  // A one-time link opened here, on arrival or into this open page.
  useEffect(() => {
    const redeem = () => {
      const token = linkToken();
      if (!token) return;
      setPhase({ kind: "asking" });
      api.redeemLink(token).then(signedIn, () => {
        setPhase({ kind: "ready" });
        setProblem("That link has expired.");
      });
    };
    redeem();
    addEventListener("hashchange", redeem);
    return () => removeEventListener("hashchange", redeem);
  }, []);

  // Waiting: ask how it went until it is answered; allowed, the token becomes the cookie.
  useEffect(() => {
    if (phase.kind !== "waiting") return;
    let stopped = false;
    const check = async () => {
      if (stopped) return;
      try {
        const { status } = await api.joinStatus(phase.id, phase.token);
        if (status === "allowed") {
          await api.joinCookie(phase.id, phase.token);
          return void signedIn();
        }
        // Denied or expired: back to the button, with nothing to read.
        if (status !== "pending") return setPhase({ kind: "ready" });
      } catch {
        // A missed answer is asked again.
      }
      timer = setTimeout(check, 1_500);
    };
    let timer = setTimeout(check, 1_500);
    return () => {
      stopped = true;
      clearTimeout(timer);
    };
  }, [phase]);

  const connect = async () => {
    setProblem(undefined);
    setPhase({ kind: "asking" });
    try {
      const token = hex(crypto.getRandomValues(new Uint8Array(32)));
      const hash = hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)));
      const asked = await api.askToJoin(browserName(navigator.userAgent), hash);
      setPhase({ kind: "waiting", id: asked.id, token, match: asked.match });
    } catch {
      setPhase({ kind: "ready" });
      setProblem("Couldn't reach your Mac. Try again.");
    }
  };

  const name = hello.data?.name;
  if (phase.kind === "waiting")
    return (
      <Centered>
        <Face spec={mark} size={88} mood="thinking" label="Devys" />
        <p aria-label="Match" className="text-[44px] leading-none tracking-[0.2em]">
          {phase.match.join("")}
        </p>
        <Line>Allow on {name ?? "your Mac"}</Line>
      </Centered>
    );
  return (
    <Centered>
      <Face spec={mark} size={88} mood={problem ? "oops" : "idle"} label="Devys" />
      <Button
        variant="aurora"
        className="h-11 w-full justify-center px-6 text-[15px] [&>span]:w-full [&>span]:justify-center"
        disabled={!name || phase.kind === "asking"}
        onClick={() => void connect()}
      >
        {name ? `Connect to ${name}` : "Connect"}
      </Button>
      <Line alert={Boolean(problem)}>{problem ?? (name ? "" : "Looking for your Mac…")}</Line>
    </Centered>
  );
}

/**
 * Signed in: a device asking to join shows here at once, as the system would ask. Allow lets
 * it in as you; Deny, or closing, sends it back to its button.
 */
export function JoinPrompt() {
  const client = useQueryClient();
  const allowButton = useRef<HTMLButtonElement>(null);
  const joins = useQuery({ queryKey: ["joins"], queryFn: api.joins, refetchInterval: 2_000 });
  const asking = joins.data?.joins[0];
  const answer = useMutation({
    mutationFn: ({ id, allow }: { id: string; allow: boolean }) => api.answerJoin(id, allow),
    onSettled: () => client.invalidateQueries({ queryKey: ["joins"] }),
  });
  if (!asking) return null;
  const decide = (allow: boolean) => answer.mutate({ id: asking.id, allow });
  return (
    <Dialog open onOpenChange={(open) => !open && !answer.isPending && decide(false)}>
      <DialogContent
        showCloseButton={false}
        initialFocus={allowButton}
        className="w-[300px] justify-items-center gap-5 p-6 text-center"
      >
        <DialogTitle className="text-heading font-semibold text-ink">
          {asking.name} wants to join
        </DialogTitle>
        <p aria-label="Match" className="text-[36px] leading-none tracking-[0.2em]">
          {asking.match.join("")}
        </p>
        <div className="grid w-full grid-cols-2 gap-2">
          <Button
            className="justify-center"
            disabled={answer.isPending}
            onClick={() => decide(false)}
          >
            Deny
          </Button>
          <Button
            ref={allowButton}
            variant="aurora"
            className="justify-center [&>span]:justify-center"
            disabled={answer.isPending}
            onClick={() => decide(true)}
          >
            Allow
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** Hired with the Head of Operations when a business starts; changed later in Settings. */
const startingTeam: StartingRole[] = ["engineering", "growth", "business-operations"];

/** Signed in with no business yet: its name, a line about it if you like, and start. */
export function FirstBusiness() {
  const createBusiness = useCreateBusiness();
  const [name, setName] = useState("");
  const [brief, setBrief] = useState("");
  const [problem, setProblem] = useState<string>();
  const busy = createBusiness.isPending;
  return (
    <Centered>
      <Face
        spec={mark}
        size={88}
        mood={busy ? "thinking" : problem ? "oops" : "idle"}
        label="Devys"
      />
      <form
        aria-label="Name your business"
        className="flex w-full flex-col gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          if (!name.trim()) return;
          setProblem(undefined);
          createBusiness.mutate(
            { name, brief, team: startingTeam },
            { onError: () => setProblem("That didn't work. Try again.") },
          );
        }}
      >
        <h1 className="mb-2 text-title font-semibold tracking-tight text-ink">
          Name your business
        </h1>
        <Input
          autoFocus
          aria-label="Name"
          placeholder="Name"
          maxLength={80}
          value={name}
          onChange={(event) => setName(event.target.value)}
          className="h-11 rounded-row bg-sheet px-4 text-[15px]"
        />
        <Input
          aria-label="What it does"
          placeholder="What it does (optional)"
          maxLength={200}
          value={brief}
          onChange={(event) => setBrief(event.target.value)}
          className="h-11 rounded-row bg-sheet px-4 text-[15px]"
        />
        <Button
          variant="aurora"
          type="submit"
          disabled={busy || !name.trim()}
          className="mt-4 h-11 w-full justify-center text-[15px] [&>span]:w-full [&>span]:justify-center"
        >
          Start
        </Button>
        <Line alert={Boolean(problem)}>{problem}</Line>
      </form>
    </Centered>
  );
}
