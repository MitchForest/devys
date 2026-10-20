/** A text or source file, highlighted by Pierre's file view, read-only. */
import { File } from "@pierre/diffs/react";

export function CodeFile({
  name,
  contents,
  dark = false,
}: {
  name: string;
  contents: string;
  dark?: boolean;
}) {
  return (
    <div className="size-full overflow-auto" data-testid="code-file">
      <File file={{ name, contents }} options={{ themeType: dark ? "dark" : "light" }} />
    </div>
  );
}
