import type { Route } from "../../src/features/conversation/conversation.router.ts";
import type { CorpusItem } from "../fixtures/conversation-corpus.ts";

export function matches(route: Route, item: CorpusItem) {
  if (item.expect.kind === "PREFERENCE") return route.kind === "UNKNOWN";
  if (route.kind !== item.expect.kind) return false;
  if (route.kind === "STATS" && item.expect.domain) return route.domain === item.expect.domain;
  if (route.kind === "FOOD" && item.expect.query) return route.query.includes(item.expect.query.split(" ")[0]!);
  return true;
}
