import Markdown from "react-markdown";

/** Block Markdown in the native MarkdownView's type scale. Raw HTML is never rendered. */
export function MarkdownView({ text }: { text: string }) {
  return (
    <div className="flex flex-col gap-2.5 text-body leading-relaxed text-ink select-text [&_a]:text-indigo [&_a]:underline [&_blockquote]:border-l-2 [&_blockquote]:border-hairline [&_blockquote]:pl-3 [&_blockquote]:text-ink-2 [&_code]:rounded-tiny [&_code]:bg-well [&_code]:px-1 [&_code]:font-mono [&_code]:text-[12px] [&_h1]:text-title [&_h1]:font-semibold [&_h2]:text-heading [&_h2]:font-semibold [&_h3]:font-semibold [&_hr]:border-hairline [&_ol]:list-decimal [&_ol]:pl-5 [&_pre]:overflow-x-auto [&_pre]:rounded-control [&_pre]:bg-well [&_pre]:p-3 [&_pre_code]:bg-transparent [&_pre_code]:p-0 [&_table]:text-detail [&_td]:border-b [&_td]:border-hairline [&_td]:py-1 [&_td]:pr-3 [&_th]:pr-3 [&_th]:text-left [&_ul]:list-disc [&_ul]:pl-5">
      <Markdown>{text}</Markdown>
    </div>
  );
}

/** Inline Markdown (bold, links, code) without block layout, as chat bubbles on native. */
export function InlineMarkdown({ text }: { text: string }) {
  return (
    <Markdown
      allowedElements={["p", "strong", "em", "a", "code", "del", "br"]}
      unwrapDisallowed
      components={{
        p: ({ children }) => (
          <span className="block whitespace-pre-wrap not-first:mt-2">{children}</span>
        ),
        a: ({ children, href }) => (
          <a href={href} target="_blank" rel="noreferrer" className="underline">
            {children}
          </a>
        ),
        code: ({ children }) => <code className="font-mono text-[12px]">{children}</code>,
      }}
    >
      {text}
    </Markdown>
  );
}
