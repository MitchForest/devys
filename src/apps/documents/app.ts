import { defineApp } from "../../protocol/app.ts";
import { bundledSkill } from "../../protocol/skill.ts";
import writingPages from "./skills/writing-pages/SKILL.md?raw";

const artifacts = ["artifactPage", "artifactRead", "artifactEdit", "publishArtifact"] as const;
const drive = ["driveList", "driveRead", "driveCreate", "driveUpdate"] as const;

export const documents = defineApp({
  id: "documents",
  name: "Documents",
  icon: "doc.text",
  summary: "Documents, pages, sheets, slides, whiteboards, PDFs and uploads, and Google Drive.",
  kind: "business",
  records: [
    { kind: "artifact", title: "Artifact" },
    { kind: "file", title: "File" },
  ],
  capabilities: [...artifacts, ...drive],
  skills: [bundledSkill("writing-pages", writingPages)],
  connections: [{ provider: "google", scopes: ["https://www.googleapis.com/auth/drive.file"] }],
  appears: "always",
  defaultGrants: {
    "chief-of-staff": [...artifacts, ...drive],
    engineering: artifacts,
    growth: artifacts,
    admin: [...artifacts, ...drive],
    finance: [...artifacts, ...drive],
  },
});
