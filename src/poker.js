// Texas Hold'em Engine fuer 2-6 Spieler mit Kuhhandel-Tierkarten.
// Autoritativer Spielzustand. Clients schicken nur Aktionen, der Server validiert alles.
//
// Unterstuetzt Button-/Blind-Rotation, korrekte Setzreihenfolge und Side Pots
// (mehrere All-Ins auf unterschiedlichen Hoehen). Optionaler Flush-Modus.

import { buildDeck, shuffle } from './cards.js';
import { evaluate, compareScores } from './handEval.js';

export const STARTING_STACK = 1000;
export const SMALL_BLIND = 10;
export const BIG_BLIND = 20;

// Turnier-Blindstruktur: steigt mit jedem Level. Im Turniermodus wird das Level
// aus der Handnummer abgeleitet (alle `levelHands` Haende ein Level hoeher); das
// letzte Level gilt danach unbegrenzt weiter.
export const TOURNEY_BLINDS = [
  { sb: 10, bb: 20 },
  { sb: 15, bb: 30 },
  { sb: 25, bb: 50 },
  { sb: 50, bb: 100 },
  { sb: 75, bb: 150 },
  { sb: 100, bb: 200 },
  { sb: 150, bb: 300 },
  { sb: 200, bb: 400 },
  { sb: 300, bb: 600 },
  { sb: 500, bb: 1000 },
  { sb: 750, bb: 1500 },
  { sb: 1000, bb: 2000 },
];

// Binomialkoeffizient C(n, k) – fuer die Entscheidung exakt vs. Monte-Carlo.
function nCk(n, k) {
  if (k < 0 || k > n) return 0;
  if (k === 0 || k === n) return 1;
  k = Math.min(k, n - k);
  let r = 1;
  for (let j = 0; j < k; j++) r = (r * (n - j)) / (j + 1);
  return Math.round(r);
}

// Live-Handstaerke waehrend des Setzens: beste Kategorie aus den bisher bekannten
// Karten (eigene Hole-Cards + bereits gezeigtes Board). Bei <5 Karten greift eine
// einfache Heuristik (Paar/Hohe Karte), sonst die volle Auswertung.
function liveCategory(hole, community, flush) {
  const cards = [...hole, ...community];
  if (cards.length >= 5) return evaluate(cards, { flush }).score[0];
  // Weniger als 5 Karten: nur Paar (3) oder Hohe Karte (2) moeglich.
  const counts = new Map();
  for (const c of cards) counts.set(c.rank, (counts.get(c.rank) || 0) + 1);
  let max = 0;
  for (const v of counts.values()) if (v > max) max = v;
  if (max >= 4) return 8; // theoretisch nur mit 4 gleichen Hole-Cards unmoeglich, sicherheitshalber
  if (max === 3) return 5; // Drilling
  if (max === 2) {
    // Zwei Paare moeglich? (zwei verschiedene Paare)
    let pairs = 0;
    for (const v of counts.values()) if (v >= 2) pairs++;
    return pairs >= 2 ? 4 : 3;
  }
  return 2; // Hohe Karte
}

