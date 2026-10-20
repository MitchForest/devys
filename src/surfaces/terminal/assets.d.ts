// Vite resolves these imports to asset URLs.
declare module "*?url" {
  const url: string;
  export default url;
}
declare module "*?url&no-inline" {
  const url: string;
  export default url;
}
