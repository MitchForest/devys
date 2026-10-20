/**
 * The browser's speech: recognition and synthesis through the Web Speech API, the web's
 * counterpart to native `SpeechCaptureClient` and `SpeechPlaybackClient`.
 */

export type SpeechMode = "dictation" | "handsFree";
export type VoicePhase =
  | { kind: "idle" }
  | { kind: "starting" | "listening" | "finishing"; mode: SpeechMode }
  | { kind: "awaitingReply" }
  | { kind: "speaking" };
export const capturing = (phase: VoicePhase) =>
  phase.kind === "starting" || phase.kind === "listening" || phase.kind === "finishing";
export const modeOf = (phase: VoicePhase) =>
  capturing(phase) ? (phase as { mode: SpeechMode }).mode : undefined;

export type CaptureError =
  | "microphoneDenied"
  | "unsupportedLocale"
  | "noSpeech"
  | "interrupted"
  | "cancelled"
  | "unavailable";
export const errorMessage: Record<CaptureError, string> = {
  microphoneDenied:
    "Devys needs microphone access. Allow it in your browser's settings for this site.",
  unsupportedLocale: "Speech recognition isn't available for your language in this browser.",
  noSpeech: "Didn't catch anything.",
  interrupted: "Listening stopped because the microphone was lost.",
  cancelled: "",
  unavailable: "Speech isn't available in this browser. Try Chrome or Safari.",
};

export interface VoiceSettings {
  /** A `SpeechSynthesisVoice.voiceURI`, or null for the best available. */
  voiceURI: string | null;
  /** 0.5–1.5 times the default speaking rate. */
  rate: number;
  speaksReplies: boolean;
}
const settingsKey = "voiceSettings";
export function loadVoiceSettings(): VoiceSettings {
  try {
    const saved = JSON.parse(localStorage.getItem(settingsKey) ?? "{}") as Partial<VoiceSettings>;
    return {
      voiceURI: saved.voiceURI ?? null,
      rate: saved.rate ?? 1,
      speaksReplies: saved.speaksReplies ?? false,
    };
  } catch {
    return { voiceURI: null, rate: 1, speaksReplies: false };
  }
}
export function saveVoiceSettings(settings: VoiceSettings) {
  try {
    localStorage.setItem(settingsKey, JSON.stringify(settings));
  } catch {
    // Voice settings are a per-browser convenience, like native's per-device defaults.
  }
}

interface Recognition extends EventTarget {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  processLocally?: boolean;
  start(): void;
  stop(): void;
  abort(): void;
  onresult:
    | ((event: {
        resultIndex: number;
        results: ArrayLike<{ isFinal: boolean; 0: { transcript: string } }>;
      }) => void)
    | null;
  onerror: ((event: { error: string }) => void) | null;
  onend: (() => void) | null;
  onaudiostart: (() => void) | null;
}
type RecognitionClass = new () => Recognition;
const recognitionClass = () =>
  typeof window === "undefined"
    ? undefined
    : ((
        window as unknown as {
          SpeechRecognition?: RecognitionClass;
          webkitSpeechRecognition?: RecognitionClass;
        }
      ).SpeechRecognition ??
      (window as unknown as { webkitSpeechRecognition?: RecognitionClass })
        .webkitSpeechRecognition);
export interface CaptureHandlers {
  listening: () => void;
  transcript: (finalized: string, volatile: string) => void;
  level: (level: number) => void;
  /** Hands-free capture ends by itself when the owner stops speaking. */
  endOfSpeech: () => void;
  finished: (text: string) => void;
  failed: (error: CaptureError) => void;
}

/**
 * Starts listening. Dictation keeps listening until `finish`; hands-free ends at the
 * first pause. Prefers on-device recognition where the browser offers it.
 */
