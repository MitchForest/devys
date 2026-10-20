/** Which viewer a file opens in, from its name. */
export type FileKind =
  | "markdown"
  | "pdf"
  | "word"
  | "sheet"
  | "whiteboard"
  | "presentation"
  | "image"
  | "text"
  | "other";

const text = new Set([
  "txt",
  "json",
  "ts",
  "tsx",
  "js",
  "jsx",
  "mjs",
  "css",
  "html",
  "yml",
  "yaml",
  "toml",
  "sql",
  "sh",
  "swift",
  "py",
  "rb",
  "go",
  "rs",
  "java",
  "kt",
  "c",
  "h",
  "cpp",
  "xml",
  "svg",
  "env",
  "gitignore",
  "log",
]);

export function fileKind(name: string): FileKind {
  const extension = name.includes(".") ? name.split(".").at(-1)!.toLowerCase() : name.toLowerCase();
  if (extension === "md" || extension === "markdown") return "markdown";
  if (extension === "pdf") return "pdf";
  if (extension === "docx") return "word";
  if (extension === "xlsx" || extension === "xls" || extension === "csv") return "sheet";
  if (extension === "excalidraw") return "whiteboard";
  if (extension === "pptx" || extension === "ppt" || extension === "key") return "presentation";
  if (["png", "jpg", "jpeg", "gif", "webp"].includes(extension)) return "image";
  if (text.has(extension) || !name.includes(".")) return "text";
  return "other";
}
