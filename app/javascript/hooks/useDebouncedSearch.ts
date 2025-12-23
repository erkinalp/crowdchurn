import { router } from "@inertiajs/react";
import React from "react";

import { useDebouncedCallback } from "$app/components/useDebouncedCallback";
import { useOnChange } from "$app/components/useOnChange";

/**
 * Hook for managing search query state with debounced Inertia reload.
 *
 * - Maintains local query state for immediate UI updates
 * - Debounces the actual server request by 500ms
 * - Only triggers reload when query actually changes (not on mount)
 * - Resets to page 1 when search query changes
 * - Resets installments prop to clear merged infinite scroll data
 * - Clears InfiniteScroll remembered state to prevent stale pagination
 * - Exposes debouncedQuery to use as a key for InfiniteScroll remounting
 */
export function useDebouncedSearch() {
  const [query, setQuery] = React.useState(() => new URLSearchParams(window.location.search).get("query") || "");
  const [debouncedQuery, setDebouncedQuery] = React.useState(query);

  const handleQueryChange = React.useCallback((newQuery: string) => {
    setDebouncedQuery(newQuery);
    // Clear InfiniteScroll's remembered pagination state before reloading.
    // Without this, when the InfiniteScroll component remounts, it restores
    // stale pagination state (e.g., nextPage: null from a previous search
    // with few results), which breaks infinite scroll for subsequent searches.
    router.remember(null, "inertia:infinite-scroll-data:installments");
    router.reload({ data: { query: newQuery || undefined }, only: ["installments"], reset: ["installments"] });
  }, []);

  const debouncedFetch = useDebouncedCallback((q: string) => handleQueryChange(q), 500);

  useOnChange(() => debouncedFetch(query), [query]);

  return { query, setQuery, debouncedQuery };
}
