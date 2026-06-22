/* global io */
const socket = io({
  // Unbegrenzt automatisch neu verbinden, mit kurzem Start- und gedeckeltem
  // Maximal-Backoff – so kehrt der Client nach einem Aussetzer schnell zurueck.
  reconnection: true,
  reconnectionAttempts: Infinity,
  reconnectionDelay: 500,
  reconnectionDelayMax: 4000,
  timeout: 20000,
});

// ---------- Daten ----------
const ANIMALS = {
  1: { de: 'Hahn', en: 'Rooster', value: 10, emoji: '🐓' },
  2: { de: 'Gans', en: 'Goose', value: 40, emoji: '🪿' },
  3: { de: 'Katze', en: 'Cat', value: 90, emoji: '🐈' },
  4: { de: 'Hund', en: 'Dog', value: 160, emoji: '🐕' },
  5: { de: 'Schaf', en: 'Sheep', value: 250, emoji: '🐑' },
  6: { de: 'Ziege', en: 'Goat', value: 350, emoji: '🐐' },
  7: { de: 'Esel', en: 'Donkey', value: 500, emoji: '🫏' },
  8: { de: 'Schwein', en: 'Pig', value: 650, emoji: '🐖' },
  9: { de: 'Kuh', en: 'Cow', value: 800, emoji: '🐄' },
  10: { de: 'Pferd', en: 'Horse', value: 1000, emoji: '🐎' },
};
const SUITS = [
  { de: 'Sonne', en: 'Sun', color: '#f5b50a', symbol: '☀' },
  { de: 'Mond', en: 'Moon', color: '#5a8fe6', symbol: '☾' },
  { de: 'Klee', en: 'Clover', color: '#3fae5a', symbol: '☘' },
  { de: 'Herz', en: 'Heart', color: '#e2483b', symbol: '♥' },
];

// Kategorie-Code -> semantische ID (abhaengig vom Flush-Modus).
const CAT_IDS_FLUSH = { 10: 'sflush', 9: 'quads', 8: 'flush', 7: 'full', 6: 'straight', 5: 'trips', 4: 'twopair', 3: 'pair', 2: 'high' };
const CAT_IDS_NOFLUSH = { 8: 'quads', 7: 'full', 6: 'straight', 5: 'trips', 4: 'twopair', 3: 'pair', 2: 'high' };
const CAT_LABELS = {
  sflush: { de: 'Straße Flush', en: 'Straight Flush' },
  quads: { de: 'Vierling', en: 'Four of a Kind' },
  flush: { de: 'Flush', en: 'Flush' },
  full: { de: 'Full House', en: 'Full House' },
  straight: { de: 'Straße', en: 'Straight' },
  trips: { de: 'Drilling', en: 'Three of a Kind' },
  twopair: { de: 'Zwei Paare', en: 'Two Pair' },
  pair: { de: 'Paar', en: 'Pair' },
  high: { de: 'Hohe Karte', en: 'High Card' },
};