export class Table {
  // Aufruf:
  //   new Table([{id,name}, ...], { flush })   // 2-6 Spieler
  //   new Table({id,name}, {id,name})          // Rueckwaerts-kompatibel (Heads-up)
  constructor(playersOrP0, p1OrOptions, options) {
    let playerDefs;
    let opts;
    if (Array.isArray(playersOrP0)) {
      playerDefs = playersOrP0;
      opts = p1OrOptions || {};
    } else {
      playerDefs = [playersOrP0, p1OrOptions];
      opts = options || {};
    }

    this.flush = !!opts.flush;
    const ss = Math.floor(Number(opts.startingStack));
    this.startingStack = Number.isFinite(ss) && ss > 0 ? ss : STARTING_STACK;
    // Cash-Game: Buy-in = startingStack, busten beendet das Match NICHT (Rebuy
    // moeglich). Schliesst den Turniermodus aus.
    this.cash = !!opts.cash;
    // Turniermodus: Blinds steigen mit der Handnummer. Sonst fix 10/20.
    this.tournament = !this.cash && !!opts.tournament;
    const lh = Math.floor(Number(opts.levelHands));
    this.levelHands = Number.isFinite(lh) && lh > 0 ? lh : 6;
    this.smallBlind = SMALL_BLIND;
    this.bigBlind = BIG_BLIND;
    this.blindLevel = 0;
    this.players = playerDefs.map((p) => ({
      id: p.id,
      name: p.name,
      stack: this.startingStack,
      hole: [],
      bet: 0, // Einsatz in der aktuellen Setzrunde
      committed: 0, // Einsatz insgesamt in dieser Hand
      folded: false,
      allIn: false,
      inHand: false,
      lastAction: null, // letzte Aktion dieser Setzrunde (fuer die Sitz-Anzeige)
    }));
    this.n = this.players.length;
    this.button = this.n - 1; // erstes startHand rotiert auf 0
    this.handNo = 0;
    this.stage = 'idle'; // idle | preflop | flop | turn | river | showdown | handover
    this.community = [];
    this.deck = [];
    this.pot = 0; // Gesamteinsatz dieser Hand (inkl. aktueller Bets)
    this.currentBet = 0;
    this.minRaise = this.bigBlind;
    this.toAct = null;
    this.actedSinceRaise = new Set();
    this.sbPos = null;
    this.bbPos = null;
    this.log = [];
    this.result = null;
    this.matchOver = false;
    this.matchWinnerId = null;
    this.shownCards = new Set(); // Sitze, die nach Fold-Sieg freiwillig aufgedeckt haben

    // All-In-Run-out: Wenn niemand mehr handeln kann, aber >=2 Spieler im Showdown
    // stehen, werden die restlichen Karten gezeigt. Im Offline-Test (autoRunout=true)
    // geschieht das sofort/synchron. Der Server setzt autoRunout=false und deckt die
    // Strassen zeitversetzt ueber stepRunout() auf (TV-Poker-Stil) und zeigt vorher
    // die Gewinnwahrscheinlichkeiten (equities).
    this.autoRunout = true;
    this.runoutActive = false;
    this.equities = null; // [{ i, pct }] waehrend eines gestaffelten Run-outs
  }

  // Strukturiertes Log-Event: { key, ...params }. Die Uebersetzung passiert im Client,
  // damit jeder Spieler das Log in seiner Sprache sieht.
  addLog(event) {
    this.log.push(event);
    if (this.log.length > 40) this.log.shift();
  }

  resetMatch() {
    for (const p of this.players) {
      p.stack = this.startingStack;
      p.hole = [];
      p.bet = 0;
      p.committed = 0;
      p.folded = false;
      p.allIn = false;
      p.inHand = false;
    }
    this.button = this.n - 1;
    this.handNo = 0;
    this.stage = 'idle';
    this.community = [];
    this.deck = [];
    this.pot = 0;
    this.currentBet = 0;
    this.applyBlindLevel();
    this.minRaise = this.bigBlind;
    this.toAct = null;
    this.actedSinceRaise = new Set();
    this.sbPos = null;
    this.bbPos = null;
    this.result = null;
    this.matchOver = false;
    this.matchWinnerId = null;
    this.shownCards = new Set();
    this.runoutActive = false;
    this.equities = null;
    this.log = [];
    this.addLog({ key: 'rematch' });
    return { ok: true };
  }

  // Setzt smallBlind/bigBlind passend zur aktuellen Handnummer. Im Nicht-Turnier
  // bleibt es fix bei 10/20. Loggt einen Blind-Anstieg (ausser bei der 1. Hand).
  applyBlindLevel() {
    if (!this.tournament) {
      this.blindLevel = 0;
      this.smallBlind = SMALL_BLIND;
      this.bigBlind = BIG_BLIND;
      return;
    }
    const level = Math.max(0, Math.floor((this.handNo - 1) / this.levelHands));
    const prevBb = this.bigBlind;
    const b = TOURNEY_BLINDS[Math.min(level, TOURNEY_BLINDS.length - 1)];
    this.blindLevel = level;
    this.smallBlind = b.sb;
    this.bigBlind = b.bb;
    if (this.handNo > 1 && this.bigBlind > prevBb) {
      this.addLog({ key: 'blindsUp', sb: this.smallBlind, bb: this.bigBlind, level: level + 1 });
    }
  }

  // Haende bis zur naechsten Blind-Erhoehung (nur im Turniermodus sinnvoll).
  handsUntilNextLevel() {
    if (!this.tournament) return null;
    if (this.blindLevel >= TOURNEY_BLINDS.length - 1) return null; // letztes Level erreicht
    return (this.blindLevel + 1) * this.levelHands - this.handNo;
  }

