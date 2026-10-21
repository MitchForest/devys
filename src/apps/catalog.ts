import type { AppManifest } from "./contract.ts";

const artifacts = ["artifactPage", "artifactEdit", "publishArtifact"] as const;
const drive = ["driveList", "driveRead", "driveCreate", "driveUpdate"] as const;
const coding = [
  "codingStart",
  "codingStatus",
  "codingSend",
  "codingStop",
  "codingAccept",
  "codingPublish",
  "deployPreview",
  "deployProduction",
] as const;

/**
 * Devys apps. Built-in tools (commands and files on the computer, the browser, terminals,
 * memory, conversations, work and projects) belong to no app: every business has them.
 */
export const appCatalog: readonly AppManifest[] = [
  {
    id: "documents",
    name: "Documents",
    icon: "doc.text",
    summary: "Documents, pages, sheets, slides, whiteboards, PDFs and uploads, and Google Drive.",
    records: ["artifact", "file", "drive-file"],
    capabilities: [...artifacts, ...drive],
    connections: ["google"],
    appears: "always",
    status: "available",
    defaultGrants: {
      engineering: artifacts,
      growth: artifacts,
      "business-operations": [...artifacts, ...drive],
    },
  },
  {
    id: "code",
    name: "Code",
    icon: "chevron.left.forwardslash.chevron.right",
    summary: "Repositories, coding sessions, pull requests and deploys.",
    records: ["assignment", "pull-request", "deploy"],
    capabilities: coding,
    connections: ["github"],
    appears: "records",
    status: "available",
    defaultGrants: { engineering: coding },
  },
  ...(
    [
      [
        "mail",
        "Mail",
        "envelope",
        "The business's mailboxes: threads, drafts and sending.",
        "google",
      ],
      ["money", "Money", "creditcard", "Payments, cards and transactions.", "stripe"],
      ["website", "Website", "globe", "The business's site, domains and pages.", "cloudflare"],
      ["ads", "Ads", "megaphone", "Ad campaigns, spend and results.", "meta"],
      ["customers", "Customers", "person.2", "Customers, conversations and follow-ups.", "google"],
    ] as const
  ).map(([id, name, icon, summary, connection]) => ({
    id,
    name,
    icon,
    summary,
    records: [],
    capabilities: [],
    connections: [connection],
    appears: "connected" as const,
    status: "coming" as const,
  })),
];

export const appById = (id: string) => appCatalog.find((app) => app.id === id);

/** The app a capability belongs to; undefined for a built-in tool. */
export const appOf = (capability: string) =>
  appCatalog.find((app) => app.capabilities.includes(capability));

/** What every new business has installed. */
export const defaultApps = ["documents", "code"] as const;