// ---------- i18n ----------
const I18N = {
  de: {
    subtitle: "Texas Hold'em mit Kuhhandel-Tierkarten",
    yourName: 'Dein Name',
    namePlaceholder: 'z. B. Anna',
    maxPlayers: 'Max. Spieler',
    startChips: 'Start-Chips',
    flushMode: 'Flush-Modus',
    on: 'An',
    off: 'Aus',
    flushHint:
      'An: Farben zählen — ein Flush (5 gleiche Farben) schlägt sogar das Full House. Aus: Farben sind nur Deko, kein Flush.',
    tournamentMode: 'Turnier-Modus',
    levelLength: 'Hände pro Stufe',
    tourneyHint:
      'An: Turnier mit steigenden Blinds — alle paar Hände werden Small/Big Blind höher. Aus: Blinds bleiben konstant bei 10/20.',
    cashMode: 'Cash-Game',
    cashHint:
      'An: Buy-in aus deinem Guthaben — busten beendet das Spiel nicht, du kannst nachkaufen (Rebuy). Beim Verlassen gehen deine Chips zurück aufs Guthaben (Cash-out).',
    cashHintOn: (buy) => `An: Buy-in ${buy.toLocaleString()} 🪙 aus deinem Guthaben. Rebuy jederzeit zwischen den Händen, Cash-out beim Verlassen.`,
    rebuyBtn: '➕ Rebuy',
    rebuyDone: (n) => `Rebuy: +${n.toLocaleString()} 🪙`,
    cashTag: 'Cash',
    blindInfo: (sb, bb, lvl) => `Blinds ${sb}/${bb} · Stufe ${lvl}`,
    nextBlindIn: (n) => ` · ↑ in ${n}`,
    createTable: 'Neuen Tisch erstellen',
    or: 'oder',
    codePlaceholder: 'CODE',
    join: 'Beitreten',
    shareCode: 'Tisch-Code zum Teilen:',
    copyLink: 'Einladungslink kopieren',
    startGame: 'Spiel starten',
    rulesSummary: 'Spielregeln',
    leaderboardTitle: '🏆 Bestenliste',
    lbEmpty: 'Noch keine gewonnenen Matches.',
    lbMatches: (n) => `${n} ${n === 1 ? 'Match' : 'Matches'}`,
    walletTitle: 'Guthaben',
    matchesTitle: 'Gewonnene Matches',
    statsTitle: '📊 Deine Statistik',
    statHandsPlayed: 'Hände gespielt',
    statHandsWon: 'Hände gewonnen',
    statWinRate: 'Gewinnrate',
    statBiggestPot: 'Größter Pot',
    statMatchesWon: 'Matches gewonnen',
    ranksTitle: 'Rangfolge',
    cardsTitle: 'Karten',
    suitsTitle: 'Farben',
    strong: 'stark',
    weak: 'schwach',
    enterCode: 'Bitte einen Code eingeben.',
    linkCopied: 'Link kopiert!',
    waitMore: 'Warte auf weitere Spieler …',
    waitHost: 'Warte darauf, dass der Host startet …',
    readyHost: 'Bereit! Du kannst das Spiel starten.',
    needTwo: 'Mindestens 2 Spieler nötig.',
    you: 'Du',
    table: (c) => `Tisch ${c}`,
    connected: '● verbunden',
    someoneOff: '● Spieler getrennt – warte auf Reconnect',
    waitingPlayers: '● warte auf Spieler',
    reconnecting: '● Verbindung verloren – verbinde neu…',
    reconnected: '✓ Wieder verbunden',
    pot: (n) => `Pot: ${n} 🪙`,
    stages: { idle: 'Bereit', preflop: 'Pre-Flop', flop: 'Flop', turn: 'Turn', river: 'River', showdown: 'Showdown', handover: 'Hand vorbei' },
    yourTurn: 'Du bist am Zug',
    waitingFor: (n) => `Warte auf ${n} …`,
    check: 'Check',
    call: (n) => `Call ${n}`,
    bet: 'Bet',
    raise: 'Raise',
    fold: 'Fold',
    allInBtn: 'All-In',
    min: 'Min',
    potBtn: 'Pot',
    allIn: 'All-In',
    back: 'Zurück',
    raiseDo: 'Erhöhen',
    firstHand: 'Erste Hand starten',
    nextHand: 'Nächste Hand',
    showCards: '🃏 Karten zeigen',
    replay: '🎬 Replay',
    replayTitle: 'Replay der letzten Hand',
    replayLive: '● Live',
    leaveConfirm: 'Tisch verlassen und zurück zur Lobby?',
    myHandTitle: 'Deine Hand',
    allInTitle: 'All-In — Karten werden aufgedeckt',
    winChance: 'Gewinnchance',
    chatPlaceholder: 'Nachricht …',
    send: 'Senden',
    rematch: 'Revanche',
    matchWon: '🏆 Du hast das Match gewonnen!',
    matchLost: '😿 Match verloren.',
    youWin: (n) => `Du gewinnst ${n} 🪙!`,
    splitPot: (n) => `Split Pot — ${n} 🪙 geteilt`,
    splitPotTitle: '🤝 Split Pot',
    splitYourShare: (n) => `Dein Anteil: +${n} 🪙`,
    playerWins: (name, n) => `${name} gewinnt ${n} 🪙`,
    wonWith: 'Gewonnen mit',
    mainPot: 'Hauptpot',
    sidePot: (n) => `Side-Pot ${n}`,
    potWinners: 'Gewinner',
    allInTag: 'All-In',
    outTag: 'raus',
    // Log
    log: {
      handStart: (e) => `— Hand ${e.hand} — ${e.name} hat den Button.`,
      fold: (e) => `${e.name} steigt aus (Fold).`,
      check: (e) => `${e.name} checkt.`,
      call: (e) => `${e.name} geht mit (${e.amount}).${e.allIn ? ' All-In!' : ''}`,
      raise: (e) => `${e.name} erhöht auf ${e.to}.${e.allIn ? ' All-In!' : ''}`,
      community: (e) => `${streetName('de', e.street)}: ${e.cards.map((c) => cardWords('de', c)).join(', ')}`,
      winFold: (e) => `${e.name} gewinnt den Pot (${e.pot}) — alle anderen ausgestiegen.`,
      shown: (e) => `${e.name} zeigt die Karten.`,
      win: (e) => `${e.name} gewinnt ${e.amount}${e.cat ? ` mit ${catName('de', e.cat, e.flush)}` : ''}.`,
      matchOver: (e) => `Match beendet — ${e.name} gewinnt!`,
      rematch: () => 'Revanche! Neue Stacks, neues Glück.',
      blindsUp: (e) => `⬆ Blinds steigen auf ${e.sb}/${e.bb} (Stufe ${e.level}).`,
      rebuy: (e) => `${e.name} kauft nach: +${e.amount} 🪙 (Rebuy).`,
    },
    rulesHtml: (flush) => `
      <p>10 Tiere mit Werten von Hahn (10) bis Pferd (1000), je 4-mal im Deck — jede Farbe einmal.
      Jeder bekommt 2 Handkarten, dann Flop (3), Turn (1), River (1). Beste 5 aus 7 Karten gewinnt.</p>
      <p><strong>Rangfolge (hoch → niedrig):</strong></p>
      <ol class="ranking">
        ${flush ? '<li>Straße Flush</li>' : ''}
        <li>Vierling</li>
        ${flush ? '<li>Flush (5 gleiche Farben — schlägt Full House!)</li>' : ''}
        <li>Full House</li>
        <li>Straße (Pferd zählt auch tief: Pferd-Hahn-Gans-Katze-Hund)</li>
        <li>Drilling</li><li>Zwei Paare</li><li>Paar</li><li>Hohe Karte</li>
      </ol>
      <p>${flush ? 'Flush-Modus <strong>an</strong>: Farben zählen.' : 'Ohne Flush-Modus zählen die Farben nicht — sie sind nur Deko.'}</p>`,
  },
  en: {
    subtitle: "Texas Hold'em with Cow-Trader animal cards",
    yourName: 'Your name',
    namePlaceholder: 'e.g. Anna',
    maxPlayers: 'Max players',
    startChips: 'Starting chips',
    flushMode: 'Flush mode',
    on: 'On',
    off: 'Off',
    flushHint:
      'On: suits count — a flush (5 same colour) even beats a full house. Off: colours are decorative only, no flush.',
    tournamentMode: 'Tournament mode',
    levelLength: 'Hands per level',
    tourneyHint:
      'On: tournament with rising blinds — small/big blind go up every few hands. Off: blinds stay constant at 10/20.',
    cashMode: 'Cash game',
    cashHint:
      'On: buy in from your balance — busting does not end the game, you can rebuy. When you leave, your chips return to your balance (cash-out).',
    cashHintOn: (buy) => `On: buy-in ${buy.toLocaleString()} 🪙 from your balance. Rebuy any time between hands, cash-out when you leave.`,
    rebuyBtn: '➕ Rebuy',
    rebuyDone: (n) => `Rebuy: +${n.toLocaleString()} 🪙`,
    cashTag: 'Cash',
    blindInfo: (sb, bb, lvl) => `Blinds ${sb}/${bb} · Level ${lvl}`,
    nextBlindIn: (n) => ` · ↑ in ${n}`,
    createTable: 'Create new table',
    or: 'or',
    codePlaceholder: 'CODE',
    join: 'Join',
    shareCode: 'Table code to share:',
    copyLink: 'Copy invite link',
    startGame: 'Start game',
    rulesSummary: 'Rules',
    leaderboardTitle: '🏆 Leaderboard',
    lbEmpty: 'No matches won yet.',
    lbMatches: (n) => `${n} ${n === 1 ? 'match' : 'matches'}`,
    walletTitle: 'Balance',
    matchesTitle: 'Matches won',
    statsTitle: '📊 Your stats',
    statHandsPlayed: 'Hands played',
    statHandsWon: 'Hands won',
    statWinRate: 'Win rate',
    statBiggestPot: 'Biggest pot',
    statMatchesWon: 'Matches won',
    ranksTitle: 'Hand ranking',
    cardsTitle: 'Cards',
    suitsTitle: 'Suits',
    strong: 'strong',
    weak: 'weak',
    enterCode: 'Please enter a code.',
    linkCopied: 'Link copied!',
    waitMore: 'Waiting for more players …',
    waitHost: 'Waiting for the host to start …',
    readyHost: 'Ready! You can start the game.',
    needTwo: 'At least 2 players needed.',
    you: 'You',
    table: (c) => `Table ${c}`,
    connected: '● connected',
    someoneOff: '● player disconnected – waiting for reconnect',
    waitingPlayers: '● waiting for players',
    reconnecting: '● connection lost – reconnecting…',
    reconnected: '✓ Reconnected',
    pot: (n) => `Pot: ${n} 🪙`,
    stages: { idle: 'Ready', preflop: 'Pre-Flop', flop: 'Flop', turn: 'Turn', river: 'River', showdown: 'Showdown', handover: 'Hand over' },
    yourTurn: "It's your turn",
    waitingFor: (n) => `Waiting for ${n} …`,
    check: 'Check',
    call: (n) => `Call ${n}`,
    bet: 'Bet',
    raise: 'Raise',
    fold: 'Fold',
    allInBtn: 'All-In',
    min: 'Min',
    potBtn: 'Pot',
    allIn: 'All-In',
    back: 'Back',
    raiseDo: 'Raise',
    firstHand: 'Start first hand',
    nextHand: 'Next hand',
    showCards: '🃏 Show cards',
    replay: '🎬 Replay',
    replayTitle: 'Replay of the last hand',
    replayLive: '● Live',
    leaveConfirm: 'Leave the table and return to the lobby?',
    myHandTitle: 'Your hand',
    allInTitle: 'All-In — revealing cards',
    winChance: 'Win chance',
    chatPlaceholder: 'Message …',
    send: 'Send',
    rematch: 'Rematch',
    matchWon: '🏆 You won the match!',
    matchLost: '😿 Match lost.',
    youWin: (n) => `You win ${n} 🪙!`,
    splitPot: (n) => `Split pot — ${n} 🪙 shared`,
    splitPotTitle: '🤝 Split Pot',
    splitYourShare: (n) => `Your share: +${n} 🪙`,
    playerWins: (name, n) => `${name} wins ${n} 🪙`,
    wonWith: 'Won with',
    mainPot: 'Main pot',
    sidePot: (n) => `Side pot ${n}`,
    potWinners: 'Winners',
    allInTag: 'All-In',
    outTag: 'out',
    log: {
      handStart: (e) => `— Hand ${e.hand} — ${e.name} is on the button.`,
      fold: (e) => `${e.name} folds.`,
      check: (e) => `${e.name} checks.`,
      call: (e) => `${e.name} calls (${e.amount}).${e.allIn ? ' All-In!' : ''}`,
      raise: (e) => `${e.name} raises to ${e.to}.${e.allIn ? ' All-In!' : ''}`,
      community: (e) => `${streetName('en', e.street)}: ${e.cards.map((c) => cardWords('en', c)).join(', ')}`,
      winFold: (e) => `${e.name} wins the pot (${e.pot}) — everyone else folded.`,
      shown: (e) => `${e.name} shows their cards.`,
      win: (e) => `${e.name} wins ${e.amount}${e.cat ? ` with ${catName('en', e.cat, e.flush)}` : ''}.`,
      matchOver: (e) => `Match over — ${e.name} wins!`,
      rematch: () => 'Rematch! Fresh stacks, fresh luck.',
      blindsUp: (e) => `⬆ Blinds rise to ${e.sb}/${e.bb} (level ${e.level}).`,
      rebuy: (e) => `${e.name} rebuys: +${e.amount} 🪙.`,
    },
    rulesHtml: (flush) => `
      <p>10 animals valued from Rooster (10) to Horse (1000), 4 of each in the deck — one per colour.
      Everyone gets 2 hole cards, then flop (3), turn (1), river (1). Best 5 of 7 wins.</p>
      <p><strong>Ranking (high → low):</strong></p>
      <ol class="ranking">
        ${flush ? '<li>Straight Flush</li>' : ''}
        <li>Four of a Kind</li>
        ${flush ? '<li>Flush (5 same colour — beats a full house!)</li>' : ''}
        <li>Full House</li>
        <li>Straight (Horse plays low too: Horse-Rooster-Goose-Cat-Dog)</li>
        <li>Three of a Kind</li><li>Two Pair</li><li>Pair</li><li>High Card</li>
      </ol>
      <p>${flush ? 'Flush mode <strong>on</strong>: suits count.' : 'Without flush mode the colours are decorative only.'}</p>`,
  },
};

let lang = localStorage.getItem('kuhpoker_lang') || 'de';
function t(key, ...args) {
  const v = I18N[lang][key];
  return typeof v === 'function' ? v(...args) : v;
}
function streetName(l, s) {
  return { flop: 'Flop', turn: 'Turn', river: 'River' }[s] || s;
}
function animalName(l, rank) {
  return ANIMALS[rank][l];
}
function cardWords(l, c) {
  const a = ANIMALS[c.rank];
  return a[l];
}
function catName(l, code, flush) {
  const id = (flush ? CAT_IDS_FLUSH : CAT_IDS_NOFLUSH)[code];
  return id ? CAT_LABELS[id][l] : '';
}

const $ = (id) => document.getElementById(id);
function withHotkey(label, key) {
  return `${escapeHtml(label)}<kbd class="hk">${escapeHtml(key)}</kbd>`;
}
let myCode = null;
let lastState = null;
let lastLobby = null;
let raiseOpen = false;
let createOpts = { maxPlayers: 6, flush: false, startingStack: 1000, tournament: false, levelHands: 6, cash: false };

// ---------- Token / Raum ----------
function getToken() {
  let tk = localStorage.getItem('kuhpoker_token');
  if (!tk) {
    tk = (crypto.randomUUID && crypto.randomUUID()) || `t${Date.now()}${Math.random()}`;
    localStorage.setItem('kuhpoker_token', tk);
  }
  return tk;
}
const myToken = getToken();
function rememberRoom(code) {
  myCode = code;
  localStorage.setItem('kuhpoker_code', code);
}
function forgetRoom() {
  myCode = null;
  localStorage.removeItem('kuhpoker_code');
}