  // ---- Index-Helfer (rund um den Tisch) ----
  // Naechster Sitz nach `from`, dessen Spieler noch Chips hat (fuer Button/Blinds).
  nextLive(from) {
    for (let k = 1; k <= this.n; k++) {
      const idx = (from + k) % this.n;
      if (this.players[idx].stack > 0) return idx;
    }
    return from;
  }

  // Erster handlungsfaehiger Spieler ab `start` (inklusive): in der Hand und nicht All-In.
  firstActorFrom(start) {
    for (let k = 0; k < this.n; k++) {
      const idx = (start + k) % this.n;
      const p = this.players[idx];
      if (!p.folded && !p.allIn && p.inHand) return idx;
    }
    return null;
  }

  // Naechster handlungsfaehiger Spieler nach `from` (exklusiv).
  nextToAct(from) {
    for (let k = 1; k <= this.n; k++) {
      const idx = (from + k) % this.n;
      const p = this.players[idx];
      if (!p.folded && !p.allIn && p.inHand) return idx;
    }
    return null;
  }

  liveCount() {
    return this.players.filter((p) => p.stack > 0).length;
  }

  // ---- Hand starten ----
  startHand() {
    if (this.matchOver) return { error: 'Match ist beendet.' };
    if (this.stage !== 'idle' && this.stage !== 'handover')
      return { error: 'Hand laeuft noch.' };
    if (this.liveCount() < 2)
      return { error: 'Mindestens zwei Spieler mit Chips noetig.' };

    this.handNo++;
    this.applyBlindLevel();
    this.button = this.nextLive(this.button);
    this.deck = shuffle(buildDeck());
    this.community = [];
    this.pot = 0;
    this.currentBet = 0;
    this.minRaise = this.bigBlind;
    this.result = null;
    this.actedSinceRaise = new Set();
    this.shownCards = new Set();
    this.runoutActive = false;
    this.equities = null;

    for (const p of this.players) {
      p.hole = [];
      p.bet = 0;
      p.committed = 0;
      p.allIn = false;
      p.inHand = p.stack > 0;
      p.folded = !p.inHand; // Spieler ohne Chips sitzen aus
      p.lastAction = null;
    }

    // Karten austeilen (nur aktive Spieler), beginnend links vom Button.
    const order = [];
    for (let k = 1; k <= this.n; k++) order.push((this.button + k) % this.n);
    for (let round = 0; round < 2; round++) {
      for (const idx of order) {
        if (this.players[idx].inHand) this.players[idx].hole.push(this.deck.pop());
      }
    }

    const liveIdx = this.players
      .map((p, i) => ({ p, i }))
      .filter((x) => x.p.stack > 0)
      .map((x) => x.i);

    let firstToAct;
    if (liveIdx.length === 2) {
      // Heads-up: Button ist Small Blind und handelt praeflop zuerst.
      this.sbPos = this.button;
      this.bbPos = this.nextLive(this.button);
      firstToAct = this.sbPos;
    } else {
      this.sbPos = this.nextLive(this.button);
      this.bbPos = this.nextLive(this.sbPos);
      firstToAct = this.nextLive(this.bbPos); // UTG
    }

    this.postBlind(this.sbPos, this.smallBlind);
    this.postBlind(this.bbPos, this.bigBlind);
    this.currentBet = this.bigBlind;
    this.minRaise = this.bigBlind;

    this.stage = 'preflop';
    this.addLog({ key: 'handStart', hand: this.handNo, name: this.players[this.button].name });
    this.syncPot();

    // Erster handlungsfaehiger Spieler (ueberspringt evtl. All-In durch kurze Blinds).
    this.toAct = this.firstActorFrom(firstToAct);
    if (this.toAct === null || this.isBettingClosed()) {
      this.proceedAfterBetting();
    }
    return { ok: true };
  }

  postBlind(i, amount) {
    const p = this.players[i];
    const pay = Math.min(amount, p.stack);
    p.stack -= pay;
    p.bet += pay;
    p.committed += pay;
    if (p.stack === 0) p.allIn = true;
  }

  syncPot() {
    this.pot = this.players.reduce((s, p) => s + p.committed, 0);
  }

