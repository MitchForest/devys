/**
 * The apps the Connect apps sheet offers first: well-known services whose official remote MCP
 * server connects with the owner's own sign-in and no setup with the provider (OAuth with dynamic
 * client registration or a client ID metadata document). Search also reaches the MCP Registry.
 *
 * Verified 2026-10-23 by an unauthenticated `initialize` and each server's OAuth metadata. Recheck
 * before relying on one: a provider may still allowlist clients (Ramp, Square and Figma are
 * reported to). Services needing a client registered with the provider first (Slack, GitHub,
 * Google Workspace, Microsoft 365, HubSpot, Asana, Xero) are not listed until Devys has one.
 */
export const appCategories = [
  "Payments and finance",
  "Productivity",
  "Code and hosting",
  "Design and web",
  "Sales and support",
  "Analytics and automation",
] as const;
export type AppCategory = (typeof appCategories)[number];

export interface ListedApp {
  name: string;
  /** One line on what it lets employees do. */
  summary: string;
  category: AppCategory;
  /** The official remote MCP server (Streamable HTTP). */
  url: string;
  /** The service's own site, for its logo. */
  website: string;
}

export const listedApps: readonly ListedApp[] = [
  {
    name: "Ramp",
    summary: "Cards, spend and bills",
    category: "Payments and finance",
    url: "https://mcp.ramp.com/mcp",
    website: "https://ramp.com",
  },
  {
    name: "Stripe",
    summary: "Payments, customers and invoices",
    category: "Payments and finance",
    url: "https://mcp.stripe.com",
    website: "https://stripe.com",
  },
  {
    name: "Mercury",
    summary: "Business banking",
    category: "Payments and finance",
    url: "https://mcp.mercury.com/mcp",
    website: "https://mercury.com",
  },
  {
    name: "Brex",
    summary: "Cards, spend and expenses",
    category: "Payments and finance",
    url: "https://api.brex.com/mcp",
    website: "https://brex.com",
  },
  {
    name: "Square",
    summary: "Sales, payments and catalog",
    category: "Payments and finance",
    url: "https://mcp.squareup.com/mcp",
    website: "https://squareup.com",
  },
  {
    name: "PayPal",
    summary: "Payments and invoices",
    category: "Payments and finance",
    url: "https://mcp.paypal.com/mcp",
    website: "https://paypal.com",
  },
  {
    name: "Notion",
    summary: "Pages and databases",
    category: "Productivity",
    url: "https://mcp.notion.com/mcp",
    website: "https://notion.so",
  },
  {
    name: "Linear",
    summary: "Issues and projects",
    category: "Productivity",
    url: "https://mcp.linear.app/mcp",
    website: "https://linear.app",
  },
  {
    name: "Atlassian",
    summary: "Jira and Confluence",
    category: "Productivity",
    url: "https://mcp.atlassian.com/v2/mcp",
    website: "https://atlassian.com",
  },
  {
    name: "Airtable",
    summary: "Bases and records",
    category: "Productivity",
    url: "https://mcp.airtable.com/mcp",
    website: "https://airtable.com",
  },
  {
    name: "Vercel",
    summary: "Deploys and projects",
    category: "Code and hosting",
    url: "https://mcp.vercel.com",
    website: "https://vercel.com",
  },
  {
    name: "Cloudflare",
    summary: "Domains, DNS, Workers and more",
    category: "Code and hosting",
    url: "https://mcp.cloudflare.com/mcp",
    website: "https://cloudflare.com",
  },
  {
    name: "Supabase",
    summary: "Databases and auth",
    category: "Code and hosting",
    url: "https://mcp.supabase.com/mcp",
    website: "https://supabase.com",
  },
  {
    name: "Neon",
    summary: "Postgres databases",
    category: "Code and hosting",
    url: "https://mcp.neon.tech/mcp",
    website: "https://neon.com",
  },
  {
    name: "Sentry",
    summary: "Errors and performance",
    category: "Code and hosting",
    url: "https://mcp.sentry.dev/mcp",
    website: "https://sentry.io",
  },
  {
    name: "Figma",
    summary: "Designs and files",
    category: "Design and web",
    url: "https://mcp.figma.com/mcp",
    website: "https://figma.com",
  },
  {
    name: "Canva",
    summary: "Designs and brand kits",
    category: "Design and web",
    url: "https://mcp.canva.com/mcp",
    website: "https://canva.com",
  },
  {
    name: "Webflow",
    summary: "Sites and CMS",
    category: "Design and web",
    url: "https://mcp.webflow.com/mcp",
    website: "https://webflow.com",
  },
  {
    name: "Intercom",
    summary: "Conversations and help center",
    category: "Sales and support",
    url: "https://mcp.intercom.com/mcp",
    website: "https://intercom.com",
  },
  {
    name: "PostHog",
    summary: "Product analytics",
    category: "Analytics and automation",
    url: "https://mcp.posthog.com/mcp",
    website: "https://posthog.com",
  },
  {
    name: "Zapier",
    summary: "Automations across apps",
    category: "Analytics and automation",
    url: "https://mcp.zapier.com/api/v1/connect",
    website: "https://zapier.com",
  },
];