// ---------- Referenz-Panels (Rangfolge links, Karten rechts) ----------
let panelFlush = false; // zuletzt bekannter Flush-Modus fuer das Rangfolge-Panel
function buildSidePanels(flush) {
  panelFlush = !!flush;
  const rankBody = $('rankBody');
  if (rankBody) {
    const codes = flush ? [10, 9, 8, 7, 6, 5, 4, 3, 2] : [8, 7, 6, 5, 4, 3, 2];
    rankBody.innerHTML =
      `<div class="rank-scale"><span>${t('strong')}</span><span>${t('weak')}</span></div>` +
      codes
        .map(
          (c, i) =>
            `<div class="rank-row"><span class="rank-no">${i + 1}</span><span class="rank-name">${escapeHtml(catName(lang, c, flush))}</span></div>`
        )
        .join('');
  }
  const cardBody = $('cardBody');
  if (cardBody) {
    const animals = Object.keys(ANIMALS)
      .map(Number)
      .sort((a, b) => b - a) // Pferd (1000) oben, Hahn (10) unten
      .map((r) => {
        const a = ANIMALS[r];
        return `<div class="cardref-row"><span class="cardref-emoji">${a.emoji}</span><span class="cardref-name">${escapeHtml(a[lang])}</span><span class="cardref-val">${a.value}</span></div>`;
      })
      .join('');
    const suits = SUITS.map(
      (s) => `<span class="suit-chip" style="color:${s.color}">${s.symbol} ${escapeHtml(s[lang])}</span>`
    ).join('');
    cardBody.innerHTML =
      animals + `<div class="cardref-suits"><div class="cardref-suits-title">${t('suitsTitle')}</div>${suits}</div>`;
  }
}
function togglePanel(id) {
  const el = $(id);
  if (el) el.classList.toggle('collapsed');
}

// ---------- Statische Übersetzung anwenden ----------
function applyStatic() {
  document.documentElement.lang = lang;
  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.getAttribute('data-i18n');
    if (I18N[lang][key] !== undefined) el.textContent = t(key);
  });
  $('nameInput').placeholder = t('namePlaceholder');
  $('codeInput').placeholder = t('codePlaceholder');
  $('rulesBody').innerHTML = t('rulesHtml', createOpts.flush);
  if ($('chatInput')) $('chatInput').placeholder = t('chatPlaceholder');
  if ($('chatSend')) $('chatSend').textContent = t('send');
  // Lang-Buttons markieren
  document.querySelectorAll('.lang-btn[data-lang]').forEach((b) => {
    b.classList.toggle('active', b.dataset.lang === lang);
  });
  $('gameLangBtn').textContent = lang.toUpperCase();
  buildSidePanels(lastState ? lastState.flush : panelFlush);
  if (typeof updateCashHint === 'function') updateCashHint();
  if (typeof renderProfile === 'function') renderProfile();
  if ($('leaderboardBox')?.open) loadLeaderboard();
  if (lastLobby) renderLobby(lastLobby);
  // Render-Caches verwerfen, damit Sitze/Log in der neuen Sprache neu gebaut werden.
  invalidateRenderCaches();
  if (lastState) render(lastState);
}

function setLang(l) {
  lang = l;
  localStorage.setItem('kuhpoker_lang', l);
  applyStatic();
}
document.querySelectorAll('.lang-btn[data-lang]').forEach((b) => {
  b.onclick = () => setLang(b.dataset.lang);
});
$('gameLangBtn').onclick = () => setLang(lang === 'de' ? 'en' : 'de');

// Referenz-Panels ein-/ausklappen.
$('ranksBtn').onclick = () => togglePanel('rankPanel');
$('cardsBtn').onclick = () => togglePanel('cardPanel');
document.querySelectorAll('.side-close').forEach((b) => {
  b.onclick = () => togglePanel(b.dataset.panel);
});

// ---------- Lobby-Optionen ----------
$('maxPlayersSeg').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  createOpts.maxPlayers = +b.dataset.val;
  segActivate('maxPlayersSeg', b);
});
$('stackSeg').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  createOpts.startingStack = +b.dataset.val;
  segActivate('stackSeg', b);
  if (typeof updateCashHint === 'function') updateCashHint();
});
$('flushSeg').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  createOpts.flush = b.dataset.val === 'on';
  segActivate('flushSeg', b);
  $('rulesBody').innerHTML = t('rulesHtml', createOpts.flush);
});
$('tourneySeg').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  createOpts.tournament = b.dataset.val === 'on';
  segActivate('tourneySeg', b);
  $('levelHandsRow').classList.toggle('hidden', !createOpts.tournament);
  // Turnier und Cash-Game schliessen sich aus.
  if (createOpts.tournament && createOpts.cash) {
    createOpts.cash = false;
    segActivate('cashSeg', $('cashSeg').querySelector('[data-val="off"]'));
    updateCashHint();
  }
});
const cashSeg = $('cashSeg');
if (cashSeg) {
  cashSeg.addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    createOpts.cash = b.dataset.val === 'on';
    segActivate('cashSeg', b);
    updateCashHint();
    if (createOpts.cash && createOpts.tournament) {
      createOpts.tournament = false;
      segActivate('tourneySeg', $('tourneySeg').querySelector('[data-val="off"]'));
      $('levelHandsRow').classList.add('hidden');
    }
  });
}
function updateCashHint() {
  const hint = $('cashHint');
  if (hint) hint.textContent = createOpts.cash ? t('cashHintOn', createOpts.startingStack) : t('cashHint');
}
$('levelHandsSeg').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  createOpts.levelHands = +b.dataset.val;
  segActivate('levelHandsSeg', b);
});
function segActivate(segId, btn) {
  $(segId).querySelectorAll('button').forEach((x) => x.classList.toggle('active', x === btn));
}

$('nameInput').value = localStorage.getItem('kuhpoker_name') || '';

$('createBtn').onclick = () => {
  const name = $('nameInput').value.trim();
  localStorage.setItem('kuhpoker_name', name);
  socket.emit('createRoom', { name, token: myToken, maxPlayers: createOpts.maxPlayers, flush: createOpts.flush, startingStack: createOpts.startingStack, tournament: createOpts.tournament, levelHands: createOpts.levelHands, cash: createOpts.cash }, (res) => {
    if (res?.error) return toast(res.error);
    rememberRoom(res.code);
  });
};
$('joinBtn').onclick = () => {
  const name = $('nameInput').value.trim();
  const code = $('codeInput').value.trim().toUpperCase();
  if (!code) return toast(t('enterCode'));
  localStorage.setItem('kuhpoker_name', name);
  socket.emit('joinRoom', { code, name, token: myToken }, (res) => {
    if (res?.error) return toast(res.error);
    rememberRoom(res.code);
  });
};
$('startGameBtn').onclick = () => socket.emit('startHand');
$('copyLinkBtn').onclick = () => {
  const link = `${location.origin}/?code=${myCode}`;
  navigator.clipboard?.writeText(link).then(() => toast(t('linkCopied')), () => toast(link));
};

// Verbindungsstatus: zeigt im Spiel an, wenn die Verbindung kurz weg ist, und
// blendet nach dem Reconnect eine kurze Bestaetigung ein. connLost ueberschreibt
// die normale Statusanzeige, damit der Spieler nicht glaubt, er sei rausgeflogen.
let connLost = false;
function updateConnBanner() {
  const el = $('connStatus');
  if (!el) return;
  if (connLost) {
    el.textContent = t('reconnecting');
    el.className = 'conn off';
  } else if (lastLobby) {
    renderConnStatus(lastLobby);
  }
}

socket.on('connect', () => {
  if (connLost) {
    connLost = false;
    toast(t('reconnected'));
    updateConnBanner();
  }
  const code = localStorage.getItem('kuhpoker_code');
  if (!code) return;
  socket.emit('resume', { code, token: myToken }, (res) => {
    if (res?.error) {
      forgetRoom();
      $('game').classList.add('hidden');
      $('lobby').classList.remove('hidden');
    }
  });
});

socket.on('disconnect', (reason) => {
  // "io client disconnect" = bewusstes Trennen (Verlassen) – kein Hinweis noetig.
  if (reason === 'io client disconnect') return;
  connLost = true;
  updateConnBanner();
});
socket.io.on('reconnect_attempt', () => {
  connLost = true;
  updateConnBanner();
});

const urlCode = new URLSearchParams(location.search).get('code');
if (urlCode) $('codeInput').value = urlCode.toUpperCase();

// ---------- Server-Events ----------
socket.on('lobby', (lob) => {
  lastLobby = lob;
  rememberRoom(lob.code);
  renderLobby(lob);
});
socket.on('state', (s) => {
  captureFrame(s); // Live-Zustand fuer die Replay-Aufzeichnung puffern
  lastState = s;
  // Im Replay die Anzeige nicht stoeren – beim Schliessen wird live gerendert.
  if (!replayMode) render(s);
});
socket.on('errorMsg', (msg) => toast(msg));

// ---------- Profil (Wallet/Statistik) ----------
let myProfile = null;
socket.on('profile', (p) => {
  myProfile = p;
  renderProfile();
});
function renderProfile() {
  const bar = $('profileBar');
  if (!bar) return;
  if (!myProfile) {
    bar.classList.add('hidden');
    return;
  }
  bar.classList.remove('hidden');
  $('pbWallet').textContent = (myProfile.wallet ?? 0).toLocaleString();
  $('pbMatches').textContent = myProfile.matchesWon ?? 0;
  $('pbWallet').parentElement.title = t('walletTitle');
  $('pbMatches').parentElement.title = t('matchesTitle');
  renderStats();
  renderTableStat();
}

