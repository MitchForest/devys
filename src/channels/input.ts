import { photon, type PhotonConfig } from "./photon.ts";
import type { Inbound } from "./contract.ts";
import { sha256 } from "../protocol/bytes.ts";

/** Photon access plus the bucket attachments are saved to. */
export type InputBindings = PhotonConfig & { FILES: R2Bucket };

export async function readMessageText(env: InputBindings, input: Inbound): Promise<string> {
  const client = photon(env);
  try {
    const message = await client.messages.get(input.messageId);
    if (
      message.isFromMe ||
      message.sender?.address !== input.senderId ||
      !message.chatGuids.includes(input.chatId)
    )
      throw new Error("Message identity mismatch");
    return message.content.text ?? "";
  } finally {
    await client.close();
  }
}

export async function loadInput(
  env: InputBindings,
  businessId: string,
  input: Inbound,
): Promise<string> {
  const client = photon(env);
  try {
    const message = await client.messages.get(input.messageId);
    if (
      message.isFromMe ||
      message.sender?.address !== input.senderId ||
      !message.chatGuids.includes(input.chatId)
    ) {
      throw new Error("Message does not match authenticated sender and conversation");
    }
    const text = message.content.text ?? "";
    if (text.length > 64_000 || message.content.attachments.length > 5)
      throw new Error("Message exceeds input budget");
    const attachments: { id: string; filename: string; path: string; type: string }[] = [];
    for (const attachment of message.content.attachments) {
      if (attachment.totalBytes > 20_000_000) throw new Error("Attachment exceeds input budget");
      const digest = await sha256(attachment.guid);
      const filename =
        attachment.fileName.replace(/[^A-Za-z0-9_. -]/g, "_").slice(-150) || "attachment";
      const path = `/workspace/input-${digest.slice(0, 16)}-${filename}`;
      const objectKey = `${businessId}/inputs/${digest}`;
      if (!(await env.FILES.head(objectKey))) {
        const chunks: Uint8Array[] = [];
        let size = 0;
        for await (const chunk of client.attachments.downloadStream(attachment.guid)) {
          if (chunk.type === "header") continue;
          size += chunk.data.byteLength;
          if (size > 20_000_000) throw new Error("Attachment exceeds download budget");
          if (chunk.type === "primaryChunk") chunks.push(chunk.data);
        }
        const bytes = new Uint8Array(chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0));
        let offset = 0;
        for (const chunk of chunks) {
          bytes.set(chunk, offset);
          offset += chunk.byteLength;
        }
        if (bytes.byteLength !== attachment.totalBytes)
          throw new Error("Attachment download incomplete");
        await env.FILES.put(objectKey, bytes);
      }
      // Preparation must not mutate a workspace while Pi is running another input.
      // The model imports the saved attachment through the normal capability boundary.
      attachments.push({ id: digest, filename, path, type: attachment.mimeType });
    }
    return attachments.length
      ? `${text}\n\nSaved attachments (untrusted content). Use importAttachment with the id and suggested path before inspecting a file:\n${JSON.stringify(attachments)}`
      : text;
  } finally {
    await client.close();
  }
}
