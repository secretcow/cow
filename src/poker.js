// Heads-up Texas Hold'em Engine (2 Spieler) mit Kuhhandel-Tierkarten.
// Autoritativer Spielzustand. Clients schicken nur Aktionen, der Server validiert alles.

import { buildDeck, shuffle, animalByRank } from './cards.js';
import { evaluate, compareScores } from './handEval.js';

export const STARTING_STACK = 1000;
export const SMALL_BLIND = 10;
export const BIG_BLIND = 20;

export class Table {
  constructor(p0, p1) {
    // p0, p1: { id, name }
    this.players = [p0, p1].map((p) => ({
      id: p.id,
      name: p.name,
      stack: STARTING_STACK,
      hole: [],
      bet: 0, // Einsatz in der aktuellen Setzrunde
      committed: 0, // Einsatz insgesamt in dieser Hand
      folded: false,
      allIn: false,
    }));
    this.button = 1; // wird beim ersten startHand auf 0 rotiert
    this.handNo = 0;
    this.stage = 'idle'; // idle | preflop | flop | turn | river | showdown | handover
    this.community = [];
    this.deck = [];
    this.pot = 0;
    this.currentBet = 0;
    this.minRaise = BIG_BLIND;
    this.toAct = null;
    this.actedSinceRaise = new Set();
    this.log = [];
    this.result = null; // Showdown-/Fold-Ergebnis
    this.matchOver = false;
    this.matchWinnerId = null;
  }

  addLog(msg) {
    this.log.push(msg);
    if (this.log.length > 30) this.log.shift();
  }

  // Revanche: Stacks zuruecksetzen, neues Match.
  resetMatch() {
    for (const p of this.players) {
      p.stack = STARTING_STACK;
      p.hole = [];
      p.bet = 0;
      p.committed = 0;
      p.folded = false;
      p.allIn = false;
    }
    this.button = 1;
    this.handNo = 0;
    this.stage = 'idle';
    this.community = [];
    this.deck = [];
    this.pot = 0;
    this.currentBet = 0;
    this.minRaise = BIG_BLIND;
    this.toAct = null;
    this.actedSinceRaise = new Set();
    this.result = null;
    this.matchOver = false;
    this.matchWinnerId = null;
    this.log = [];
    this.addLog('Revanche! Neue Stacks, neues Glueck.');
    return { ok: true };
  }

  other(i) {
    return i === 0 ? 1 : 0;
  }