// Kompakte Statistik-Anzeige am Tisch (Topbar): Gewinnrate, sobald Hände gespielt.
function renderTableStat() {
  const el = $('tableStat');
  if (!el || !myProfile) return;
  const played = myProfile.handsPlayed ?? 0;
  if (played <= 0) {
    el.classList.add('hidden');
    return;
  }
  const rate = Math.round(((myProfile.handsWon ?? 0) / played) * 100);
  el.textContent = `📈 ${rate}% · ${played}`;
  el.title = `${t('statWinRate')} ${rate}% · ${t('statHandsPlayed')} ${played}`;
  el.classList.remove('hidden');
}

// Detail-Statistik im aufklappbaren Panel (Lobby).
function renderStats() {
  const box = $('statsBox');
  const body = $('statsBody');
  if (!box || !body || !myProfile) return;
  const played = myProfile.handsPlayed ?? 0;
  const won = myProfile.handsWon ?? 0;
  const rate = played > 0 ? Math.round((won / played) * 100) : 0;
  const rows = [
    ['🃏', t('statHandsPlayed'), played.toLocaleString()],
    ['🏅', t('statHandsWon'), won.toLocaleString()],
    ['📈', t('statWinRate'), `${rate}%`],
    ['💰', t('statBiggestPot'), `${(myProfile.biggestPot ?? 0).toLocaleString()} 🪙`],
    ['🏆', t('statMatchesWon'), (myProfile.matchesWon ?? 0).toLocaleString()],
  ];
  body.innerHTML = rows
    .map(
      ([icon, label, val]) =>
        `<div class="stat-row"><span class="stat-label"><span class="stat-ico">${icon}</span>${escapeHtml(label)}</span><span class="stat-val">${escapeHtml(val)}</span></div>`
    )
    .join('');
  box.classList.remove('hidden');
}

// ---------- Bestenliste ----------
async function loadLeaderboard() {
  const body = $('leaderboardBody');
  if (!body) return;
  try {
    const res = await fetch('/api/leaderboard');
    const data = await res.json();
    const top = ((data && data.top) || []).filter((r) => (r.matchesWon || 0) > 0);
    if (!top.length) {
      body.innerHTML = `<p class="lb-empty">${escapeHtml(t('lbEmpty'))}</p>`;
      return;
    }
    body.innerHTML = top
      .map((r, i) => {
        const medal = i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : `${i + 1}.`;
        return `<div class="lb-row"><span class="lb-rank">${medal}</span><span class="lb-name">${escapeHtml(r.name || 'Spieler')}</span><span class="lb-matches">${escapeHtml(t('lbMatches', r.matchesWon || 0))}</span></div>`;
      })
      .join('');
  } catch {
    body.innerHTML = `<p class="lb-empty">${escapeHtml(t('lbEmpty'))}</p>`;
  }
}
const lbBox = $('leaderboardBox');
if (lbBox) lbBox.addEventListener('toggle', () => { if (lbBox.open) loadLeaderboard(); });

// ---------- Tisch-Chat ----------
let chatMsgs = [];
socket.on('chatHistory', (msgs) => {
  chatMsgs = Array.isArray(msgs) ? msgs.slice() : [];
  renderChat();
});
socket.on('chat', (msg) => {
  chatMsgs.push(msg);
  if (chatMsgs.length > 80) chatMsgs.shift();
  renderChat();
});
function renderChat() {
  const box = $('chatMessages');
  if (!box) return;
  box.innerHTML = chatMsgs
    .map(
      (m) =>
        `<div class="chat-msg"><span class="chat-name">${escapeHtml(m.name)}</span><span class="chat-text">${escapeHtml(m.text)}</span></div>`
    )
    .join('');
  box.scrollTop = box.scrollHeight;
}
const chatForm = $('chatForm');
if (chatForm) {
  chatForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const inp = $('chatInput');
    const text = inp.value.trim();
    if (!text) return;
    socket.emit('chat', { text });
    inp.value = '';
  });
}

function renderLobby(lob) {
  if (lob.started) {
    $('lobby').classList.add('hidden');
    $('game').classList.remove('hidden');
    $('topCode').textContent = t('table', lob.code);
    renderConnStatus(lob);
    return;
  }
  // In Lobby, im Warte-Bereich
  $('game').classList.add('hidden');
  $('lobby').classList.remove('hidden');
  $('waiting').classList.remove('hidden');
  $('roomCode').textContent = lob.code;

  const list = $('lobbyPlayers');
  list.innerHTML = lob.players
    .map(
      (p) =>
        `<div class="lp ${p.connected ? '' : 'off'}">${p.isHost ? '👑 ' : ''}${escapeHtml(p.name)}${p.connected ? '' : ' …'}</div>`
    )
    .join('');

  const startBtn = $('startGameBtn');
  if (lob.youAreHost) {
    startBtn.classList.remove('hidden');
    startBtn.disabled = !lob.canStart;
    $('waitHint').textContent = lob.canStart ? t('readyHost') : t('needTwo');
  } else {
    startBtn.classList.add('hidden');
    $('waitHint').textContent = t('waitHost');
  }
}

function renderBlindInfo(s) {
  const el = $('blindInfo');
  if (!el) return;
  const bl = s.blinds;
  // Cash-Game: Buy-in-Hinweis. Sonst nur im Turniermodus (Stufe/Anstieg).
  if (s.cash) {
    el.textContent = `${t('cashTag')} · Buy-in ${(s.buyIn || 0).toLocaleString()} 🪙`;
    el.classList.remove('hidden');
    return;
  }
  if (!bl || !bl.tournament) {
    el.classList.add('hidden');
    return;
  }
  let txt = t('blindInfo', bl.sb, bl.bb, bl.level);
  if (typeof bl.nextLevelIn === 'number' && bl.nextLevelIn >= 0) {
    txt += t('nextBlindIn', bl.nextLevelIn);
  }
  el.textContent = txt;
  el.classList.remove('hidden');
}

function renderConnStatus(lob) {
  const el = $('connStatus');
  // Eigener Verbindungsabriss hat Vorrang vor dem Status der Mitspieler.
  if (connLost) {
    el.textContent = t('reconnecting');
    el.className = 'conn off';
    return;
  }
  const off = lob.players.filter((p) => !p.connected);
  if (off.length > 0) {
    el.textContent = t('someoneOff');
    el.className = 'conn off';
  } else if (lob.players.length < 2) {
    el.textContent = t('waitingPlayers');
    el.className = 'conn waiting';
  } else {
    el.textContent = t('connected');
    el.className = 'conn on';
  }
}

// ---------- Sound ----------
let muted = localStorage.getItem('kuhpoker_muted') === '1';
let audioCtx = null;
function ac() {
  if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  return audioCtx;
}
function beep(freq, dur = 0.12, type = 'sine', gain = 0.08) {
  if (muted) return;
  try {
    const ctx = ac();
    const o = ctx.createOscillator();
    const g = ctx.createGain();
    o.type = type;
    o.frequency.value = freq;
    g.gain.value = gain;
    o.connect(g);
    g.connect(ctx.destination);
    const tt = ctx.currentTime;
    g.gain.setValueAtTime(gain, tt);
    g.gain.exponentialRampToValueAtTime(0.0001, tt + dur);
    o.start(tt);
    o.stop(tt + dur);
  } catch (_) {}
}
const sfx = {
  deal: () => beep(440, 0.08, 'triangle', 0.05),
  turn: () => beep(660, 0.1, 'sine', 0.09),
  chip: () => beep(300, 0.07, 'square', 0.05),
  win: () => { beep(523, 0.12); setTimeout(() => beep(659, 0.12), 110); setTimeout(() => beep(784, 0.2), 220); },
  lose: () => { beep(330, 0.18, 'sine', 0.07); setTimeout(() => beep(247, 0.25, 'sine', 0.07), 140); },
};
$('muteBtn').textContent = muted ? '🔇' : '🔊';
$('muteBtn').onclick = () => {
  muted = !muted;
  localStorage.setItem('kuhpoker_muted', muted ? '1' : '0');
  $('muteBtn').textContent = muted ? '🔇' : '🔊';
  if (!muted) sfx.turn();
};

// ---------- Render-Status ----------
let prevCommunityCount = 0;
let prevHandNo = 0;
let prevStage = null;
let prevYourTurn = false;
let prevPot = 0;
let newCardKeys = new Set();
let revealedSeen = new Set(); // bereits animierte Gegnerkarten (Schluessel "seat:rank-copy")

// Render-Caches: vermeiden, bei jedem State-Update das gesamte DOM neu aufzubauen.
// Sitz-Knoten werden ueber ihre Inhalts-Signatur wiederverwendet; nur wirklich
// veraenderte Sitze werden neu gebaut. Log/Community wachsen inkrementell.
let seatNodeCache = new Map(); // playerId -> { el, sig }
let renderedLogLen = 0; // wie viele Log-Eintraege bereits im DOM stehen

// Render-Caches verwerfen (Sprache gewechselt, Tisch verlassen) – erzwingt einen
// vollstaendigen Neuaufbau bei der naechsten Render-Runde.
function invalidateRenderCaches() {
  seatNodeCache.clear();
  renderedLogLen = 0;
  const seats = $('seats');
  if (seats) seats.innerHTML = '';
  const logEl = $('log');
  if (logEl) logEl.innerHTML = '';
  const com = $('community');
  if (com) com.innerHTML = '';
}

// ---------- Replay der letzten Hand ----------
// Der Client puffert die Zustaende der laufenden Hand. Endet die Hand, kann der
// Spieler sie Frame fuer Frame abspielen (kein Serverumbau noetig).
let currentHandFrames = []; // Zustaende der aktuell laufenden/letzten Hand
let lastFrameSig = ''; // Signatur des letzten gepufferten Frames (dedupe)
let replayMode = false; // laeuft gerade ein Replay?
let replayFrames = []; // eingefrorene Kopie fuers Abspielen
let replayIdx = 0;
let replayPlaying = false;
let replayTimer = null;
const REPLAY_STEP_MS = 1100;

