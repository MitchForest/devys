/** At this width and below the web is a phone: tabs, and the panel as a sheet. */
export const compactWidth = 700;
export const compactQuery = `(max-width: ${compactWidth}px)`;

/** Column widths from the space actually available, exactly as native `WorkspaceLayout`. */
const minimumConversation = 420;
export const panelRange = [360, 720] as const;
export const defaultPanel = 440;
export const handle = 9;
export const sidebarWidth = 236;

/**
 * The conversation keeps its minimum; the right panel takes its preferred width within its
 * range, or everything else when widened, and lies over the conversation when the window is
 * too narrow for both.
 */
export function layout(
  width: number,
  sidebarVisible: boolean,
  panelOpen: boolean,
  wide: boolean,
  preferred: number,
) {
  const sidebar = sidebarVisible ? sidebarWidth : 0;
  const content = Math.max(0, width - (sidebarVisible ? sidebarWidth + 1 : 0));
  if (!panelOpen)
    return { sidebar, conversation: content, panel: 0, overlay: false, handle: false };
  if (content < minimumConversation + handle + panelRange[0])
    return {
      sidebar,
      conversation: content,
      panel: Math.min(content, defaultPanel),
      overlay: true,
      handle: false,
    };
  const largest = content - minimumConversation - handle;
  const panel = wide
    ? largest
    : Math.min(Math.max(preferred, panelRange[0]), Math.min(panelRange[1], largest));
  return { sidebar, conversation: content - panel - handle, panel, overlay: false, handle: !wide };
}
