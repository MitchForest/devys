import { defineApp } from "../../protocol/app.ts";

export const conversations = defineApp({
  id: "conversations",
  name: "Conversations",
  icon: "bubble.left.and.bubble.right",
  summary: "What was said in direct messages, project channels and work threads.",
  kind: "system",
  records: [],
  capabilities: ["conversationHistory"],
  skills: [],
  connections: [],
  appears: "never",
  // Every employee reads back in the conversation it is answering.
  defaultGrants: {
    operations: ["conversationHistory"],
    engineering: ["conversationHistory"],
    growth: ["conversationHistory"],
    "business-operations": ["conversationHistory"],
    custom: ["conversationHistory"],
  },
});