export function startCapture(mode: SpeechMode, handlers: CaptureHandlers) {
  const Recognition = recognitionClass();
  if (!Recognition) {
    queueMicrotask(() => handlers.failed("unavailable"));
    return { finish: () => undefined, cancel: () => undefined };
  }
  const recognition = new Recognition();
  recognition.continuous = mode === "dictation";
  recognition.interimResults = true;
  recognition.lang = navigator.language;
  if ("processLocally" in recognition) recognition.processLocally = true;
  let finalized = "";
  let volatile = "";
  let failure: CaptureError | undefined;
  let cancelled = false;
  let done = false;
  const meter = levelMeter(handlers.level);
  recognition.onaudiostart = () => handlers.listening();
  recognition.onresult = (event) => {
    volatile = "";
    let text = "";
    for (let i = 0; i < event.results.length; i++) {
      const result = event.results[i]!;
      if (result.isFinal) text += result[0].transcript;
      else volatile += result[0].transcript;
    }
    finalized = text.trim();
    handlers.transcript(finalized, volatile.trim());
  };
  recognition.onerror = (event) => {
    failure =
      event.error === "not-allowed" || event.error === "service-not-allowed"
        ? "microphoneDenied"
        : event.error === "no-speech"
          ? "noSpeech"
          : event.error === "audio-capture"
            ? "interrupted"
            : event.error === "language-not-supported"
              ? "unsupportedLocale"
              : event.error === "aborted"
                ? "cancelled"
                : "unavailable";
  };
  recognition.onend = () => {
    if (done) return;
    done = true;
    meter.stop();
    if (cancelled) return handlers.failed("cancelled");
    const text = `${finalized} ${volatile}`.trim();
    if (failure && !text) return handlers.failed(failure);
    if (mode === "handsFree") handlers.endOfSpeech();
    if (!text) return handlers.failed("noSpeech");
    handlers.finished(text);
  };
  recognition.start();
  return {
    finish: () => recognition.stop(),
    cancel: () => {
      cancelled = true;
      recognition.abort();
    },
  };
}

/** A live microphone level from 0 to 1, for the mic button and level bars. */
function levelMeter(report: (level: number) => void) {
  let stopped = false;
  let release = () => undefined as void;
  void navigator.mediaDevices
    ?.getUserMedia({ audio: true })
    .then((stream) => {
      if (stopped) return stream.getTracks().forEach((track) => track.stop());
      const context = new AudioContext();
      const analyser = context.createAnalyser();
      analyser.fftSize = 512;
      context.createMediaStreamSource(stream).connect(analyser);
      const samples = new Uint8Array(analyser.fftSize);
      let frame = 0;
      const tick = () => {
        analyser.getByteTimeDomainData(samples);
        let sum = 0;
        for (const sample of samples) sum += ((sample - 128) / 128) ** 2;
        report(Math.min(1, Math.sqrt(sum / samples.length) * 4));
        frame = requestAnimationFrame(tick);
      };
      tick();
      release = () => {
        cancelAnimationFrame(frame);
        stream.getTracks().forEach((track) => track.stop());
        void context.close();
      };
    })
    .catch(() => undefined);
  return {
    stop: () => {
      stopped = true;
      release();
      report(0);
    },
  };
}

export const availableVoices = () =>
  typeof speechSynthesis === "undefined"
    ? []
    : speechSynthesis
        .getVoices()
        .filter((voice) => voice.lang.startsWith(navigator.language.slice(0, 2)));

/** Reads a reply aloud with the owner's voice and rate; resolves when it ends or is stopped. */
export function speak(text: string, settings: VoiceSettings) {
  return new Promise<void>((resolve) => {
    if (typeof speechSynthesis === "undefined") return resolve();
    const utterance = new SpeechSynthesisUtterance(text.replace(/[*_`#>]/g, ""));
    const voice = speechSynthesis.getVoices().find((v) => v.voiceURI === settings.voiceURI);
    if (voice) utterance.voice = voice;
    utterance.rate = settings.rate;
    utterance.onend = () => resolve();
    utterance.onerror = () => resolve();
    speechSynthesis.cancel();
    speechSynthesis.speak(utterance);
  });
}

export const stopSpeaking = () =>
  typeof speechSynthesis !== "undefined" && speechSynthesis.cancel();

/** Merges dictated speech into text already typed, as native `TranscriptionDraft`. */
export function mergeDraft(initial: string, transcript: string) {
  const base = initial.trim();
  const spoken = transcript.trim();
  if (!base) return spoken;
  if (!spoken) return initial;
  return initial + (/\s$/.test(initial) ? "" : " ") + spoken;
}