// Signatur eines Spielzustands – aendert sich genau dann, wenn sich etwas
// Sichtbares getan hat (Strasse, Pot, Einsaetze, Stacks, Fold, Reveal).
function frameSig(s) {
  return [
    s.handNo, s.stage, s.pot, (s.community || []).length,
    (s.players || []).map((p) => `${p.bet}|${p.stack}|${p.folded ? 1 : 0}`).join(','),
    s.result ? (s.result.reveal || []).length : 0,
  ].join('#');
}

// Frame eines Live-Zustands puffern (nur aus dem 'state'-Handler aufgerufen,
// nie beim Rendern historischer Replay-Frames).
let captureHandNo = -1;
function captureFrame(s) {
  if (s.handNo !== captureHandNo) {
    // Neue Hand -> Aufzeichnung frisch beginnen.
    captureHandNo = s.handNo;
    currentHandFrames = [];
    lastFrameSig = '';
  }
  if (s.stage === 'idle') return; // Wartephase vor der ersten Hand nicht puffern
  const sig = frameSig(s);
  if (sig === lastFrameSig) return;
  lastFrameSig = sig;
  currentHandFrames.push(JSON.parse(JSON.stringify(s)));
  if (currentHandFrames.length > 150) currentHandFrames.shift();
}

function replayAvailable(s) {
  return !replayMode && s && s.stage === 'handover' && currentHandFrames.length >= 2;
}

function startReplay() {
  if (currentHandFrames.length < 2) return;
  replayFrames = currentHandFrames.slice();
  replayIdx = 0;
  replayMode = true;
  replayPlaying = true;
  $('replayBar').classList.remove('hidden');
  renderReplayFrame();
  scheduleReplayTick();
}

function scheduleReplayTick() {
  clearTimeout(replayTimer);
  if (!replayPlaying) return;
  replayTimer = setTimeout(() => {
    if (replayIdx < replayFrames.length - 1) {
      replayIdx++;
      renderReplayFrame();
      scheduleReplayTick();
    } else {
      replayPlaying = false;
      updateReplayBar();
    }
  }, REPLAY_STEP_MS);
}

function renderReplayFrame() {
  // prev*-Tracking auf den Vorgaenger-Frame setzen, damit Karten-/Pot-Animationen
  // beim Vorspulen korrekt (nur fuer wirklich neue Karten) ausgeloest werden.
  const prev = replayFrames[Math.max(0, replayIdx - 1)];
  prevCommunityCount = replayIdx === 0 ? 0 : (prev.community || []).length;
  prevPot = replayIdx === 0 ? 0 : (prev.pot || 0);
  render(replayFrames[replayIdx]);
  updateReplayBar();
}

function updateReplayBar() {
  $('replayPos').textContent = `${replayIdx + 1}/${replayFrames.length}`;
  $('replayPlay').textContent = replayPlaying ? '⏸' : '▶';
  $('replayTag').textContent = t('replayTitle');
}

function stepReplay(delta) {
  replayPlaying = false;
  clearTimeout(replayTimer);
  replayIdx = Math.max(0, Math.min(replayFrames.length - 1, replayIdx + delta));
  renderReplayFrame();
}

function toggleReplayPlay() {
  if (replayPlaying) {
    replayPlaying = false;
    clearTimeout(replayTimer);
    updateReplayBar();
  } else {
    if (replayIdx >= replayFrames.length - 1) replayIdx = 0;
    replayPlaying = true;
    renderReplayFrame();
    scheduleReplayTick();
  }
}

function closeReplay() {
  replayMode = false;
  replayPlaying = false;
  clearTimeout(replayTimer);
  $('replayBar').classList.add('hidden');
  // Zurueck in den Live-Zustand.
  prevCommunityCount = 0;
  prevPot = 0;
  if (lastState) render(lastState);
}

// Sitz-Positionen (Prozent) je Anzahl Gegner. "Ich" bin immer unten Mitte.
const OPP_SLOTS = {
  0: [],
  1: [[50, 8]],
  2: [[15, 22], [85, 22]],
  3: [[12, 40], [50, 6], [88, 40]],
  4: [[8, 34], [30, 8], [70, 8], [92, 34]],
  5: [[7, 36], [25, 8], [50, 4], [75, 8], [93, 36]],
};
// Schmaler Bildschirm: Eck-Sitze nach innen ziehen und obere Reihe etwas tiefer,
// damit nichts ueber den Tischrand hinausragt (sonst werden Sitze abgeschnitten).
const OPP_SLOTS_MOBILE = {
  0: [],
  1: [[50, 9]],
  2: [[18, 22], [82, 22]],
  3: [[16, 38], [50, 9], [84, 38]],
  4: [[14, 32], [33, 10], [67, 10], [86, 32]],
  5: [[13, 34], [30, 10], [50, 7], [70, 10], [87, 34]],
};

function cardEl(card) {
  const el = document.createElement('div');
  if (!card) {
    el.className = 'card back';
    el.innerHTML = '<div class="back-pattern">🐄</div>';
    return el;
  }
  const a = ANIMALS[card.rank];
  const suit = SUITS[card.suit ?? card.copy ?? 0];
  el.className = 'card';
  el.style.setProperty('--suit', suit.color);
  el.innerHTML = `
    <div class="card-corner top"><span class="cval">${a.value}</span><span class="suit">${suit.symbol}</span></div>
    <div class="card-emoji">${a.emoji}</div>
    <div class="card-name">${animalName(lang, card.rank)}</div>
    <div class="card-corner bot"><span class="cval">${a.value}</span><span class="suit">${suit.symbol}</span></div>`;
  return el;
}

function miniCardHtml(c) {
  if (!c) return '';
  const a = ANIMALS[c.rank];
  const suit = SUITS[c.suit ?? c.copy ?? 0];
  return `<span class="mini-card" style="--suit:${suit.color}"><span class="mini-emoji">${a.emoji}</span><span class="mini-val">${a.value}</span><span class="mini-suit">${suit.symbol}</span></span>`;
}

function render(s) {
  const me = s.players[s.meIdx];
  if (s.flush !== panelFlush) buildSidePanels(s.flush);
  const handChanged = s.handNo !== prevHandNo;
  const communityGrew = s.community.length > prevCommunityCount;
  newCardKeys = new Set();
  if (communityGrew) {
    for (let i = prevCommunityCount; i < s.community.length; i++) {
      const c = s.community[i];
      newCardKeys.add(`${c.rank}-${c.copy}`);
    }
  }

  // Neu aufgedeckte Gegnerkarten bestimmen (Showdown ODER freiwilliges Zeigen) —
  // diese bekommen eine langsamere Flip-Animation, gestaffelt nacheinander.
  if (handChanged) revealedSeen = new Set();
  const revealAnim = new Map();
  if (s.stage === 'showdown' || s.stage === 'handover') {
    let ri = 0;
    for (const p of s.players) {
      if (p.seat === s.meIdx || p.folded) continue;
      for (const c of p.hole || []) {
        if (!c) continue;
        const key = `${p.seat}:${c.rank}-${c.copy}`;
        if (!revealedSeen.has(key)) {
          revealAnim.set(key, ri++);
          revealedSeen.add(key);
        }
      }
    }
  }

  renderSeats(s, handChanged, revealAnim);
  renderCommunity(s);

  $('pot').textContent = t('pot', s.pot);
  $('stageLabel').textContent = t('stages')[s.stage] || s.stage;
  renderBlindInfo(s);

  renderResult(s, me);
  renderControls(s, me);
  renderLog(s.log);

  if (lastLobby) renderConnStatus(lastLobby);

  if (handChanged && s.handNo > 0) sfx.deal();
  if (communityGrew) sfx.deal();
  if (s.pot > prevPot && !handChanged && s.stage !== 'handover') sfx.chip();
  if (s.yourTurn && !prevYourTurn) sfx.turn();
  if (s.stage === 'handover' && prevStage !== 'handover' && s.result) {
    const iWon = s.result.winners.includes(s.meIdx);
    if (iWon) sfx.win();
    else sfx.lose();
    // Pot fliegt zu den Gewinnern (nicht beim Replay-Spulen).
    if (!replayMode) flyPotToWinners(s);
  }

  prevHandNo = s.handNo;
  prevCommunityCount = s.community.length;
  prevStage = s.stage;
  prevYourTurn = s.yourTurn;
  prevPot = s.pot;
}

// Pot-zum-Gewinner-Animation: beim Showdown fliegen Chips vom zentralen Pot
// zu jedem Gewinner-Sitz (compositor-only: transform/opacity).
function flyPotToWinners(s) {
  const winners = s.result?.winners;
  if (!winners || !winners.length) return;
  // Bewegungsempfindliche Nutzer: keine fliegenden Chips.
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const potEl = $('pot');
  if (!potEl) return;
  const pr = potEl.getBoundingClientRect();
  const px = pr.left + pr.width / 2;
  const py = pr.top + pr.height / 2;
  for (const seatIdx of winners) {
    const pid = s.players[seatIdx]?.id;
    const seatEl = pid && seatNodeCache.get(pid)?.el;
    if (!seatEl) continue;
    const sr = seatEl.getBoundingClientRect();
    const sx = sr.left + sr.width / 2;
    const sy = sr.top + sr.height / 2;
    const count = 6;
    for (let k = 0; k < count; k++) {
      const chip = document.createElement('div');
      chip.className = 'fly-chip';
      chip.textContent = '🪙';
      chip.style.left = `${px}px`;
      chip.style.top = `${py}px`;
      chip.style.transitionDelay = `${k * 0.05}s`;
      document.body.appendChild(chip);
      const jx = (Math.random() - 0.5) * 26;
      const jy = (Math.random() - 0.5) * 26;
      // Zwei rAF, damit der Startzustand sicher gerendert ist, bevor die
      // Transition zum Zielsitz startet.
      requestAnimationFrame(() =>
        requestAnimationFrame(() => {
          chip.style.transform = `translate(${sx - px + jx}px, ${sy - py + jy}px) scale(0.7)`;
          chip.style.opacity = '0';
        })
      );
      setTimeout(() => chip.remove(), 1100 + k * 50);
    }
  }
}

