import { createContext, useContext } from "react";

/** The right panel as the shell lays it out: whether it shows, and showing or hiding it. */
export const PanelContext = createContext<{
  open: boolean;
  hasPermanent: boolean;
  toggle: () => void;
}>({ open: false, hasPermanent: false, toggle: () => undefined });
export const usePanel = () => useContext(PanelContext);
