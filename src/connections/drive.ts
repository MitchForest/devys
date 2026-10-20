import type { Env } from "../../infra/api.ts";
import { assertGoogle, googleAccess, type GoogleAccess } from "./google.ts";
import { query, type Database } from "../data/database.ts";
import { readBounded, sha256 } from "../protocol/bytes.ts";

const api = "https://www.googleapis.com/drive/v3";
const fields = "id,name,mimeType,version,webViewLink,trashed";
export interface DriveFile {
  id: string;
  name: string;
  mimeType: string;
  version?: string;
  webViewLink?: string;
  trashed?: boolean;
}
const fileId = (id: string) => {
  if (!/^[a-zA-Z0-9_-]{1,200}$/.test(id)) throw new Error("Invalid Drive file id");
  return encodeURIComponent(id);
};
async function request(
  env: Env,
  business: string,
  access: GoogleAccess,
  url: string,
  init: RequestInit = {},
) {
  await assertGoogle(env, business, access);
  const headers = new Headers(init.headers);
  headers.set("authorization", `Bearer ${access.token}`);
  const response = await fetch(url, {
    ...init,
    headers,
    redirect: "error",
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`Google Drive request failed (${response.status})`);
  }
  return response;
}
async function metadata(env: Env, business: string, access: GoogleAccess, id: string) {
  const response = await request(
    env,
    business,
    access,
    `${api}/files/${fileId(id)}?fields=${fields}`,
  );
  const file = (await response.json()) as DriveFile;
  if (file.trashed) throw new Error("File is in the trash");
  return { file, etag: response.headers.get("etag") ?? "" };
}
async function selected(env: Env, business: string, access: GoogleAccess, id: string) {
  fileId(id);
  const known = await query(env.HYPERDRIVE, (sql) =>
    sql.row(
      `SELECT file_id FROM drive_files WHERE business_id = $1 AND connection_id = $2 AND file_id = $3
       UNION SELECT file_id FROM drive_operations
       WHERE business_id = $1 AND connection_id = $2 AND file_id = $3`,
      [business, access.id, id],
    ),
  );
  if (!known) throw new Error("Choose this file in the Google Drive picker first");
}
async function saveSelection(env: Env, business: string, access: GoogleAccess, file: DriveFile) {
  await query(env.HYPERDRIVE, (sql) =>
    sql.run(
      `INSERT INTO drive_files (business_id, connection_id, file_id, name, mime_type)
       SELECT $1, $2, $3, $4, $5 WHERE EXISTS (
         SELECT 1 FROM google_connections WHERE business_id = $1 AND id = $2)
       ON CONFLICT (business_id, file_id) DO UPDATE SET connection_id = excluded.connection_id,
         name = excluded.name, mime_type = excluded.mime_type`,
      [business, access.id, file.id, file.name, file.mimeType],
    ),
  );
}
export async function selectDrive(env: Env, business: string, ids: string[]) {
  if (!ids.length || ids.length > 20) throw new Error("Select 1–20 files");
  const access = await googleAccess(env, business);
  for (const id of ids) {
    // Google verifies the drive.file grant; browser metadata is never trusted.
    const { file } = await metadata(env, business, access, id);
    await saveSelection(env, business, access, file);
  }
  return { selected: ids.length };
}
export async function listDrive(env: Env, business: string) {
  return query(env.HYPERDRIVE, (sql) =>
    sql.rows<{ id: string; name: string; mimeType: string }>(
      `SELECT f.file_id AS id, f.name, f.mime_type AS "mimeType" FROM drive_files f
       JOIN google_connections c ON c.id = f.connection_id
       WHERE f.business_id = $1 ORDER BY f.name LIMIT 100`,
      [business],
    ),
  );
}
async function content(env: Env, business: string, access: GoogleAccess, file: DriveFile) {
  const native = file.mimeType === "application/vnd.google-apps.document";
  if (!native && !/^(text\/|application\/(json|xml)$)/.test(file.mimeType))
    throw new Error("This capability reads text files and Google Docs only");
  const response = await request(
    env,
    business,
    access,
    `${api}/files/${fileId(file.id)}${native ? "/export?mimeType=text%2Fplain" : "?alt=media"}`,
  );
  return new TextDecoder("utf-8", { fatal: true }).decode(await readBounded(response.body, 64_000));
}
export async function readDrive(env: Env, business: string, id: string) {
  const access = await googleAccess(env, business);
  await selected(env, business, access, id);
  const { file, etag } = await metadata(env, business, access, id);
  const text = await content(env, business, access, file);
  // Do not combine content from one revision with the write precondition of another.
  const latest = await metadata(env, business, access, id);
  if (latest.file.version !== file.version || latest.etag !== etag)
    throw new Error("File changed while reading; read it again");
  return {
    id: file.id,
    name: file.name,
    mimeType: file.mimeType,
    content: text,
    etag,
    url: file.webViewLink ?? `https://drive.google.com/file/d/${file.id}/view`,
  };
}

