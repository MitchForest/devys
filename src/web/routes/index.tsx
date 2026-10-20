import { createFileRoute } from "@tanstack/react-router";
import { App } from "../app/App.tsx";
export const Route = createFileRoute("/")({ component: App });