  // ---- Hand starten ----
  startHand() {
    if (this.matchOver) return { error: 'Match ist beendet.' };
    if (this.stage !== 'idle' && this.stage !== 'handover')
      return { error: 'Hand laeuft noch.' };
    if (this.players.some((p) => p.stack <= 0))
      return { error: 'Ein Spieler hat keine Chips mehr.' };

    this.handNo++;
    this.button = this.other(this.button);
    this.deck = shuffle(buildDeck());
    this.community = [];
    this.pot = 0;
    this.currentBet = 0;
    this.minRaise = BIG_BLIND;
    this.result = null;
    this.actedSinceRaise = new Set();

    for (const p of this.players) {
      p.hole = [this.deck.pop(), this.deck.pop()];
      p.bet = 0;
      p.committed = 0;
      p.folded = false;
      p.allIn = false;
    }

    // Blinds: Button = Small Blind, Gegner = Big Blind (Heads-up)
    const sb = this.button;
    const bb = this.other(this.button);
    this.postBlind(sb, SMALL_BLIND);
    this.postBlind(bb, BIG_BLIND);
    this.currentBet = BIG_BLIND;
    this.minRaise = BIG_BLIND;

    this.stage = 'preflop';
    // Praeflop handelt der Button (Small Blind) zuerst.
    this.toAct = sb;
    this.addLog(`— Hand ${this.handNo} — ${this.players[sb].name} ist Button/Small Blind.`);
    this.syncPot();
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
  // type: 'fold' | 'check' | 'call' | 'raise'  (raise: amount = Ziel-Gesamteinsatz dieser Runde)
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
        this.addLog(`${p.name} steigt aus (Fold).`);
        return this.endByFold();
      }
      case 'check': {
        if (toCall > 0) return { error: 'Check nicht moeglich, es liegt ein Einsatz an.' };
        this.actedSinceRaise.add(i);
        this.addLog(`${p.name} checkt.`);
        break;
      }
      case 'call': {
        if (toCall <= 0) {
          // wie Check behandeln
          this.actedSinceRaise.add(i);
          this.addLog(`${p.name} checkt.`);
          break;
        }
        const pay = Math.min(toCall, p.stack);
        p.stack -= pay;
        p.bet += pay;
        p.committed += pay;
        if (p.stack === 0) p.allIn = true;
        this.actedSinceRaise.add(i);
        this.addLog(`${p.name} geht mit (${pay}).${p.allIn ? ' All-In!' : ''}`);
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
        if (raiseTo <= this.currentBet) return { error: 'Erhoehung muss ueber dem aktuellen Einsatz liegen.' };

        const pay = raiseTo - p.bet;
        const prevBet = this.currentBet;
        p.stack -= pay;
        p.bet = raiseTo;
        p.committed += pay;
        if (p.stack === 0) p.allIn = true;
        this.minRaise = Math.max(this.minRaise, raiseTo - prevBet);
        this.currentBet = raiseTo;
        this.actedSinceRaise = new Set([i]);
        this.addLog(`${p.name} erhoeht auf ${raiseTo}.${p.allIn ? ' All-In!' : ''}`);
        break;
      }
      default:
        return { error: 'Unbekannte Aktion.' };
    }

    this.syncPot();

    if (this.isBettingClosed()) {
      this.proceedAfterBetting();
    } else {
      this.toAct = this.nextToAct(i);
    }
    return { ok: true };
  }

  endByFold() {
    const winner = this.players.findIndex((p) => !p.folded);
    this.distribute([winner], 'fold');
    return { ok: true };
  }

  nextToAct(fromIndex) {
    const j = this.other(fromIndex);
    const p = this.players[j];
    if (p.folded || p.allIn) return fromIndex; // sollte hier nicht vorkommen
    return j;
  }

  isBettingClosed() {
    const inHand = this.players.filter((p) => !p.folded);
    const matched = inHand.every((p) => p.allIn || p.bet === this.currentBet);
    if (!matched) return false;
    const canAct = inHand.filter((p) => !p.allIn);
    if (canAct.length <= 1) return true;
    return canAct.every((p) => this.actedSinceRaise.has(this.players.indexOf(p)));
  }

  // Naechste Strasse aufdecken oder Showdown.
  proceedAfterBetting() {
    // Einsaetze der Runde sind bereits in committed; bet zuruecksetzen.
    for (const p of this.players) p.bet = 0;
    this.currentBet = 0;
    this.minRaise = BIG_BLIND;
    this.actedSinceRaise = new Set();

    const canActCount = () =>
      this.players.filter((p) => !p.folded && !p.allIn).length;

    // Strassen nacheinander; wenn niemand mehr handeln kann, automatisch durchlaufen.
    while (true) {
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
        return this.showdown();
      }

      if (canActCount() >= 2) {
        // Postflop handelt der Nicht-Button-Spieler zuerst.
        const first = this.other(this.button);
        this.toAct = this.players[first].folded || this.players[first].allIn
          ? this.other(first)
          : first;
        return;
      }
      // sonst: weiter zur naechsten Strasse (Auto-Run-out)
    }
  }

  dealCommunity(n) {
    for (let k = 0; k < n; k++) this.community.push(this.deck.pop());
    const names = this.community
      .slice(-n)
      .map((c) => animalByRank(c.rank).name)
      .join(', ');
    const label = { 3: 'Flop', 1: this.stage === 'flop' ? 'Turn' : 'River' }[n] || 'Karten';
    this.addLog(`${label}: ${names}`);
  }

  showdown() {
    this.stage = 'showdown';
    const contenders = this.players
      .map((p, i) => ({ p, i }))
      .filter((x) => !x.p.folded);

    const evals = contenders.map((x) => ({
      i: x.i,
      eval: evaluate([...x.p.hole, ...this.community]),
    }));

    let best = evals[0];
    for (const e of evals) if (compareScores(e.eval.score, best.eval.score) > 0) best = e;
    const winners = evals
      .filter((e) => compareScores(e.eval.score, best.eval.score) === 0)
      .map((e) => e.i);

    this.distribute(winners, 'showdown', evals);
    return { ok: true };
  }

  distribute(winners, reason, evals = null) {
    // Nicht mitgegangene Ueberzahl zurueckgeben (Heads-up: hoechster Einsatz ueber dem zweithoechsten).
    const sorted = [...this.players].sort((a, b) => b.committed - a.committed);
    const uncalled = sorted[0].committed - sorted[1].committed;
    if (uncalled > 0) {
      sorted[0].stack += uncalled;
      sorted[0].committed -= uncalled;
      this.addLog(`${sorted[0].name} bekommt ${uncalled} (nicht mitgegangen) zurueck.`);
    }
    this.syncPot();
    const pot = this.pot;

    const share = Math.floor(pot / winners.length);
    let remainder = pot - share * winners.length;
    for (const w of winners) {
      let amt = share;
      if (remainder > 0) {
        amt += 1;
        remainder -= 1;
      }
      this.players[w].stack += amt;
    }

    const names = winners.map((w) => this.players[w].name).join(' & ');
    if (reason === 'fold') {
      this.addLog(`${names} gewinnt den Pot (${pot}) — Gegner ausgestiegen.`);
    } else {
      const handName = evals
        ? evals.find((e) => e.i === winners[0]).eval.name
        : '';
      if (winners.length > 1) this.addLog(`Split Pot (${pot}) — ${handName}.`);
      else this.addLog(`${names} gewinnt ${pot} mit ${handName}.`);
    }

    this.result = {
      reason,
      winners,
      pot,
      reveal:
        reason === 'showdown'
          ? this.players.map((p, i) => ({
              i,
              hole: p.hole,
              eval: evals.find((e) => e.i === i)?.eval || null,
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

    // Match-Ende?
    const broke = this.players.find((p) => p.stack <= 0);
    if (broke) {
      this.matchOver = true;
      this.matchWinnerId = this.players.find((p) => p.stack > 0).id;
      this.addLog(`Match beendet — ${this.players.find((p) => p.stack > 0).name} gewinnt!`);
    }
  }

  // ---- Spieler-spezifische Sicht (versteckt gegnerische Handkarten) ----
  view(playerId) {
    const meIdx = this.players.findIndex((p) => p.id === playerId);
    const showAll = this.stage === 'showdown' || this.stage === 'handover';

    const mkPlayer = (p, i) => {
      const isMe = i === meIdx;
      const revealHole = isMe || (showAll && !p.folded && this.result?.reason === 'showdown');
      return {
        id: p.id,
        name: p.name,
        stack: p.stack,
        bet: p.bet,
        committed: p.committed,
        folded: p.folded,
        allIn: p.allIn,
        isButton: i === this.button,
        isMe,
        hole: revealHole ? p.hole : p.hole.map(() => null),
      };
    };

    const me = this.players[meIdx];
    const toCall = this.toAct !== null ? this.currentBet - this.players[this.toAct].bet : 0;
    const yourTurn = this.toAct === meIdx;
    const minRaiseTo = Math.min(this.currentBet + this.minRaise, me ? me.bet + me.stack : 0);
    const maxRaiseTo = me ? me.bet + me.stack : 0;

    return {
      handNo: this.handNo,
      stage: this.stage,
      community: this.community,
      pot: this.pot + this.players.reduce((s, p) => s + p.bet, 0),
      currentBet: this.currentBet,
      players: this.players.map(mkPlayer),
      meIdx,
      toActId: this.toAct !== null ? this.players[this.toAct].id : null,
      yourTurn,
      actions: yourTurn
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
      log: this.log,
      matchOver: this.matchOver,
      matchWinnerId: this.matchWinnerId,
      blinds: { sb: SMALL_BLIND, bb: BIG_BLIND },
    };
  }
}