  // ---- Aktion verarbeiten ----
  act(playerId, type, amount) {
    if (this.stage === 'idle' || this.stage === 'handover' || this.stage === 'showdown')
      return { error: 'Keine aktive Setzrunde.' };
    if (this.toAct === null) return { error: 'Niemand am Zug.' };
    const i = this.toAct;
    const p = this.players[i];
    if (p.id !== playerId) return { error: 'Du bist nicht am Zug.' };

    const toCall = this.currentBet - p.bet;

    switch (type) {
      case 'fold': {
        p.folded = true;
        p.inHand = false;
        p.lastAction = { type: 'fold' };
        this.addLog({ key: 'fold', name: p.name });
        const remaining = this.players.filter((x) => !x.folded);
        if (remaining.length === 1) {
          return this.endByFold();
        }
        break;
      }
      case 'check': {
        if (toCall > 0) return { error: 'Check nicht moeglich, es liegt ein Einsatz an.' };
        this.actedSinceRaise.add(i);
        p.lastAction = { type: 'check' };
        this.addLog({ key: 'check', name: p.name });
        break;
      }
      case 'call': {
        if (toCall <= 0) {
          this.actedSinceRaise.add(i);
          p.lastAction = { type: 'check' };
          this.addLog({ key: 'check', name: p.name });
          break;
        }
        const pay = Math.min(toCall, p.stack);
        p.stack -= pay;
        p.bet += pay;
        p.committed += pay;
        if (p.stack === 0) p.allIn = true;
        this.actedSinceRaise.add(i);
        p.lastAction = { type: 'call', amount: pay, allIn: p.allIn };
        this.addLog({ key: 'call', name: p.name, amount: pay, allIn: p.allIn });
        break;
      }
      case 'raise': {
        if (p.stack <= toCall) return { error: 'Nicht genug Chips zum Erhoehen.' };
        const maxTo = p.bet + p.stack; // All-In-Ziel
        let raiseTo = Math.floor(Number(amount));
        if (!Number.isFinite(raiseTo)) return { error: 'Ungueltiger Betrag.' };
        const minTo = this.currentBet + this.minRaise;
        if (raiseTo > maxTo) raiseTo = maxTo;
        const isAllIn = raiseTo === maxTo;
        if (raiseTo < minTo && !isAllIn)
          return { error: `Mindestens auf ${minTo} erhoehen.` };
        if (raiseTo <= this.currentBet)
          return { error: 'Erhoehung muss ueber dem aktuellen Einsatz liegen.' };

        const pay = raiseTo - p.bet;
        const prevBet = this.currentBet;
        p.stack -= pay;
        p.bet = raiseTo;
        p.committed += pay;
        if (p.stack === 0) p.allIn = true;
        // Eine echte (volle) Erhoehung setzt minRaise neu und oeffnet die Runde.
        const raiseSize = raiseTo - prevBet;
        if (raiseSize >= this.minRaise) {
          this.minRaise = raiseSize;
          this.actedSinceRaise = new Set([i]);
        } else {
          // Unter-Minimum (nur per All-In moeglich): eroeffnet die Runde nicht neu.
          this.actedSinceRaise.add(i);
        }
        this.currentBet = raiseTo;
        // "Bet" wenn vorher kein Einsatz lag, sonst "Raise".
        p.lastAction = { type: prevBet > 0 ? 'raise' : 'bet', to: raiseTo, allIn: p.allIn };
        this.addLog({ key: 'raise', name: p.name, to: raiseTo, allIn: p.allIn });
        break;
      }
      default:
        return { error: 'Unbekannte Aktion.' };
    }

    this.syncPot();

    if (this.isBettingClosed()) {
      this.proceedAfterBetting();
    } else {
      const nxt = this.nextToAct(i);
      if (nxt === null) this.proceedAfterBetting();
      else this.toAct = nxt;
    }
    return { ok: true };
  }

  endByFold() {
    const winner = this.players.findIndex((p) => !p.folded);
    this.distribute('fold', null, [winner]);
    return { ok: true };
  }

  // Freiwilliges Aufdecken: Nach einem Fold-Sieg darf der verbliebene Spieler
  // seine Karten zeigen (klassisches "Show"). Wird an alle gebroadcastet.
  revealOwn(playerId) {
    if (this.stage !== 'handover' || this.result?.reason !== 'fold')
      return { error: 'Zeigen jetzt nicht moeglich.' };
    const i = this.players.findIndex((p) => p.id === playerId);
    if (i < 0) return { error: 'Unbekannter Spieler.' };
    if (this.players[i].folded)
      return { error: 'Gefoldete Karten koennen nicht gezeigt werden.' };
    if (this.shownCards.has(i)) return { ok: true };
    this.shownCards.add(i);

    // Wertung nur berechnen, wenn genug Karten fuer eine 5-Karten-Hand vorliegen
    // (bei einem Preflop-Fold fehlt das Board, dann zeigen wir nur die Karten).
    let ev = null;
    if (this.players[i].hole.length + this.community.length >= 5)
      ev = evaluate([...this.players[i].hole, ...this.community], { flush: this.flush });
    if (!this.result.reveal) this.result.reveal = [];
    if (!this.result.reveal.find((r) => r.i === i))
      this.result.reveal.push({ i, hole: this.players[i].hole, eval: ev, folded: false });

    this.addLog({ key: 'shown', name: this.players[i].name });
    return { ok: true };
  }