// Signatur eines Sitzes: alles, was buildSeat sichtbar macht. Bleibt sie gleich,
// kann der vorhandene DOM-Knoten wiederverwendet werden (kein Neuaufbau).
function seatSig(s, p, isMe, animate, revealAnim) {
  const holeKey = (p.hole || []).map((c) => (c ? `${c.rank}-${c.copy}` : 'x')).join(',');
  const rev = s.result?.reveal?.find((r) => r.i === p.seat);
  const revKey = rev?.eval
    ? `${rev.eval.score?.[0]}:${(rev.eval.cards || []).map((c) => `${c.rank}-${c.copy}`).join('.')}:${rev.folded ? 1 : 0}`
    : '';
  const eq = s.runout && s.equities && !p.folded ? s.equities.find((e) => e.i === p.seat)?.pct ?? '' : '';
  const myHandKey = isMe && s.myHand && s.myHand.cat ? `${s.myHand.cat}` : '';
  // Animations-Trigger erzwingen einen Neuaufbau, damit die Animation auch laeuft.
  let animKey = animate ? 'A' : '';
  if (revealAnim) {
    for (const c of p.hole || []) {
      if (c && revealAnim.has(`${p.seat}:${c.rank}-${c.copy}`)) { animKey += 'R'; break; }
    }
  }
  // Nur das Showdown/Handover-Label haengt von der Strasse ab – als Boolean
  // kodieren, damit Flop->Turn->River nicht unnoetig alle Sitze neu baut.
  const showLabel = s.stage === 'showdown' || s.stage === 'handover' ? 1 : 0;
  const la = p.lastAction ? `${p.lastAction.type}:${p.lastAction.to || ''}:${p.lastAction.allIn ? 1 : 0}` : '';
  return [
    isMe ? 1 : 0, p.out ? 1 : 0, p.folded ? 1 : 0, p.id === s.toActId ? 1 : 0,
    p.isButton ? 1 : 0, p.isSB ? 1 : 0, p.isBB ? 1 : 0,
    p.name, p.stack, p.bet, p.allIn ? 1 : 0,
    holeKey, revKey, eq, myHandKey, showLabel, s.flush ? 1 : 0, lang, la, animKey,
  ].join('#');
}

function renderSeats(s, animate, revealAnim) {
  const container = $('seats');
  const n = s.players.length;
  const meIdx = s.meIdx;

  // Reihenfolge der Gegner: ab dem Sitz nach mir, im Uhrzeigersinn.
  const opps = [];
  for (let k = 1; k < n; k++) opps.push(s.players[(meIdx + k) % n]);
  // Auf schmalen Bildschirmen (Handy, Tablet, schmales Fenster) engere
  // Sitz-Positionen verwenden, damit nichts ueber den Rand hinausragt.
  const slotTable = window.innerWidth <= 820 ? OPP_SLOTS_MOBILE : OPP_SLOTS;
  const slots = slotTable[opps.length] || slotTable[5];

  const seen = new Set();
  // Baut den Sitz nur neu, wenn sich seine Signatur geaendert hat; Position wird
  // immer gesetzt (Slots koennen sich verschieben, wenn jemand geht/kommt).
  const place = (p, isMe, x, y) => {
    seen.add(p.id);
    const sig = seatSig(s, p, isMe, animate, revealAnim);
    let entry = seatNodeCache.get(p.id);
    if (!entry || entry.sig !== sig) {
      const el = buildSeat(s, p, isMe, animate, revealAnim);
      if (entry && entry.el.parentNode) entry.el.replaceWith(el);
      else container.appendChild(el);
      entry = { el, sig };
      seatNodeCache.set(p.id, entry);
    } else if (!entry.el.parentNode) {
      container.appendChild(entry.el);
    }
    const el = entry.el;
    if (isMe) { el.style.left = '50%'; el.style.bottom = '2%'; el.style.top = ''; }
    else { el.style.left = `${x}%`; el.style.top = `${y}%`; el.style.bottom = ''; }
  };

  opps.forEach((p, idx) => place(p, false, slots[idx][0], slots[idx][1]));
  place(s.players[meIdx], true);

  // Verwaiste Sitze (Spieler weg) entfernen.
  for (const [id, entry] of seatNodeCache) {
    if (!seen.has(id)) {
      if (entry.el.parentNode) entry.el.remove();
      seatNodeCache.delete(id);
    }
  }
}

// Kurztext + Stilklasse fuer die "letzte Aktion"-Blase am Sitz. Poker-Begriffe
// sind in DE/EN identisch (wie schon bei den Aktions-Buttons).
function actionBubble(la) {
  if (!la) return null;
  if (la.allIn) return { text: t('allInTag'), cls: 'allin' };
  switch (la.type) {
    case 'fold': return { text: t('fold'), cls: 'fold' };
    case 'check': return { text: t('check'), cls: 'check' };
    case 'call': return { text: 'Call', cls: 'call' };
    case 'bet': return { text: `Bet ${la.to}`, cls: 'bet' };
    case 'raise': return { text: `${t('raise')} ${la.to}`, cls: 'raise' };
    default: return null;
  }
}

function buildSeat(s, p, isMe, animate, revealAnim) {
  const seat = document.createElement('div');
  seat.className = 'seat';
  if (isMe) { seat.classList.add('me'); seat.classList.add('seat-bottom'); }
  if (p.out) seat.classList.add('out');
  else if (p.folded) seat.classList.add('folded');
  if (p.id === s.toActId) seat.classList.add('active-turn');

  // "Letzte Aktion"-Blase (Check/Call/Raise …) – erscheint mit Pop-Animation.
  const ab = actionBubble(p.lastAction);
  if (ab) {
    const bubble = document.createElement('div');
    bubble.className = `last-act last-act-${ab.cls}`;
    bubble.textContent = ab.text;
    seat.appendChild(bubble);
  }

  // Karten
  const hole = document.createElement('div');
  hole.className = 'hole';
  const used = s.result?.reveal?.find((r) => r.i === p.seat)?.eval?.cards || [];
  const usedSet = new Set(used.map((c) => `${c.rank}-${c.copy}`));
  const cards = p.hole && p.hole.length ? p.hole : [null, null];
  cards.forEach((c, i) => {
    const el = cardEl(c);
    if (c && usedSet.has(`${c.rank}-${c.copy}`)) el.classList.add('used');
    const revKey = c ? `${p.seat}:${c.rank}-${c.copy}` : null;
    if (revKey && revealAnim && revealAnim.has(revKey)) {
      // Langsameres Aufdecken (Flip), gestaffelt.
      el.classList.add('revealing');
      el.style.animationDelay = `${revealAnim.get(revKey) * 0.18}s`;
    } else if (animate) {
      el.classList.add('dealing');
      el.style.animationDelay = `${i * 0.1}s`;
    }
    hole.appendChild(el);
  });

  // Info
  const info = document.createElement('div');
  info.className = 'seat-info';
  const badges = [];
  if (p.isButton) badges.push('<span class="badge button-badge">D</span>');
  if (p.isSB) badges.push('<span class="badge blind-badge">SB</span>');
  if (p.isBB) badges.push('<span class="badge blind-badge">BB</span>');
  info.innerHTML = `
    <span class="pname">${escapeHtml(p.name)}${isMe ? ` (${t('you')})` : ''}</span>
    ${badges.join('')}
    <span class="stack">${p.out ? t('outTag') : p.stack + ' 🪙'}</span>`;

  // Bet-Chip
  const bet = document.createElement('div');
  bet.className = 'bet-chip' + (p.bet > 0 ? '' : ' hidden');
  bet.textContent = p.allIn && p.bet > 0 ? `${p.bet} · ${t('allInTag')}` : `${p.bet}`;

  // Equity-Badge waehrend eines All-In-Run-outs (Gewinnwahrscheinlichkeit).
  let equity = null;
  if (s.runout && s.equities && !p.folded) {
    const eq = s.equities.find((e) => e.i === p.seat);
    if (eq) {
      equity = document.createElement('div');
      equity.className = 'equity';
      equity.textContent = `${eq.pct}%`;
    }
  }

  // Live-Handstaerke (nur fuer mich, waehrend des Setzens): Balken + Kategorie unter dem Namen.
  let strength = null;
  if (isMe && s.myHand && s.myHand.cat) {
    const maxCat = s.flush ? 10 : 8;
    const frac = Math.max(0.08, Math.min(1, (s.myHand.cat - 2) / (maxCat - 2)));
    const hue = Math.round(frac * 130); // rot (schwach) -> gruen (stark)
    strength = document.createElement('div');
    strength.className = 'strength';
    strength.innerHTML =
      `<div class="strength-bar"><div class="strength-fill" style="width:${Math.round(frac * 100)}%;background:hsl(${hue},72%,46%)"></div></div>` +
      `<span class="strength-cat">${escapeHtml(catName(lang, s.myHand.cat, s.flush))}</span>`;
  }

  // Hand-Label (Showdown)
  const label = document.createElement('div');
  label.className = 'hand-label hidden';
  const rev = s.result?.reveal?.find((r) => r.i === p.seat);
  if ((s.stage === 'showdown' || s.stage === 'handover') && rev?.eval && !p.folded) {
    label.textContent = catName(lang, rev.eval.score[0], s.flush);
    label.classList.remove('hidden');
  }

  if (isMe) {
    seat.appendChild(bet);
    seat.appendChild(hole);
    seat.appendChild(label);
    if (equity) seat.appendChild(equity);
    seat.appendChild(info);
    if (strength) seat.appendChild(strength);
  } else {
    seat.appendChild(hole);
    seat.appendChild(bet);
    seat.appendChild(label);
    if (equity) seat.appendChild(equity);
    seat.appendChild(info);
  }

  // Zug-Countdown: depletierender Balken am Sitz des Spielers am Zug. Dauer aus
  // turnMsLeft (nicht Teil der Sitz-Signatur, damit er waehrend des Zugs
  // ununterbrochen durchlaeuft und nicht bei jedem Broadcast neu startet).
  if (!replayMode && p.id === s.toActId && typeof s.turnMsLeft === 'number' && s.turnMsLeft > 0) {
    const timer = document.createElement('div');
    timer.className = 'turn-timer';
    const fill = document.createElement('div');
    fill.className = 'turn-timer-fill';
    fill.style.animationDuration = `${s.turnMsLeft}ms`;
    timer.appendChild(fill);
    seat.appendChild(timer);
  }
  return seat;
}

