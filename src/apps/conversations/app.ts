import { defineApp } from "../../protocol/app.ts";

export const conversations = defineApp({
  id: "conversations",
  name: "Conversations",
  icon: "bubble.left.and.bubble.right",
  summary: "What was said in direct messages, project channels and work threads.",
  kind: "system",
  records: [],
  capabilities: ["conversationHistory", "suggestReplies"],
  skills: [],
  connections: [],
  appears: "never",
  // Every employee reads back in the conversation it is answering and offers replies to tap.
  defaultGrants: {
    operations: ["conversationHistory", "suggestReplies"],
    engineering: ["conversationHistory", "suggestReplies"],
    growth: ["conversationHistory", "suggestReplies"],
    "business-operations": ["conversationHistory", "suggestReplies"],
    custom: ["conversationHistory", "suggestReplies"],
  },
});
