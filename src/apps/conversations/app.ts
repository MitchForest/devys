import { defineApp } from "../../protocol/app.ts";
import { bundledSkill } from "../../protocol/skill.ts";
import emailingForTheBusiness from "./skills/emailing-for-the-business/SKILL.md?raw";

export const conversations = defineApp({
  id: "conversations",
  name: "Conversations",
  icon: "bubble.left.and.bubble.right",
  summary: "What was said in direct messages, project channels and work threads.",
  kind: "system",
  records: [],
  capabilities: ["conversationHistory", "suggestReplies"],
  skills: [bundledSkill("emailing-for-the-business", emailingForTheBusiness)],
  connections: [],
  appears: "never",
  // Every employee reads back in the conversation it is answering and offers replies to tap.
  defaultGrants: {
    "chief-of-staff": ["conversationHistory", "suggestReplies"],
    engineering: ["conversationHistory", "suggestReplies"],
    growth: ["conversationHistory", "suggestReplies"],
    admin: ["conversationHistory", "suggestReplies"],
    finance: ["conversationHistory", "suggestReplies"],
    custom: ["conversationHistory", "suggestReplies"],
  },
});
