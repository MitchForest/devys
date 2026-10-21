import { useSyncExternalStore } from "react";

/**
 * A small client-state store: components read a slice with `useStore` and re-render only when
 * that slice changes, so one change never re-renders the whole workspace.
 */
export function createStore<T extends object>(initial: T) {
  let state = initial;
  const listeners = new Set<() => void>();
  return {
    get: () => state,
    set(change: Partial<T> | ((current: T) => Partial<T>)) {
      state = { ...state, ...(typeof change === "function" ? change(state) : change) };
      for (const listener of listeners) listener();
    },
    subscribe(listener: () => void) {
      listeners.add(listener);
      return () => void listeners.delete(listener);
    },
  };
}
type Store<T extends object> = ReturnType<typeof createStore<T>>;

/** One slice of a store; the selector must return a value from the state, not a new object. */
export function useStore<T extends object, S>(store: Store<T>, select: (state: T) => S): S {
  return useSyncExternalStore(
    store.subscribe,
    () => select(store.get()),
    () => select(store.get()),
  );
}