  isBettingClosed() {
    const inHand = this.players.filter((p) => !p.folded);
    if (inHand.length <= 1) return true;
    const matched = inHand.every((p) => p.allIn || p.bet === this.currentBet);
    if (!matched) return false;
    const canAct = inHand.filter((p) => !p.allIn);
    if (canAct.length <= 1) {
      // Nur einer (oder keiner) kann noch handeln: Runde ist zu, sobald er gehandelt hat
      // bzw. nichts zu callen ist.
      if (canAct.length === 0) return true;
      const onlyOne = canAct[0];
      return this.actedSinceRaise.has(this.players.indexOf(onlyOne));
    }
    return canAct.every((p) => this.actedSinceRaise.has(this.players.indexOf(p)));
  }

  canActCount() {
    return this.players.filter((p) => !p.folded && !p.allIn).length;
  }

  // Anzahl Spieler, die noch in der Hand sind (nicht gefoldet) -> potenzielle Showdown-Teilnehmer.
  contenderCount() {
    return this.players.filter((p) => !p.folded).length;
  }

  proceedAfterBetting() {
    // Neue Setzrunde: Einsaetze und Aktions-Anzeigen zuruecksetzen (gefoldete
    // Spieler behalten ihr "Fold", solange sie gefoldet sind).
    for (const p of this.players) {
      p.bet = 0;
      if (!p.folded) p.lastAction = null;
    }
    this.currentBet = 0;
    this.minRaise = this.bigBlind;
    this.actedSinceRaise = new Set();

    // All-In-Run-out: keiner (oder nur einer) kann mehr handeln, aber >=2 Spieler
    // stehen im Showdown und es fehlen noch Gemeinschaftskarten.
    const isRunout =
      this.contenderCount() >= 2 &&
      this.canActCount() < 2 &&
      this.community.length < 5;

    if (isRunout && !this.autoRunout) {
      // Server-Modus: gestaffelt aufdecken. Wahrscheinlichkeiten jetzt berechnen,
      // dann auf externe stepRunout()-Takte warten.
      this.runoutActive = true;
      this.computeEquities();
      return;
    }

    while (true) {
      if (this.advanceStreet()) return this.showdown();

      if (this.canActCount() >= 2) {
        // Postflop handelt der erste aktive Spieler links vom Button.
        this.toAct = this.firstActorFrom((this.button + 1) % this.n);
        if (this.toAct !== null) return;
      }
      // sonst: Auto-Run-out zur naechsten Strasse
    }
  }

  // Deckt die naechste Strasse auf. Liefert true, wenn der River bereits lag
  // (also ein Showdown ansteht).
  advanceStreet() {
    if (this.stage === 'preflop') {
      this.dealCommunity(3);
      this.stage = 'flop';
    } else if (this.stage === 'flop') {
      this.dealCommunity(1);
      this.stage = 'turn';
    } else if (this.stage === 'turn') {
      this.dealCommunity(1);
      this.stage = 'river';
    } else if (this.stage === 'river') {
      return true;
    }
    return false;
  }

  // Ein Takt des gestaffelten All-In-Run-outs (vom Server per Timer aufgerufen).
  // "Sweat": deckt genau EINE Gemeinschaftskarte pro Takt auf (auch den Flop
  // Karte fuer Karte), und fuehrt nach der fuenften Karte den Showdown durch.
  // Liefert { done } – done=true, sobald die Hand abgeschlossen ist.
  stepRunout() {
    if (!this.runoutActive) return { done: true };
    // Board komplett -> Showdown.
    if (this.community.length >= 5) {
      this.runoutActive = false;
      this.equities = null;
      this.showdown();
      return { done: true };
    }
    this.dealOneRunoutCard();
    this.computeEquities();
    return { done: false };
  }