function renderCommunity(s) {
  const com = $('community');
  const cards = s.community || [];
  // Inkrementell: bereits ausgeteilte Karten bleiben stehen (kein Flackern, keine
  // erneute Animation). Nur neue Karten werden angehaengt.
  let dealt = com.querySelectorAll('.card:not(.placeholder)').length;
  if (dealt > cards.length) {
    // Weniger Karten als gerendert (neue Hand / Zurueckspulen) -> Neuaufbau.
    com.innerHTML = '';
    dealt = 0;
  }
  // Platzhalter entfernen, danach unten passend neu setzen.
  com.querySelectorAll('.card.placeholder').forEach((el) => el.remove());
  let added = 0;
  for (let i = dealt; i < cards.length; i++) {
    const c = cards[i];
    const el = cardEl(c);
    if (newCardKeys.has(`${c.rank}-${c.copy}`)) {
      el.classList.add('dealing');
      el.style.animationDelay = `${added * 0.12}s`;
    }
    com.appendChild(el);
    added++;
  }
  for (let i = cards.length; i < 5; i++) {
    const ph = document.createElement('div');
    ph.className = 'card placeholder';
    com.appendChild(ph);
  }
}

function renderResult(s, me) {
  const banner = $('resultBanner');
  const detail = $('resultDetail');
  if (s.stage === 'handover' && s.result) {
    banner.classList.remove('hidden', 'win', 'lose', 'split');
    const myWin = s.result.winnings?.find((w) => w.i === s.meIdx)?.amount || 0;
    const winners = s.result.winners || [];
    if (winners.length > 1) {
      // Gleichstand: eigene Split-Pot-Grafik (statt "Du gewinnst"), auch wenn ich
      // mitgewinne. Zeigt die Aufteilung mit allen Beteiligten.
      banner.classList.add('split');
      banner.innerHTML = splitBannerHtml(s, myWin);
    } else if (myWin > 0) {
      banner.textContent = t('youWin', myWin);
      banner.classList.add('win');
    } else {
      const w = winners[0];
      const name = s.players[w]?.name || '?';
      banner.textContent = t('playerWins', name, s.result.pot);
      banner.classList.add('lose');
    }
    renderResultDetail(s, detail);
  } else {
    banner.classList.add('hidden');
    if (detail) detail.classList.add('hidden');
  }
}

// Split-Pot-Grafik: Kopfzeile + Karten/Chips fuer jeden Beteiligten, eigener
// Anteil hervorgehoben. Wird bei Gleichstand statt der Gewinn-Banner gezeigt.
function splitBannerHtml(s, myWin) {
  const winners = s.result.winners || [];
  const n = winners.length;
  const shares = winners
    .map((i) => {
      const amt =
        s.result.winnings?.find((w) => w.i === i)?.amount ||
        Math.floor((s.result.pot || 0) / n);
      const name = s.players[i]?.name || '?';
      const meCls = i === s.meIdx ? ' me' : '';
      return `<span class="split-share${meCls}"><span class="split-name">${escapeHtml(name)}</span><span class="split-amt">+${amt} 🪙</span></span>`;
    })
    .join('<span class="split-link">🤝</span>');
  const mine = myWin > 0 ? `<div class="split-you">${escapeHtml(t('splitYourShare', myWin))}</div>` : '';
  return (
    `<div class="split-head">${escapeHtml(t('splitPotTitle'))} · ${(s.result.pot || 0)} 🪙</div>` +
    `<div class="split-shares">${shares}</div>` +
    mine
  );
}

function renderResultDetail(s, detail) {
  if (!detail) return;
  const parts = [];

  // (6) Gewinnhand fett anzeigen, wenn Karten gezeigt wurden (Showdown oder freiwilliges Zeigen)
  const reveal = s.result.reveal || [];
  const winnerReveals = reveal.filter(
    (r) => s.result.winners.includes(r.i) && r.eval && r.eval.cards && !r.folded
  );
  for (const r of winnerReveals) {
    const name = s.players[r.i]?.name || '?';
    const cat = catName(lang, r.eval.score?.[0] ?? r.eval.cat, s.flush);
    const cards = r.eval.cards.map(miniCardHtml).join('');
    parts.push(
      `<div class="win-hand"><div class="win-hand-head">${escapeHtml(name)} — <span class="win-hand-cat">${escapeHtml(cat)}</span></div><div class="win-hand-cards">${cards}</div></div>`
    );
  }

  // (5) Split-Pot-Aufschluesselung bei mehreren Pots
  const pots = s.result.pots || [];
  if (pots.length > 1) {
    const rows = pots
      .map((p, idx) => {
        const label = idx === 0 ? t('mainPot') : t('sidePot', idx);
        const names = (p.winners || [])
          .map((w) => s.players[w]?.name || '?')
          .join(', ');
        return `<div class="pot-row"><span class="pot-name">${escapeHtml(label)}</span><span class="pot-amt">${p.amount} 🪙</span><span class="pot-win">${escapeHtml(names)}</span></div>`;
      })
      .join('');
    parts.push(`<div class="pot-breakdown"><div class="pot-bd-title">${t('potWinners')}</div>${rows}</div>`);
  }

  if (parts.length) {
    detail.innerHTML = parts.join('');
    detail.classList.remove('hidden');
  } else {
    detail.classList.add('hidden');
  }
}

function renderControls(s, me) {
  const turnInd = $('turnIndicator');
  const actionButtons = $('actionButtons');
  const raisePanel = $('raisePanel');
  const nextBtn = $('nextHandBtn');
  const matchOver = $('matchOver');
  const showBtn = $('showCardsBtn');
  const replayBtn = $('replayBtn');

  // Im Replay alle Live-Bedienelemente ausblenden (kein versehentliches Handeln).
  if (replayMode) {
    actionButtons.classList.add('hidden');
    raisePanel.classList.add('hidden');
    nextBtn.classList.add('hidden');
    showBtn.classList.add('hidden');
    replayBtn.classList.add('hidden');
    $('rebuyBtn').classList.add('hidden');
    matchOver.classList.add('hidden');
    turnInd.textContent = '';
    return;
  }

  // Replay-Knopf nach Rundenende anbieten, sobald genug Frames gepuffert sind.
  const showReplay = replayAvailable(s);
  replayBtn.classList.toggle('hidden', !showReplay);
  if (showReplay) replayBtn.textContent = t('replay');

  // "Karten zeigen" nur nach einem Fold-Sieg fuer den Gewinner, der noch nicht gezeigt hat.
  const canShow =
    !s.matchOver &&
    s.stage === 'handover' &&
    s.result?.reason === 'fold' &&
    s.result.winners.includes(s.meIdx) &&
    !me.folded &&
    !(s.shown || []).includes(s.meIdx);
  showBtn.classList.toggle('hidden', !canShow);
  if (canShow) showBtn.textContent = t('showCards');

  // Cash-Game: Rebuy zwischen den Händen, wenn der Stack unter einen Buy-in fällt.
  const rebuyBtn = $('rebuyBtn');
  const canRebuy =
    s.cash &&
    (s.stage === 'idle' || s.stage === 'handover') &&
    (s.myStack || 0) < (s.buyIn || 0);
  rebuyBtn.classList.toggle('hidden', !canRebuy);
  if (canRebuy) rebuyBtn.textContent = t('rebuyBtn');

  if (s.matchOver) {
    matchOver.classList.remove('hidden');
    $('matchOverText').textContent = s.matchWinnerId === me.id ? t('matchWon') : t('matchLost');
    actionButtons.classList.add('hidden');
    raisePanel.classList.add('hidden');
    nextBtn.classList.add('hidden');
    turnInd.textContent = '';
    return;
  }
  matchOver.classList.add('hidden');

  if (s.stage === 'idle' || s.stage === 'handover') {
    nextBtn.classList.remove('hidden');
    nextBtn.innerHTML = withHotkey(s.stage === 'idle' ? t('firstHand') : t('nextHand'), '⏎');
    actionButtons.classList.add('hidden');
    raisePanel.classList.add('hidden');
    turnInd.textContent = '';
    raiseOpen = false;
    return;
  }
  nextBtn.classList.add('hidden');

  $('foldBtn').innerHTML = withHotkey(t('fold'), 'F');

  if (s.yourTurn && s.actions) {
    turnInd.textContent = t('yourTurn');
    turnInd.className = 'turn-indicator active';
    const a = s.actions;
    const ccBtn = $('checkCallBtn');
    if (a.canCheck) {
      ccBtn.innerHTML = withHotkey(t('check'), 'C');
      ccBtn.dataset.act = 'check';
    } else {
      ccBtn.innerHTML = withHotkey(t('call', a.toCall), 'C');
      ccBtn.dataset.act = 'call';
    }
    $('raiseBtn').classList.toggle('hidden', !a.canRaise);
    $('raiseBtn').innerHTML = withHotkey(a.canCheck ? t('bet') : t('raise'), 'R');

    if (raiseOpen && a.canRaise) {
      actionButtons.classList.add('hidden');
      raisePanel.classList.remove('hidden');
      setupRaise(a);
    } else {
      actionButtons.classList.remove('hidden');
      raisePanel.classList.add('hidden');
    }
  } else {
    const actor = s.players.find((p) => p.id === s.toActId);
    turnInd.textContent = actor ? t('waitingFor', actor.name) : '';
    turnInd.className = 'turn-indicator';
    actionButtons.classList.add('hidden');
    raisePanel.classList.add('hidden');
    raiseOpen = false;
  }
}