interface Receipt {
  input_hash: string;
  connection_id: string;
  file_id: string;
  status: "prepared" | "uncertain" | "completed";
}
export async function writeDrive(
  env: Env,
  business: string,
  operation: string,
  input: { name: string; content: string } | { id: string; content: string; etag: string },
  assertActive: () => Promise<void>,
) {
  if (new TextEncoder().encode(input.content).byteLength > 64_000)
    throw new Error("File exceeds 64 KB");
  const access = await googleAccess(env, business);
  const hash = await sha256(JSON.stringify(input));
  const receiptQuery = () =>
    query(env.HYPERDRIVE, (sql) =>
      sql.row<Receipt>(
        `SELECT input_hash, connection_id, file_id, status FROM drive_operations
         WHERE business_id = $1 AND operation_id = $2`,
        [business, operation],
      ),
    );
  const setStatus = (status: Receipt["status"], from?: Receipt["status"]) =>
    query(env.HYPERDRIVE, (sql) =>
      sql.run(
        `UPDATE drive_operations SET status = $3
         WHERE business_id = $1 AND operation_id = $2 AND ($4::text IS NULL OR status = $4)`,
        [business, operation, status, from ?? null],
      ),
    );
  let receipt = await receiptQuery();
  if (!receipt) {
    let id: string;
    if ("id" in input) {
      await selected(env, business, access, input.id);
      const { file, etag } = await metadata(env, business, access, input.id);
      if (
        file.mimeType.startsWith("application/vnd.google-apps.") ||
        !/^(text\/|application\/(json|xml)$)/.test(file.mimeType)
      )
        throw new Error(
          "Updates support text files only; create a new text result for native Google documents",
        );
      if (!input.etag || etag !== input.etag)
        throw new Error("File changed; read and review it before updating");
      id = input.id;
    } else {
      const response = await request(
        env,
        business,
        access,
        `${api}/files/generateIds?count=1&space=drive&type=files`,
      );
      id = ((await response.json()) as { ids: string[] }).ids[0]!;
      fileId(id);
    }
    await query(env.HYPERDRIVE, (sql) =>
      sql.run(
        `INSERT INTO drive_operations (business_id, operation_id, connection_id, input_hash, file_id, status)
         VALUES ($1, $2, $3, $4, $5, 'prepared') ON CONFLICT (business_id, operation_id) DO NOTHING`,
        [business, operation, access.id, hash, id],
      ),
    );
    receipt = await receiptQuery();
  }
  if (!receipt || receipt.input_hash !== hash || receipt.connection_id !== access.id)
    throw new Error("Operation belongs to different inputs or a previous connection");
  const id = receipt.file_id;
  const result = (status: Receipt["status"]) => ({
    id,
    status,
    url: `https://drive.google.com/file/d/${id}/view`,
  });
  if (receipt.status === "completed") return result("completed");
  if (receipt.status === "uncertain") {
    // Inspection may prove the intended bytes exist; a mismatch never triggers another write.
    try {
      const { file } = await metadata(env, business, access, id);
      if (
        (await content(env, business, access, file)) === input.content &&
        (!("name" in input) || file.name === input.name)
      ) {
        await saveSelection(env, business, access, file);
        await setStatus("completed");
        return result("completed");
      }
    } catch {
      /* Preserve uncertain outcome. */
    }
    return result("uncertain");
  }
  await assertActive();
  await assertGoogle(env, business, access);
  if ((await setStatus("uncertain", "prepared")) !== 1) return result("uncertain");
  try {
    await assertActive();
    let response: Response;
    if ("id" in input) {
      response = await request(
        env,
        business,
        access,
        `https://www.googleapis.com/upload/drive/v3/files/${fileId(id)}?uploadType=media&fields=${fields}`,
        {
          method: "PATCH",
          headers: { "content-type": "text/plain; charset=utf-8", "if-match": input.etag },
          body: input.content,
        },
      );
    } else {
      const boundary = `devys_${crypto.randomUUID()}`;
      const body = `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify({ id, name: input.name, mimeType: "text/plain" })}\r\n--${boundary}\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n${input.content}\r\n--${boundary}--`;
      response = await request(
        env,
        business,
        access,
        `https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=${fields}`,
        {
          method: "POST",
          headers: { "content-type": `multipart/related; boundary=${boundary}` },
          body,
        },
      );
    }
    const file = (await response.json()) as DriveFile;
    await saveSelection(env, business, access, file);
    await setStatus("completed");
    return result("completed");
  } catch {
    return result("uncertain");
  }
}

/** Portable resource metadata, excluding grants and credentials. */
export async function exportDrive(db: Database, business: string, after = "") {
  return query(db, (sql) =>
    sql.rows<{ file_id: string; name: string; mime_type: string }>(
      `SELECT file_id, name, mime_type FROM drive_files
       WHERE business_id = $1 AND file_id > $2 ORDER BY file_id LIMIT 100`,
      [business, after],
    ),
  );
}