  // Deckt im All-In-Run-out genau eine Gemeinschaftskarte auf, aktualisiert die
  // Strasse und loggt erst, wenn eine Strasse vollstaendig sichtbar ist (damit
  // der Flop nicht dreifach im Log auftaucht).
  dealOneRunoutCard() {
    this.community.push(this.deck.pop());
    const len = this.community.length;
    if (len <= 3) this.stage = 'flop';
    else if (len === 4) this.stage = 'turn';
    else this.stage = 'river';
    if (len === 3) {
      const cards = this.community.slice(0, 3).map((c) => ({ rank: c.rank, suit: c.suit }));
      this.addLog({ key: 'community', street: 'flop', cards });
    } else if (len === 4) {
      const c = this.community[3];
      this.addLog({ key: 'community', street: 'turn', cards: [{ rank: c.rank, suit: c.suit }] });
    } else if (len === 5) {
      const c = this.community[4];
      this.addLog({ key: 'community', street: 'river', cards: [{ rank: c.rank, suit: c.suit }] });
    }
  }

  dealCommunity(n) {
    const street = n === 3 ? 'flop' : this.stage === 'flop' ? 'turn' : 'river';
    for (let k = 0; k < n; k++) this.community.push(this.deck.pop());
    const cards = this.community.slice(-n).map((c) => ({ rank: c.rank, suit: c.suit }));
    this.addLog({ key: 'community', street, cards });
  }

  // ---- All-In-Gewinnwahrscheinlichkeiten ----
  // Berechnet fuer alle noch nicht gefoldeten Spieler die Equity (Gewinn-/Split-Anteil)
  // ueber die noch fehlenden Gemeinschaftskarten. Exakte Enumeration, wenn die Anzahl
  // der Kombinationen klein ist, sonst Monte-Carlo-Stichprobe.
  computeEquities() {
    const contenders = this.players
      .map((p, i) => ({ p, i }))
      .filter((x) => !x.p.folded);
    if (contenders.length < 2) {
      this.equities = null;
      return;
    }

    const need = 5 - this.community.length;
    // Verbleibendes Deck = alle Karten, die weder auf der Hand eines Contenders
    // noch auf dem Board liegen. (Gefoldete Hole-Cards sind unbekannt -> bleiben im Topf.)
    const used = new Set();
    const key = (c) => c.rank * 10 + c.suit;
    for (const c of this.community) used.add(key(c));
    for (const x of contenders) for (const c of x.p.hole) used.add(key(c));
    const deck = [];
    for (const c of buildDeck()) if (!used.has(key(c))) deck.push(c);

    const wins = new Array(contenders.length).fill(0);
    let total = 0;

    const tally = (board) => {
      const full = [...this.community, ...board];
      let best = null;
      let bestIdxs = [];
      for (let k = 0; k < contenders.length; k++) {
        const sc = evaluate([...contenders[k].p.hole, ...full], { flush: this.flush }).score;
        const cmp = best === null ? 1 : compareScores(sc, best);
        if (cmp > 0) {
          best = sc;
          bestIdxs = [k];
        } else if (cmp === 0) {
          bestIdxs.push(k);
        }
      }
      const share = 1 / bestIdxs.length;
      for (const k of bestIdxs) wins[k] += share;
      total++;
    };

    if (need === 0) {
      tally([]);
    } else {
      const combos = nCk(deck.length, need);
      if (combos <= 20000) {
        // Exakte Enumeration aller fehlenden Boards.
        const idx = [];
        const rec = (start, depth) => {
          if (depth === need) {
            tally(idx.map((j) => deck[j]));
            return;
          }
          for (let j = start; j < deck.length; j++) {
            idx.push(j);
            rec(j + 1, depth + 1);
            idx.pop();
          }
        };
        rec(0, 0);
      } else {
        // Monte-Carlo-Stichprobe.
        const SAMPLES = 2500;
        for (let s = 0; s < SAMPLES; s++) {
          // Zufaellige `need` verschiedene Karten ziehen (Fisher-Yates-Teilmischung).
          const pool = deck.slice();
          const board = [];
          for (let d = 0; d < need; d++) {
            const r = d + Math.floor(Math.random() * (pool.length - d));
            const tmp = pool[d];
            pool[d] = pool[r];
            pool[r] = tmp;
            board.push(pool[d]);
          }
          tally(board);
        }
      }
    }

    this.equities = contenders.map((x, k) => ({
      i: x.i,
      pct: total > 0 ? Math.round((wins[k] / total) * 100) : 0,
    }));
  }

  showdown() {
    this.stage = 'showdown';
    const contenders = this.players
      .map((p, i) => ({ p, i }))
      .filter((x) => !x.p.folded);

    const evals = contenders.map((x) => ({
      i: x.i,
      eval: evaluate([...x.p.hole, ...this.community], { flush: this.flush }),
    }));

    this.distribute('showdown', evals, null);
    return { ok: true };
  }

