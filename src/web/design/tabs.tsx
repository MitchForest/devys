import { cn } from "@/lib/utils";

/** Choices sit in an inset track; the selection rises out of it as a white thumb. */
export function SegmentedTabs<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T;
  options: readonly { value: T; title: string }[];
  onChange: (value: T) => void;
  label?: string;
}) {
  return (
    <div className="max-w-full overflow-x-auto [scrollbar-width:none]">
      <div
        role="tablist"
        aria-label={label}
        className="inline-flex gap-0.5 rounded-workspace bg-well p-1"
      >
        {options.map((option) => {
          const selected = option.value === value;
          return (
            <button
              key={option.value}
              type="button"
              role="tab"
              aria-selected={selected}
              onClick={() => onChange(option.value)}
              className={cn(
                "whitespace-nowrap rounded-control px-3.5 py-[7px] text-control font-medium transition duration-200 ease-[cubic-bezier(.3,1.3,.5,1)]",
                selected
                  ? "bg-sheet text-ink shadow-[0_0.5px_0.5px_rgb(0_0_0/0.05),0_2px_6px_rgb(0_0_0/0.07)]"
                  : "text-ink-2 hover:text-ink",
              )}
            >
              {option.title}
            </button>
          );
        })}
      </div>
    </div>
  );
}
