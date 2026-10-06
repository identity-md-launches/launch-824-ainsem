export const SEAT_COUNT = 2000;
export const EXPLORER = "https://explorer.imd.fun";
export const API = "https://api.imd.fun";
export const TOKEN = "0x4dc25f4a5beecfdd7ef3dde1c250cbcc29497753";
export const POLL_MS = 15000;
export const STALE_MS = 60000;

export type Seat = {
  tokenId: number;
  agentId: string;
  accepted: number;
  working: boolean;
};
export type Swarm = {
  at: number;
  health: {
    agentsOnline: number;
    workingNow: number;
    acceptedLastDay: number;
    seatsEnrolled: number;
  };
  seats: Record<number, Seat>;
};
export type Heartbeat = { until: string; accepted: number[] };
export type Hand = {
  seats: Seat[];
  total: number;
  dealtAt: string;
  sourceAt: number;
};

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("Invalid feed");
  return value as Record<string, unknown>;
}
function count(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0)
    throw new Error("Invalid count");
  return value;
}
export function parseSwarm(value: unknown, now = Date.now()): Swarm {
  const data = record(value);
  const health = record(data.health);
  const at = count(data.at);
  if (health.reachable !== true || now - at > STALE_MS || at > now + 30000)
    throw new Error("Stale feed");
  const seats: Swarm["seats"] = {};
  for (const [id, raw] of Object.entries(record(data.seats))) {
    const seat = record(raw);
    const tokenId = count(seat.tokenId);
    if (
      tokenId >= SEAT_COUNT ||
      String(tokenId) !== id ||
      typeof seat.agentId !== "string" ||
      typeof seat.working !== "boolean"
    )
      throw new Error("Invalid seat");
    seats[tokenId] = {
      tokenId,
      agentId: seat.agentId,
      accepted: count(seat.accepted),
      working: seat.working,
    };
  }
  return {
    at,
    seats,
    health: {
      agentsOnline: count(health.agentsOnline),
      workingNow: count(health.workingNow),
      acceptedLastDay: count(health.acceptedLastDay),
      seatsEnrolled: count(health.seatsEnrolled),
    },
  };
}
export function parseHeartbeat(value: unknown, now = Date.now()): Heartbeat {
  const data = record(value);
  if (
    typeof data.until !== "string" ||
    !Number.isFinite(Date.parse(data.until)) ||
    now - Date.parse(data.until) > STALE_MS ||
    Date.parse(data.until) > now + 30000 ||
    !Array.isArray(data.accepted) ||
    data.accepted.length !== 24
  )
    throw new Error("Invalid heartbeat");
  return { until: data.until, accepted: data.accepted.map(count) };
}
export async function fetchJSON(
  path: string,
  signal: AbortSignal,
): Promise<unknown> {
  const response = await fetch(`${API}${path}`, {
    signal,
    credentials: "omit",
  });
  if (!response.ok) throw new Error(`Feed returned ${response.status}`);
  return response.json();
}
export function dealHand(
  swarm: Swarm,
  random = () => crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296,
  now = Date.now(),
): Hand {
  if (now - swarm.at > STALE_MS)
    throw new Error("Wait for a fresh swarm update, then try again.");
  const pool = Object.values(swarm.seats);
  if (pool.length < 13)
    throw new Error(
      "A hand needs 13 enrolled agents. Try again when more seats join.",
    );
  for (let i = 0; i < 13; i++) {
    const j = i + Math.floor(random() * (pool.length - i));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  const seats = pool.slice(0, 13).map((seat) => ({ ...seat }));
  return {
    seats,
    total: seats.reduce((sum, seat) => sum + seat.accepted, 0),
    dealtAt: new Date(now).toISOString(),
    sourceAt: swarm.at,
  };
}
export const utcTime = (iso: string) =>
  iso.replace("T", " ").replace(/\.\d{3}Z$/, " UTC");
export const postText = (hand: Hand) =>
  `My AINSEM hand: 13 live IMD agents, ${hand.total} accepted jobs between them. Dealt from the swarm at ${utcTime(hand.dealtAt)}.`;
export const postURL = (hand: Hand) =>
  `https://twitter.com/intent/tweet?${new URLSearchParams({ text: postText(hand) })}`;
export const seatLabel = (id: number, seat?: Seat, loaded = true) =>
  !loaded
    ? `Seat #${id}, waiting for swarm data`
    : seat
      ? `IMD #${id}, ${seat.working ? "working now" : "enrolled"}, ${seat.accepted} accepted`
      : `Seat #${id}, not enrolled yet`;