  // ---- Side-Pot-Verteilung ----
  // Baut geschichtete Pots aus den committed-Betraegen aller Spieler.
  buildSidePots() {
    const remaining = this.players.map((p, i) => ({
      i,
      amount: p.committed,
      folded: p.folded,
    }));
    const pots = [];
    let carry = 0;
    while (true) {
      const positive = remaining.filter((c) => c.amount > 0);
      if (positive.length === 0) break;
      const min = Math.min(...positive.map((c) => c.amount));
      let amount = 0;
      const eligible = [];
      for (const c of remaining) {
        if (c.amount > 0) {
          amount += min;
          c.amount -= min;
          if (!c.folded) eligible.push(c.i);
        }
      }
      if (eligible.length === 0) {
        carry += amount; // sollte praktisch nie auftreten
        continue;
      }
      amount += carry;
      carry = 0;
      pots.push({ amount, eligible });
    }
    return pots;
  }

  distribute(reason, evals, foldWinners) {
    const evalMap = new Map();
    if (evals) for (const e of evals) evalMap.set(e.i, e.eval);

    const pots = this.buildSidePots();
    const winnings = new Map(); // i -> Gewinn

    for (const pot of pots) {
      let winners;
      if (reason === 'fold') {
        winners = foldWinners.filter((w) => pot.eligible.includes(w));
        if (winners.length === 0) winners = pot.eligible;
      } else {
        let best = null;
        for (const i of pot.eligible) {
          const sc = evalMap.get(i).score;
          if (!best || compareScores(sc, best) > 0) best = sc;
        }
        winners = pot.eligible.filter(
          (i) => compareScores(evalMap.get(i).score, best) === 0
        );
      }
      pot.winners = [...winners]; // pro Pot festhalten (fuer Split-Pot-Anzeige)

      // Aufteilen, ungerade Chips an die ersten Sitze links vom Button.
      const ordered = [...winners].sort(
        (a, b) =>
          ((a - this.button + this.n) % this.n) -
          ((b - this.button + this.n) % this.n)
      );
      const share = Math.floor(pot.amount / winners.length);
      let remainder = pot.amount - share * winners.length;
      for (const w of ordered) {
        let amt = share;
        if (remainder > 0) {
          amt += 1;
          remainder -= 1;
        }
        this.players[w].stack += amt;
        winnings.set(w, (winnings.get(w) || 0) + amt);
      }
    }

    const totalPot = this.players.reduce((s, p) => s + p.committed, 0);

    // Log (strukturiert, Uebersetzung im Client)
    if (reason === 'fold') {
      const w = foldWinners[0];
      this.addLog({ key: 'winFold', name: this.players[w].name, pot: totalPot });
    } else {
      const winnerEntries = [...winnings.entries()].sort((a, b) => b[1] - a[1]);
      for (const [i, amt] of winnerEntries) {
        this.addLog({
          key: 'win',
          name: this.players[i].name,
          amount: amt,
          cat: evalMap.get(i)?.score?.[0] ?? null,
          flush: this.flush,
        });
      }
    }

    this.result = {
      reason,
      winners: [...winnings.keys()],
      winnings: [...winnings.entries()].map(([i, amount]) => ({ i, amount })),
      pot: totalPot,
      pots: pots.map((p) => ({ amount: p.amount, eligible: p.eligible, winners: p.winners || [] })),
      reveal:
        reason === 'showdown'
          ? this.players.map((p, i) => ({
              i,
              hole: p.hole,
              eval: evalMap.get(i) || null,
              folded: p.folded,
            }))
          : null,
    };

    for (const p of this.players) {
      p.bet = 0;
      p.committed = 0;
    }
    this.pot = 0;
    this.toAct = null;
    this.stage = 'handover';

    // Match-Ende? Nur noch ein Spieler mit Chips. Im Cash-Game endet nichts –
    // gebustete Spieler koennen per Rebuy nachkaufen.
    if (!this.cash) {
      const withChips = this.players.filter((p) => p.stack > 0);
      if (withChips.length <= 1) {
        this.matchOver = true;
        this.matchWinnerId = withChips[0]?.id || null;
        if (withChips[0]) this.addLog({ key: 'matchOver', name: withChips[0].name });
      }
    }
  }

