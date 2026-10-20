/** Types for the Face renderer, used by the web app and (as a synced copy) the site. */
export function mountFaces(root?: Pick<ParentNode, "querySelectorAll">): void;
export function unmountFace(canvas: HTMLCanvasElement): void;
export function redrawFaces(): void;
