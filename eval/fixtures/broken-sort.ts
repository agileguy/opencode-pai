/**
 * Sorts an array of objects by a given key.
 * BUG: Doesn't handle missing keys, crashes on undefined.
 * BUG: Comparison is wrong for numbers (string comparison).
 */
export function sortBy<T extends Record<string, unknown>>(
  items: T[],
  key: string,
  order: "asc" | "desc" = "asc"
): T[] {
  return items.sort((a, b) => {
    // BUG: no null/undefined check on a[key] or b[key]
    const valA = String(a[key]);
    const valB = String(b[key]);
    // BUG: string comparison for all types
    if (order === "asc") {
      return valA < valB ? -1 : 1;
    }
    return valA > valB ? -1 : 1;
  });
}
