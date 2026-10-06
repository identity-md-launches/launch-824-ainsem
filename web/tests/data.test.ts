import test from "node:test";
import assert from "node:assert/strict";
import {
  parseSwarm,
  parseHeartbeat,
  dealHand,
  postText,
  postURL,
  seatLabel,
  STALE_MS,
} from "../src/data";

const now = Date.parse("2026-10-07T00:00:00Z");
const fixture = () => ({
  at: now,
  health: {
    reachable: true,
    agentsOnline: 21,
    workingNow: 2,
    acceptedLastDay: 120,
    seatsEnrolled: 30,
  },
  seats: Object.fromEntries(
    Array.from({ length: 30 }, (_, tokenId) => [
      tokenId,
      {
        tokenId,
        agentId: String(50000 + tokenId),
        accepted: tokenId * 2,
        working: tokenId < 2,
      },
    ]),
  ),
});

test("preserves seat zero and the reported aggregate counters", () => {
  const result = parseSwarm(fixture(), now);
  assert.equal(result.seats[0].tokenId, 0);
  assert.equal(result.health.agentsOnline, 21);
  assert.equal(Object.keys(result.seats).length, 30);
  assert.equal(seatLabel(1999), "Seat #1999, not enrolled yet");
  assert.match(seatLabel(0, undefined, false), /waiting/);
});
test("rejects unreachable, stale, future, malformed or unsafe data", () => {
  for (const invalid of [
    null,
    {},
    { ...fixture(), at: now - STALE_MS - 1 },
    { ...fixture(), at: now + 31000 },
    { ...fixture(), health: { ...fixture().health, reachable: false } },
    { ...fixture(), health: { ...fixture().health, acceptedLastDay: -1 } },
    { ...fixture(), seats: { 0: { tokenId: 2000 } } },
  ]) {
    assert.throws(() => parseSwarm(invalid, now));
  }
});
test("deals thirteen distinct enrolled agents, with the correct immutable total and UTC timestamp", () => {
  const swarm = parseSwarm(fixture(), now);
  for (const random of [() => 0, () => 0.5, () => 0.999999]) {
    const hand = dealHand(swarm, random, now);
    assert.equal(hand.seats.length, 13);
    assert.equal(new Set(hand.seats.map((seat) => seat.tokenId)).size, 13);
    assert.ok(hand.seats.every((seat) => !!swarm.seats[seat.tokenId]));
    assert.equal(
      hand.total,
      hand.seats.reduce((sum, seat) => sum + seat.accepted, 0),
    );
    assert.equal(hand.dealtAt, "2026-10-07T00:00:00.000Z");
    assert.notEqual(hand.seats[0], swarm.seats[hand.seats[0].tokenId]);
  }
});
test("cannot deal fewer than thirteen agents or from stale data", () => {
  const swarm = parseSwarm(fixture(), now);
  assert.throws(
    () => dealHand(swarm, () => 0, now + STALE_MS + 1),
    /fresh swarm/,
  );
  swarm.seats = {};
  assert.throws(() => dealHand(swarm, () => 0, now), /13 enrolled agents/);
});
test("share intent preserves the required copy and percent-encodes it", () => {
  const hand = dealHand(parseSwarm(fixture(), now), () => 0, now);
  const expected =
    "My AINSEM hand: 13 live IMD agents, 156 accepted jobs between them. Dealt from the swarm at 2026-10-07 00:00:00 UTC.";
  assert.equal(postText(hand), expected);
  const url = new URL(postURL(hand));
  assert.equal(url.hostname, "twitter.com");
  assert.equal(url.searchParams.get("text"), expected);
});
test("heartbeat requires all 24 valid hourly values and a fresh timestamp", () => {
  assert.equal(
    parseHeartbeat(
      { until: new Date(now).toISOString(), accepted: Array(24).fill(0) },
      now,
    ).accepted.length,
    24,
  );
  assert.throws(() =>
    parseHeartbeat({ until: "not a date", accepted: [] }, now),
  );
  assert.throws(() =>
    parseHeartbeat(
      {
        until: new Date(now - STALE_MS - 1).toISOString(),
        accepted: Array(24).fill(0),
      },
      now,
    ),
  );
  assert.throws(() =>
    parseHeartbeat(
      { until: new Date(now).toISOString(), accepted: Array(24).fill(-1) },
      now,
    ),
  );
});