  // Cash-Game-Rebuy: Chips zwischen den Haenden nachkaufen. Gibt den tatsaechlich
  // gutgeschriebenen Betrag zurueck (0 bei Fehler) – der Server bucht ihn vom Wallet.
  rebuy(playerId, amount) {
    if (!this.cash) return { error: 'Rebuy nur im Cash-Game.' };
    if (this.stage !== 'idle' && this.stage !== 'handover')
      return { error: 'Rebuy nur zwischen den Haenden.' };
    const p = this.players.find((x) => x.id === playerId);
    if (!p) return { error: 'Spieler nicht gefunden.' };
    const amt = Math.floor(Number(amount));
    if (!(amt > 0)) return { error: 'Ungueltiger Betrag.' };
    p.stack += amt;
    this.addLog({ key: 'rebuy', name: p.name, amount: amt });
    return { ok: true, amount: amt };
  }

  // Aktueller Stack eines Spielers (fuer Cash-out beim Verlassen).
  stackOf(playerId) {
    const p = this.players.find((x) => x.id === playerId);
    return p ? p.stack : 0;
  }

  // ---- Spieler-spezifische Sicht ----
  view(playerId) {
    const meIdx = this.players.findIndex((p) => p.id === playerId);
    const showAll = this.stage === 'showdown' || this.stage === 'handover';

    const mkPlayer = (p, i) => {
      const isMe = i === meIdx;
      const revealHole =
        isMe ||
        (showAll && !p.folded && this.result?.reason === 'showdown') ||
        (showAll && this.shownCards.has(i));
      return {
        id: p.id,
        name: p.name,
        stack: p.stack,
        bet: p.bet,
        committed: p.committed,
        folded: p.folded,
        allIn: p.allIn,
        inHand: p.inHand,
        out: p.stack <= 0 && !p.inHand,
        isButton: i === this.button,
        isSB: i === this.sbPos,
        isBB: i === this.bbPos,
        isMe,
        seat: i,
        lastAction: p.lastAction || null,
        hole: revealHole ? p.hole : p.hole.map(() => null),
      };
    };

    const me = meIdx >= 0 ? this.players[meIdx] : null;
    const toCall =
      this.toAct !== null ? this.currentBet - this.players[this.toAct].bet : 0;
    const yourTurn = this.toAct === meIdx && meIdx >= 0;
    const minRaiseTo = me
      ? Math.min(this.currentBet + this.minRaise, me.bet + me.stack)
      : 0;
    const maxRaiseTo = me ? me.bet + me.stack : 0;

    // Zentraler Pot = bereits eingesammelt (ohne aktuelle Bets, die als Chips davor liegen).
    const collected = this.players.reduce((s, p) => s + (p.committed - p.bet), 0);

    // Live-Handstaerke fuer mich, solange ich aktiv in einer laufenden Hand bin.
    let myHand = null;
    if (
      me &&
      !me.folded &&
      me.inHand &&
      (this.stage === 'preflop' ||
        this.stage === 'flop' ||
        this.stage === 'turn' ||
        this.stage === 'river')
    ) {
      myHand = { cat: liveCategory(me.hole, this.community, this.flush) };
    }

    return {
      handNo: this.handNo,
      stage: this.stage,
      flush: this.flush,
      cash: this.cash,
      buyIn: this.cash ? this.startingStack : null,
      myStack: me ? me.stack : 0,
      betweenHands: this.stage === 'idle' || this.stage === 'handover',
      community: this.community,
      pot: collected,
      totalPot: this.players.reduce((s, p) => s + p.committed, 0),
      currentBet: this.currentBet,
      players: this.players.map(mkPlayer),
      meIdx,
      button: this.button,
      toActId: this.toAct !== null ? this.players[this.toAct].id : null,
      yourTurn,
      actions:
        yourTurn && me
          ? {
              canCheck: toCall <= 0,
              canCall: toCall > 0,
              toCall: Math.min(toCall, me.stack),
              canRaise: me.stack > Math.max(0, toCall),
              minRaiseTo,
              maxRaiseTo,
            }
          : null,
      result: this.result,
      shown: [...this.shownCards],
      runout: this.runoutActive,
      equities: this.runoutActive ? this.equities : null,
      myHand,
      log: this.log,
      matchOver: this.matchOver,
      matchWinnerId: this.matchWinnerId,
      blinds: {
        sb: this.smallBlind,
        bb: this.bigBlind,
        tournament: this.tournament,
        level: this.tournament ? this.blindLevel + 1 : null,
        nextLevelIn: this.handsUntilNextLevel(),
      },
    };
  }
}