function setupRaise(a) {
  const slider = $('raiseSlider');
  const amount = $('raiseAmount');
  const span = Math.max(0, a.maxRaiseTo - a.minRaiseTo);
  const step = Math.max(1, Math.round(span / 10)); // Barometer in ~10 Stufen
  slider.min = a.minRaiseTo;
  slider.max = a.maxRaiseTo;
  slider.step = step;
  amount.min = a.minRaiseTo;
  amount.max = a.maxRaiseTo;
  amount.step = 1; // Eingabefeld erlaubt jeden Wert
  if (!amount.value || +amount.value < a.minRaiseTo || +amount.value > a.maxRaiseTo) {
    amount.value = a.minRaiseTo;
    slider.value = a.minRaiseTo;
  }
}

// Tippeingabe auf den gueltigen Bereich begrenzen.
function clampRaise(v) {
  const a = lastState?.actions;
  let n = Math.round(Number(v));
  if (!Number.isFinite(n)) n = a ? a.minRaiseTo : 0;
  if (a) n = Math.max(a.minRaiseTo, Math.min(a.maxRaiseTo, n));
  return n;
}

function renderLog(log) {
  const el = $('log');
  // Inkrementell anhaengen statt die ganze (wachsende) Liste neu zu bauen.
  // Schrumpft das Log (neue Hand / Zurueckspulen), komplett neu aufbauen.
  if (log.length < renderedLogLen) {
    el.innerHTML = '';
    renderedLogLen = 0;
  }
  for (let i = renderedLogLen; i < log.length; i++) {
    const ev = log[i];
    const fn = I18N[lang].log[ev.key];
    const div = document.createElement('div');
    div.textContent = fn ? fn(ev) : ev.key;
    el.appendChild(div);
  }
  if (log.length !== renderedLogLen) {
    renderedLogLen = log.length;
    el.scrollTop = el.scrollHeight;
  }
}

// ---------- Aktionen ----------
$('actionButtons').addEventListener('click', (e) => {
  const btn = e.target.closest('button');
  if (!btn) return;
  const act = btn.dataset.act;
  if (act === 'raise') {
    raiseOpen = true;
    render(lastState);
    return;
  }
  socket.emit('action', { type: act });
});
$('raiseConfirm').onclick = () => {
  socket.emit('action', { type: 'raise', amount: clampRaise($('raiseAmount').value) });
  raiseOpen = false;
};
$('raiseCancel').onclick = () => {
  raiseOpen = false;
  render(lastState);
};
$('raiseSlider').oninput = (e) => { $('raiseAmount').value = e.target.value; };
$('raiseAmount').oninput = (e) => { $('raiseSlider').value = e.target.value; };
// Beim Verlassen des Feldes auf den gueltigen Bereich begrenzen, Enter bestaetigt.
$('raiseAmount').onchange = () => {
  const v = clampRaise($('raiseAmount').value);
  $('raiseAmount').value = v;
  $('raiseSlider').value = v;
};
$('raiseAmount').onkeydown = (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    $('raiseConfirm').click();
  }
};
document.querySelectorAll('[data-quick]').forEach((b) => {
  b.onclick = () => {
    const a = lastState.actions;
    if (!a) return;
    let v = a.minRaiseTo;
    if (b.dataset.quick === '3bb') {
      const bb = (lastState.blinds && lastState.blinds.bb) || 0;
      v = clampRaise(3 * bb);
    }
    if (b.dataset.quick === 'pot') v = Math.min(a.maxRaiseTo, Math.max(a.minRaiseTo, lastState.pot));
    if (b.dataset.quick === 'max') v = a.maxRaiseTo;
    $('raiseAmount').value = v;
    $('raiseSlider').value = v;
  };
});
$('nextHandBtn').onclick = () => socket.emit('startHand');
$('showCardsBtn').onclick = () => socket.emit('showCards');
$('replayBtn').onclick = () => startReplay();
$('replayPrev').onclick = () => stepReplay(-1);
$('replayNext').onclick = () => stepReplay(1);
$('replayPlay').onclick = () => toggleReplayPlay();
$('replayClose').onclick = () => closeReplay();
$('rematchBtn').onclick = () => socket.emit('rematch');
$('rebuyBtn').onclick = () => {
  socket.emit('rebuy', {}, (res) => {
    if (res?.error) return toast(res.error);
    if (res?.amount) toast(t('rebuyDone', res.amount));
  });
};

// ---------- Tastatur-Steuerung ----------
// F = Fold, C = Check/Call, R = Raise oeffnen, Enter = bestaetigen/naechste Hand,
// Esc = Raise abbrechen. Inaktiv, solange ein Eingabefeld (z. B. Chat) fokussiert ist.
function isTyping() {
  const el = document.activeElement;
  if (!el) return false;
  const tag = el.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || el.isContentEditable;
}
document.addEventListener('keydown', (e) => {
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  if ($('game').classList.contains('hidden')) return;

  // Im Replay: Pfeiltasten spulen, Leertaste Play/Pause, Esc schliesst.
  if (replayMode) {
    if (isTyping()) return;
    if (e.key === 'ArrowLeft') { e.preventDefault(); stepReplay(-1); }
    else if (e.key === 'ArrowRight') { e.preventDefault(); stepReplay(1); }
    else if (e.key === ' ') { e.preventDefault(); toggleReplayPlay(); }
    else if (e.key === 'Escape') { e.preventDefault(); closeReplay(); }
    return;
  }

  const s = lastState;
  if (!s) return;

  // Raise-Panel offen: Enter bestaetigt, Esc bricht ab.
  if (raiseOpen) {
    if (e.key === 'Escape') {
      e.preventDefault();
      $('raiseCancel').click();
    } else if (e.key === 'Enter' && !isTyping()) {
      e.preventDefault();
      $('raiseConfirm').click();
    }
    return;
  }

  if (isTyping()) return;

  // Naechste Hand / erste Hand mit Enter starten.
  if (e.key === 'Enter') {
    if (!$('nextHandBtn').classList.contains('hidden')) {
      e.preventDefault();
      $('nextHandBtn').click();
    } else if (!$('rematchBtn').closest('#matchOver').classList.contains('hidden')) {
      e.preventDefault();
      $('rematchBtn').click();
    }
    return;
  }

  if (!s.yourTurn || !s.actions) return;
  const a = s.actions;
  const k = e.key.toLowerCase();
  if (k === 'f') {
    e.preventDefault();
    socket.emit('action', { type: 'fold' });
  } else if (k === 'c') {
    e.preventDefault();
    socket.emit('action', { type: a.canCheck ? 'check' : 'call' });
  } else if (k === 'r') {
    if (a.canRaise) {
      e.preventDefault();
      raiseOpen = true;
      render(lastState);
    }
  }
});

// Bildschirm-Drehung/Groessenaenderung: Sitze neu positionieren (mobile vs. breite
// Slot-Tabelle). Entprellt; nicht waehrend eines Replays (wuerde es schliessen).
let resizeTimer = null;
window.addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    if (lastState && !replayMode && !$('game').classList.contains('hidden')) render(lastState);
  }, 150);
});

// Tisch verlassen -> zurueck zur Lobby. Loescht den gemerkten Raum, damit kein
// automatisches Resume beim naechsten Laden passiert.
$('leaveBtn').onclick = () => {
  if (!confirm(t('leaveConfirm'))) return;
  socket.emit('leaveRoom');
  forgetRoom();
  // Laufendes Replay beenden und Aufzeichnung verwerfen.
  replayMode = false;
  replayPlaying = false;
  clearTimeout(replayTimer);
  $('replayBar').classList.add('hidden');
  currentHandFrames = [];
  captureHandNo = -1;
  lastState = null;
  lastLobby = null;
  chatMsgs = [];
  renderChat();
  invalidateRenderCaches();
  $('game').classList.add('hidden');
  $('waiting').classList.add('hidden');
  $('lobby').classList.remove('hidden');
};

// ---------- Toast ----------
let toastTimer = null;
function toast(msg) {
  const tt = $('toast');
  tt.textContent = msg;
  tt.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => tt.classList.add('hidden'), 2600);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// Initiale Übersetzung
applyStatic();

// Profil beim Start laden (Wallet/Statistik in der Lobby anzeigen).
fetch(`/api/profile?token=${encodeURIComponent(myToken)}`)
  .then((r) => r.json())
  .then((d) => {
    if (d && d.ok && d.profile) {
      myProfile = d.profile;
      renderProfile();
    }
  })
  .catch(() => {});

// Referenz-Panels auf breiten Bildschirmen direkt offen zeigen.
if (window.innerWidth >= 1200) {
  $('rankPanel').classList.remove('collapsed');
  $('cardPanel').classList.remove('collapsed');
}
