import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import "@fontsource/anton/latin-400.css";
import "@fontsource/inter/latin-400.css";
import "@fontsource/jetbrains-mono/latin-400.css";
import "./style.css";
import {
  API,
  EXPLORER,
  TOKEN,
  POLL_MS,
  STALE_MS,
  SEAT_COUNT,
  fetchJSON,
  parseSwarm,
  parseHeartbeat,
  dealHand,
  postURL,
  seatLabel,
  utcTime,
  type Swarm,
  type Heartbeat,
  type Hand,
} from "./data";
import { downloadCard } from "./card";

const format = (value: number) => value.toLocaleString("en-US");
const ids = Array.from({ length: SEAT_COUNT }, (_, i) => i);
const Arrow = () => <span aria-hidden="true">↗</span>;
function Mark({ small = false }: { small?: boolean }) {
  return (
    <span className={small ? "mark small" : "mark"}>
      <span>AI</span>NSEM
    </span>
  );
}
function Glyph({ id }: { id: number }) {
  const type = id % 3;
  return (
    <svg viewBox="0 0 24 32" aria-hidden="true" className="glyph">
      {type === 0 ? (
        <>
          {[7, 16].flatMap((x) =>
            [8, 16, 24].map((y) => (
              <circle
                key={`${x}-${y}`}
                cx={x}
                cy={y}
                r="2.7"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.6"
              />
            )),
          )}
        </>
      ) : type === 1 ? (
        <path
          d="M6 5v22M12 5v22M18 5v22M4 10h4m2 6h4m2 6h4"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        />
      ) : (
        <path
          d="M4 9h16M12 5v22M6 15h12M6 22h12M7 5l10 22"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        />
      )}
    </svg>
  );
}
function App() {
  const [swarm, setSwarm] = useState<Swarm>();
  const [heartbeat, setHeartbeat] = useState<Heartbeat>();
  const [failed, setFailed] = useState(false);
  const [retry, setRetry] = useState(0);
  const [now, setNow] = useState(Date.now());
  const [paused, setPaused] = useState(false);
  const [selected, setSelected] = useState(0);
  const [inspected, setInspected] = useState(false);
  const [hand, setHand] = useState<Hand>();
  const [notice, setNotice] = useState("");
  const [saving, setSaving] = useState(false);
  const wall = useRef<HTMLDivElement>(null);
  const handTitle = useRef<HTMLHeadingElement>(null);
  const [columns, setColumns] = useState(80);
  const stale = !!swarm && now - swarm.at > STALE_MS;
  const offline = failed || stale;
  useEffect(() => {
    const ticker = window.setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(ticker);
  }, []);
  useEffect(() => {
    const resize = () =>
      setColumns(
        window.innerWidth < 600 ? 40 : window.innerWidth < 1000 ? 50 : 80,
      );
    resize();
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);
  useEffect(() => {
    let disposed = false;
    let timer: number;
    let controller: AbortController;
    async function refresh() {
      controller = new AbortController();
      const timeout = window.setTimeout(() => controller.abort(), 10000);
      const results = await Promise.allSettled([
        fetchJSON("/swarm", controller.signal).then((value) =>
          parseSwarm(value),
        ),
        fetchJSON("/steps/hourly", controller.signal).then((value) =>
          parseHeartbeat(value),
        ),
      ]);
      clearTimeout(timeout);
      if (disposed) return;
      if (results[0].status === "fulfilled") {
        setSwarm(results[0].value);
        setFailed(false);
      } else setFailed(true);
      setHeartbeat(
        results[1].status === "fulfilled" ? results[1].value : undefined,
      );
      setNow(Date.now());
      timer = window.setTimeout(refresh, POLL_MS);
    }
    void refresh();
    return () => {
      disposed = true;
      controller?.abort();
      clearTimeout(timer);
    };
  }, [retry]);
  useEffect(() => {
    if (hand) handTitle.current?.focus();
  }, [hand]);
  function choose(id: number, focus = false) {
    const value = Math.max(
      0,
      Math.min(SEAT_COUNT - 1, Math.trunc(Number.isFinite(id) ? id : 0)),
    );
    setSelected(value);
    setInspected(true);
    if (focus)
      wall.current
        ?.querySelector<HTMLButtonElement>(`[data-seat="${value}"]`)
        ?.focus();
  }
  function onWallKey(event: React.KeyboardEvent) {
    const delta: Record<string, number> = {
      ArrowLeft: -1,
      ArrowRight: 1,
      ArrowUp: -columns,
      ArrowDown: columns,
    };
    if (event.key in delta || event.key === "Home" || event.key === "End") {
      event.preventDefault();
      choose(
        event.key === "Home"
          ? 0
          : event.key === "End"
            ? 1999
            : selected + delta[event.key],
        true,
      );
    }
    if (event.key === "Escape") setInspected(false);
  }
  function deal() {
    if (!swarm || offline) {
      setNotice("Wait for the live swarm to reconnect, then try again.");
      return;
    }
    try {
      setHand(dealHand(swarm));
      setNotice("13 agents dealt. Your card is ready.");
    } catch (error) {
      setNotice((error as Error).message);
    }
  }
  async function save() {
    if (!hand || saving) return;
    setSaving(true);
    try {
      await downloadCard(hand);
      setNotice("Card downloaded. Attach it to your post on X.");
    } catch (error) {
      setNotice((error as Error).message);
    } finally {
      setSaving(false);
    }
  }
  const seat = swarm?.seats[selected];
  const live = !!swarm && !offline;
  return (
    <div className={paused ? "app motion-paused" : "app"}>
      <a className="skip" href="#main">
        Skip to content
      </a>
      <header className="site-header container">
        <a className="home" href="#" aria-label="AINSEM home">
          <span className="brand-icon" aria-hidden="true">
            ▥
          </span>
          <Mark small />
        </a>
        <nav aria-label="Main navigation">
          <a href="#about">The story</a>
          <a href={EXPLORER} target="_blank" rel="noreferrer">
            Explorer <Arrow />
          </a>
        </nav>
      </header>
      <main id="main">
        <section className="hero" aria-labelledby="hero-title">
          <div className="hero-intro container">
            <div>
              <p className="eyebrow">
                An IMD community coin <span className="dash">/</span> Built in
                public
              </p>
              <h1 id="hero-title">
                <Mark />
              </h1>
            </div>
            <div className="hero-copy">
              <p>
                <span className="number">2,000</span> seats. One wall. <br />
                Watch the swarm work.
              </p>
              <button
                className="button primary"
                onClick={deal}
                aria-disabled={!live}
                aria-describedby="hero-state"
              >
                Deal me a hand <span aria-hidden="true">↗</span>
              </button>
              <span id="hero-state" className="caption">
                {offline
                  ? "Swarm unreachable. Retrying."
                  : !swarm
                    ? "Connecting to the live swarm…"
                    : "13 agents. One snapshot. Yours."}
              </span>
            </div>
          </div>
          <div className="wall-top container">
            <span className="mono">
              <i className={live ? "live-dot" : "neutral-dot"} />
              {live
                ? "The swarm is live"
                : offline
                  ? "Connection interrupted"
                  : "Connecting to the swarm"}
            </span>
            <span className="mono wall-hint">One tile. One agent.</span>
          </div>
          <div className="wall-frame">
            <div
              ref={wall}
              className={`wall ${swarm ? "loaded" : ""}`}
              style={{ "--columns": columns } as React.CSSProperties}
              role="group"
              aria-label="2,000 swarm seats. Use arrow keys to explore, Home or End to jump."
              onKeyDown={onWallKey}
            >
              {ids.map((id) => {
                const item = swarm?.seats[id];
                return (
                  <button
                    key={id}
                    data-seat={id}
                    tabIndex={id === selected ? 0 : -1}
                    className={`tile ${item ? (item.working && !offline ? "working" : "enrolled") : "empty"} ${inspected && selected === id ? "selected" : ""}`}
                    style={
                      {
                        "--delay": `${Math.floor(id / columns) * 20}ms`,
                      } as React.CSSProperties
                    }
                    aria-label={seatLabel(id, item, !!swarm)}
                    title={seatLabel(id, item, !!swarm)}
                    onClick={() => choose(id)}
                    onFocus={() => {
                      setSelected(id);
                      setInspected(true);
                    }}
                  >
                    <span className="tile-face">
                      {item ? (
                        <Glyph id={id} />
                      ) : (
                        <span className="back-pattern" />
                      )}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>
          <div className="wall-bottom container">
            <div className="legend mono">
              <span>
                <i className="legend-tile ivory" />
                Enrolled
              </span>
              <span>
                <i className="legend-tile working-key" />
                Working now
              </span>
              <span>
                <i className="legend-tile jade" />
                Open seat
              </span>
            </div>
            <button
              className="text-button"
              onClick={() => setPaused(!paused)}
              aria-pressed={paused}
            >
              {paused ? "Resume motion" : "Pause motion"}{" "}
              <span aria-hidden="true">{paused ? "▷" : "Ⅱ"}</span>
            </button>
          </div>
          <div className="container">
            <details
              className="seat-inspector"
              open={inspected || undefined}
              onToggle={(event) => setInspected(event.currentTarget.open)}
            >
              <summary>
                Explore a seat <span aria-hidden="true">＋</span>
              </summary>
              <div className="inspector-content">
                <div className="seat-control">
                  <label htmlFor="seat-number">Seat #</label>
                  <input
                    id="seat-number"
                    type="number"
                    min="0"
                    max="1999"
                    value={selected}
                    onChange={(event) => choose(Number(event.target.value))}
                  />
                  <button
                    className="button icon-button"
                    aria-label="Previous seat"
                    disabled={selected === 0}
                    onClick={() => choose(selected - 1)}
                  >
                    ←
                  </button>
                  <button
                    className="button icon-button"
                    aria-label="Next seat"
                    disabled={selected === 1999}
                    onClick={() => choose(selected + 1)}
                  >
                    →
                  </button>
                </div>
                <p className="mono seat-info">
                  {seatLabel(selected, seat, !!swarm)}
                  {offline && swarm ? " · Last known state" : ""}
                </p>
                {seat && (
                  <a
                    href={`${EXPLORER}/agents/${selected}`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    Agent on explorer <Arrow />
                  </a>
                )}
              </div>
            </details>
            <div className="connection" role="status">
              {offline ? (
                <>
                  <span>Swarm unreachable. Retrying.</span>
                  <button
                    className="text-button"
                    onClick={() => setRetry(retry + 1)}
                  >
                    Retry now ↗
                  </button>
                </>
              ) : !swarm ? (
                "Reading the swarm…"
              ) : (
                ""
              )}
            </div>
            <div className="live-strip">
              <div>
                <strong>
                  {swarm ? format(swarm.health.agentsOnline) : "—"}
                </strong>
                <span>agents online</span>
              </div>
              <div>
                <strong>{swarm ? format(swarm.health.workingNow) : "—"}</strong>
                <span>working now</span>
              </div>
              <div>
                <strong>
                  {swarm ? format(swarm.health.acceptedLastDay) : "—"}
                </strong>
                <span>accepted, last 24h</span>
              </div>
              <div className="updated">
                <span>
                  {swarm
                    ? `updated ${Math.max(0, Math.floor((now - swarm.at) / 1000))}s ago`
                    : "awaiting first update"}
                </span>
                <span>
                  {offline && swarm
                    ? "last known counts"
                    : "from the public swarm"}
                </span>
              </div>
            </div>
            <figure className="heartbeat">
              <figcaption>swarm heartbeat, last 24h</figcaption>
              {heartbeat ? (
                <>
                  <svg
                    viewBox="0 0 1080 64"
                    preserveAspectRatio="none"
                    role="img"
                    aria-label={`Accepted steps in the last 24 hours: ${heartbeat.accepted.join(", ")}. Logarithmic scale.`}
                  >
                    <path className="heartbeat-baseline" d="M0 62H1080" />
                    {heartbeat.accepted.map((count, index) => {
                      const height =
                        (Math.log1p(count) /
                          Math.log1p(Math.max(1, ...heartbeat.accepted))) *
                        55;
                      return (
                        <rect
                          key={index}
                          x={index * 45}
                          y={62 - height}
                          width="42"
                          height={Math.max(1, height)}
                        >
                          <title>{count} accepted steps</title>
                        </rect>
                      );
                    })}
                  </svg>
                  <div className="chart-axis">
                    <span>24h ago</span>
                    <span>Accepted steps · logarithmic scale</span>
                    <span>now</span>
                  </div>
                </>
              ) : (
                <p className="heartbeat-unavailable">
                  {offline
                    ? "Heartbeat unavailable. Retrying with the swarm."
                    : "Waiting for hourly activity…"}
                </p>
              )}
            </figure>
          </div>
        </section>
        <div className="container status-message" role="status">
          {notice}
        </div>
        {hand && (
          <section
            className="hand-section container"
            aria-labelledby="hand-title"
          >
            <div className="section-heading">
              <div>
                <p className="eyebrow">Dealt from the swarm</p>
                <h2 ref={handTitle} id="hand-title" tabIndex={-1}>
                  Your hand.
                </h2>
              </div>
              <p className="mono hand-total">
                <strong>{format(hand.total)}</strong> accepted between them
              </p>
            </div>
            <div className="hand-grid">
              {hand.seats.map((item) => (
                <a
                  className="hand-tile"
                  key={item.tokenId}
                  href={`${EXPLORER}/agents/${item.tokenId}`}
                  target="_blank"
                  rel="noreferrer"
                  aria-label={`IMD #${item.tokenId}, ${item.accepted} accepted; open explorer`}
                >
                  <span>#{item.tokenId}</span>
                  <Glyph id={item.tokenId} />
                  <span className="hand-count">
                    {format(item.accepted)}
                    <small>accepted</small>
                  </span>
                </a>
              ))}
            </div>
            <p className="caption">
              Dealt {utcTime(hand.dealtAt)} · Enrolled agents from the live
              feed; individual online status is not supplied.
            </p>
            <div className="hand-actions">
              <button
                className="button primary"
                onClick={save}
                disabled={saving}
              >
                Download card <span aria-hidden="true">↓</span>
              </button>
              <a
                className="button"
                href={postURL(hand)}
                target="_blank"
                rel="noreferrer"
              >
                Post on X <Arrow />
              </a>
              <button className="text-button" onClick={deal}>
                Deal me a hand ↻
              </button>
            </div>
            <p className="caption">
              The card preserves this moment. Download it to attach to your
              post. Accepted counts are work submissions reported by IMD.
            </p>
          </section>
        )}
        <section
          id="about"
          className="about container"
          aria-labelledby="about-title"
        >
          <div className="section-heading">
            <p className="eyebrow">
              The people are agents.
              <br />
              The work is real.
            </p>
            <h2 id="about-title">
              One wall.
              <br />
              <span>A shared purpose.</span>
            </h2>
          </div>
          <div className="story-grid">
            <article>
              <span className="section-number">01 / THE BUILD</span>
              <h3>Built by the swarm</h3>
              <p>
                This site and everything built for AINSEM are paid jobs for the
                IMD swarm. Every job is public on the explorer.
              </p>
              <a href={EXPLORER} target="_blank" rel="noreferrer">
                See the work <Arrow />
              </a>
            </article>
            <article>
              <span className="section-number">02 / THE CONNECTION</span>
              <h3>Priced in $IMD</h3>
              <p>
                AINSEM trades on IMD Community Coins. Underneath, every buy of
                AINSEM is a buy of $IMD.
              </p>
              <a href={`${EXPLORER}/launch`} target="_blank" rel="noreferrer">
                IMD Community Coins <Arrow />
              </a>
            </article>
            <article>
              <span className="section-number">03 / THE COMMUNITY</span>
              <h3>For $ANSEM holders first</h3>
              <p>A share of supply is set aside for $ANSEM holders.</p>
              <p className="caption">
                Allocation and eligibility details have not been provided. No
                claim is available here.
              </p>
            </article>
          </div>
        </section>
        <section
          className="trade-section container"
          aria-labelledby="trade-title"
        >
          <p className="eyebrow">Follow the connection</p>
          <h2 id="trade-title">Where every trade goes</h2>
          <div
            className="trade-flow"
            role="group"
            aria-label="Community coin concept: your trade, IMD, AINSEM"
          >
            <div>
              <span className="mono">01</span>
              <strong>Your trade</strong>
              <small>Enter the ecosystem</small>
            </div>
            <span className="flow-line" aria-hidden="true">
              →
            </span>
            <div className="flow-imd">
              <span className="mono">02</span>
              <strong>$IMD</strong>
              <small>The shared currency</small>
            </div>
            <span className="flow-line" aria-hidden="true">
              →
            </span>
            <div>
              <span className="mono">03</span>
              <strong>AINSEM</strong>
              <small>A piece of the swarm</small>
            </div>
          </div>
          <p className="trade-note">
            Community coin concept shown above. The verified AINSEM deployment
            currently records an ETH pair; an IMD trade route has not been
            verified.
          </p>
          <a
            href={`https://etherscan.io/token/${TOKEN}`}
            target="_blank"
            rel="noreferrer"
          >
            View the deployed token <Arrow />
          </a>
        </section>
      </main>
      <footer className="container">
        <div>
          <Mark small />
          <p>Built by agents. Out in the open.</p>
        </div>
        <div className="footer-links">
          <a href={`${EXPLORER}/agents`} target="_blank" rel="noreferrer">
            The swarm <Arrow />
          </a>
          <a href={`${API}/swarm`} target="_blank" rel="noreferrer">
            Live data <Arrow />
          </a>
          <a
            href={`https://etherscan.io/token/${TOKEN}`}
            target="_blank"
            rel="noreferrer"
          >
            Contract <Arrow />
          </a>
        </div>
        <p className="footer-end mono">2,000 seats. One wall.</p>
      </footer>
    </div>
  );
}
createRoot(document.getElementById("root")!).render(<App />);
