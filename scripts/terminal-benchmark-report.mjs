#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";

const DEFAULT_LAST = "30m";
const TRACE_NAME = "terminal-open";
const PREDICATE = 'subsystem == "com.devys.mac-client" AND category == "WorkspacePerformance"';

const PAIRS = [
  ["open_request", "tab_visible"],
  ["host_ensure_start", "host_ready"],
  ["open_request", "first_frame_commit"],
  ["open_request", "first_interactive_frame"],
  ["attach_start", "first_frame_commit"],
  ["first_output_chunk", "first_frame_commit"],
];

const args = process.argv.slice(2);
let inputPath = null;
let lastWindow = DEFAULT_LAST;

for (let index = 0; index < args.length; index += 1) {
  const argument = args[index];
  if (argument === "--input") {
    inputPath = args[index + 1] ?? null;
    index += 1;
    continue;
  }
  if (argument === "--last") {
    lastWindow = args[index + 1] ?? DEFAULT_LAST;
    index += 1;
    continue;
  }
}

const rawLog = readLogSource({ inputPath, lastWindow });
const traces = collectTraces(rawLog);
const benchmarkProfiles = classifyProfiles(traces);

if (benchmarkProfiles.totalSamples === 0) {
  console.error("No completed terminal-open traces matched the benchmark profiles.");
  process.exit(1);
}

console.log(`# Terminal Benchmark Report`);
console.log();
console.log(`Trace source: ${inputPath ? inputPath : `log show --last ${lastWindow}`}`);
console.log(`Completed traces: ${benchmarkProfiles.totalSamples}`);
console.log();

for (const profile of benchmarkProfiles.orderedProfiles) {
  const samples = benchmarkProfiles.samplesByProfile.get(profile) ?? [];
  console.log(`## ${profile}`);
  console.log();
  console.log(`Samples: ${samples.length}`);
  console.log();
  console.log(`| Checkpoint Pair | p50 ms | p95 ms | samples |`);
  console.log(`| --- | ---: | ---: | ---: |`);

  for (const [start, end] of PAIRS) {
    const durations = samples
      .map((sample) => durationForPair(sample, start, end))
      .filter((value) => value !== null)
      .map((value) => value);
    const label = `${start} -> ${end}`;

    if (durations.length === 0) {
      console.log(`| ${label} | - | - | 0 |`);
      continue;
    }

    console.log(
      `| ${label} | ${quantile(durations, 0.5)} | ${quantile(durations, 0.95)} | ${durations.length} |`,
    );
  }

  console.log();
}

function readLogSource({ inputPath, lastWindow }) {
  if (inputPath) {
    return fs.readFileSync(inputPath, "utf8");
  }

  if (!process.stdin.isTTY) {
    return fs.readFileSync(0, "utf8");
  }

  return execFileSync(
    "log",
    [
      "show",
      "--style",
      "compact",
      "--predicate",
      PREDICATE,
      "--last",
      lastWindow,
    ],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
}

function collectTraces(rawLog) {
  const traces = new Map();
  const lines = rawLog.split(/\r?\n/);

  for (const line of lines) {
    if (!line.includes(`trace=${TRACE_NAME}`)) {
      continue;
    }

    const match = line.match(/\b(begin|checkpoint|end)\b trace=([^\s]+) trace_id=([^\s]+)\s*(.*)$/);
    if (!match) {
      continue;
    }

    const [, event, traceName, traceId, payload] = match;
    if (traceName !== TRACE_NAME) {
      continue;
    }

    const fields = parseFields(payload);
    let trace = traces.get(traceId);
    if (!trace) {
      trace = {
        id: traceId,
        context: {},
        checkpoints: new Map(),
        outcome: null,
      };
      traces.set(traceId, trace);
    }

    Object.assign(trace.context, fields);

    if (event === "checkpoint") {
      const checkpointName = fields.checkpoint;
      const elapsed = parseInteger(fields.elapsed_ms);
      if (checkpointName && elapsed !== null && !trace.checkpoints.has(checkpointName)) {
        trace.checkpoints.set(checkpointName, elapsed);
      }
      continue;
    }

    if (event === "end" && typeof fields.outcome === "string") {
      trace.outcome = fields.outcome;
    }
  }

  return traces;
}

function parseFields(payload) {
  const fields = {};
  const regex = /([a-zA-Z0-9_]+)=([^ ]+)/g;

  for (const match of payload.matchAll(regex)) {
    const [, key, value] = match;
    fields[key] = value;
  }

  return fields;
}

function classifyProfiles(traces) {
  const orderedProfiles = [
    "cold-empty-shell",
    "warm-empty-shell",
    "warm-real-shell",
    "existing-session-attach",
  ];
  const samplesByProfile = new Map(orderedProfiles.map((profile) => [profile, []]));

  for (const trace of traces.values()) {
    if (trace.outcome !== "interactive" && trace.outcome !== "success") {
      continue;
    }

    const profile = benchmarkProfileForTrace(trace);
    if (!profile) {
      continue;
    }

    samplesByProfile.get(profile)?.push(trace);
  }

  const totalSamples = Array.from(samplesByProfile.values()).reduce(
    (sum, samples) => sum + samples.length,
    0,
  );

  return { orderedProfiles, samplesByProfile, totalSamples };
}

function benchmarkProfileForTrace(trace) {
  const { context } = trace;

  if (context.session_lifecycle === "existing") {
    return "existing-session-attach";
  }

  if (context.launch_profile === "fast_shell" && context.host_startup === "cold") {
    return "cold-empty-shell";
  }

  if (context.launch_profile === "fast_shell" && context.host_startup === "warm") {
    return "warm-empty-shell";
  }

  if (context.launch_profile === "compatibility_shell" && context.host_startup === "warm") {
    return "warm-real-shell";
  }

  return null;
}

function durationForPair(trace, start, end) {
  const startElapsed = trace.checkpoints.get(start);
  const endElapsed = trace.checkpoints.get(end);

  if (typeof startElapsed !== "number" || typeof endElapsed !== "number") {
    return null;
  }

  return Math.max(0, endElapsed - startElapsed);
}

function parseInteger(value) {
  if (typeof value !== "string") {
    return null;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function quantile(values, percentile) {
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.max(0, Math.ceil(sorted.length * percentile) - 1);
  return sorted[index];
}
