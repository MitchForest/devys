/** Column widths from the space actually available, exactly as native `WorkspaceLayout`. */
export const minimumPage = 420;
export const inspectorRange = [280, 640] as const;
export const handle = 9;
export const sidebarWidth = 236;
export function layout(
  width: number,
  sidebarVisible: boolean,
  inspectorVisible: boolean,
  expanded: boolean,
  preferred: number,
) {
  const sidebar = sidebarVisible ? sidebarWidth : 0;
  const content = Math.max(0, width - (sidebarVisible ? sidebarWidth + 1 : 0));
  if (expanded) return { sidebar, page: 0, inspector: content, showsHandle: false };
  if (inspectorVisible && content >= minimumPage + handle + inspectorRange[0]) {
    const largest = Math.min(inspectorRange[1], content - minimumPage - handle);
    const inspector = Math.min(Math.max(preferred, inspectorRange[0]), largest);
    return { sidebar, page: content - inspector - handle, inspector, showsHandle: true };
  }
  return { sidebar, page: content, inspector: 0, showsHandle: false };
}
