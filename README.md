# 🐄 KuhPoker

Texas Hold'em mit **Kuhhandel-Tierkarten** — online gegen Freunde oder Zuschauer, im Browser und als Roblox-Spiel.

Statt der klassischen 52-Karten gibt es **10 Tiere** mit aufsteigendem Zahlenwert. Gespielt wird wie Hold'em (2 Handkarten, Flop/Turn/River, beste 5 aus 7), aber **es zählt der Zahlenwert, nicht die Farbe** — ohne Flush-Modus gibt es also keinen Flush.

## Das Kartensystem

| Rang | Tier | Wert | | Rang | Tier | Wert |
|---|---|---|---|---|---|---|
| 1 | 🐓 Hahn | 10 | | 6 | 🐐 Ziege | 350 |
| 2 | 🪿 Gans | 40 | | 7 | 🫏 Esel | 500 |
| 3 | 🐈 Katze | 90 | | 8 | 🐖 Schwein | 650 |
| 4 | 🐕 Hund | 160 | | 9 | 🐄 Kuh | 800 |
| 5 | 🐑 Schaf | 250 | | 10 | 🐎 Pferd | 1000 |

Jedes Tier ist 4× im Deck (40 Karten), jede Kopie in einer von vier **Farben** (☀ Sonne, 🌙 Mond, ♣ Klee, ♥ Herz). Die Farben sind standardmäßig nur Deko — erst im **Flush-Modus** zählen sie.

**Rangfolge (hoch → niedrig):** Vierling · Full House · Straße · Drilling · Zwei Paare · Paar · Hohe Karte. In der Straße zählt das Pferd (10) auch tief: Pferd-Hahn-Gans-Katze-Hund. Mit Flush-Modus kommen Straight Flush und Flush (schlägt Full House) dazu.

## Spielmodi

- **Flush-Modus** — Farben zählen, Flush & Straight Flush werden möglich.
- **Turnier-Modus** — steigende Blinds (alle paar Hände höher) statt konstant 10/20.
- **Cash-Game** — Buy-in aus dem Guthaben, Rebuy nach Bust, Cash-out beim Verlassen.
- **Brainrot-Modus** — rein kosmetisch: zeigt Brainrot-Charaktere statt Tiere.

## Features

Mehrtisch-Lobby mit Raum-Code · 2–6 Spieler · **Zuschauer-Modus** · Live-Handstärke · Rangfolge- & Karten-Referenzpanels · Emotes · Tisch-Chat · Hand-Historie · **Replay der letzten Hand** · Split-/Side-Pot-Aufschlüsselung · Wallet & Leaderboard · Reconnect-Handling · Tastatur-Steuerung · DE/EN · Classic-Casino-UI, responsive (Desktop/Mobile) · Erstbesucher-Onboarding.

## Projektstruktur

```
server.js            Express + Socket.io Server (Räume, Spielfluss, Persistenz)
src/
  cards.js           Tier- & Farb-Definitionen
  handEval.js        Hand-Bewertung (mit/ohne Flush)
  poker.js           Spiel-Engine (Blinds, Setzrunden, Showdown, Side-Pots)
  store.js           Persistenz (Upstash Redis REST oder JSON-Datei-Fallback)
  bot.js             Test-Bot (joint Raum, checkt/callt) — node src/bot.js <CODE>
  *.test.js          Unit- & E2E-Tests
public/
  index.html         Lobby + Tisch
  client.js          Frontend-Logik (Vanilla JS, Socket.io-Client)
  style.css          Classic-Casino-Theme
roblox/              Eigenständige Roblox-Portierung (Luau) — siehe roblox/README.md
```

## Lokal starten

```bash
npm install
npm start            # http://localhost:3000
```

Zum Testen zu zweit: einen Browser-Tab öffnen, Tisch erstellen, Code kopieren, und entweder einen zweiten Tab beitreten lassen oder einen Test-Bot starten:

```bash
node src/bot.js <CODE> Ben
```

## Tests

```bash
npm test             # alles
npm run test:unit    # Engine/Hand-Eval/Store (schnell)
npm run test:e2e     # Socket-End-to-End (startet den Server)
```

Stand: 199 Unit- + 66 E2E-Assertions grün.

## Deployment

One-Click via [Render](https://render.com) mit dem mitgelieferten `render.yaml` (Blueprint).
Persistenz über **Upstash Redis** aktiviert sich automatisch, wenn die Env-Variablen gesetzt sind — sonst JSON-Datei-Fallback (auf Render flüchtig).

### Umgebungsvariablen

| Variable | Zweck | Default |
|---|---|---|
| `PORT` | Server-Port | 3000 |
| `UPSTASH_REDIS_REST_URL` / `_TOKEN` | Persistenter Store (Wallet/Stats) | — (Datei-Fallback) |
| `STARTING_WALLET` | Start-Guthaben neuer Spieler | 10000 |
| `WALLET_REFILL` | Auffüllen, wenn pleite | 1000 |
| `TURN_MS` | Zug-Zeitlimit (Auto-Aktion) | – |
| `ROOM_TTL_MS` | Leere Räume aufräumen nach | – |
| `DISCONNECT_GRACE_MS` | Reconnect-Frist | – |
| `RUNOUT_START_MS` / `_STEP_MS` / `_RIVER_MS` | Timing des All-In-Aufdeckens | – |
| `KEEPALIVE_URL` | Self-Ping (gegen Render-Free-Sleep) | – |

## Tech-Stack

Node.js (ESM) · Express · Socket.io · Vanilla JS Frontend (kein Build-Step) · optional Upstash Redis. Roblox-Port in Luau (siehe `roblox/`).
