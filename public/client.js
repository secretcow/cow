/* global io */
const socket = io();

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
    flushMode: 'Flush-Modus',
    on: 'An',
    off: 'Aus',
    flushHint:
      'An: Farben zählen — ein Flush (5 gleiche Farben) schlägt sogar das Full House. Aus: Farben sind nur Deko, kein Flush.',
    createTable: 'Neuen Tisch erstellen',
    or: 'oder',
    codePlaceholder: 'CODE',
    join: 'Beitreten',
    shareCode: 'Tisch-Code zum Teilen:',
    copyLink: 'Einladungslink kopieren',
    startGame: 'Spiel starten',
    rulesSummary: 'Spielregeln',
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
    playerWins: (name, n) => `${name} gewinnt ${n} 🪙`,
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
    flushMode: 'Flush mode',
    on: 'On',
    off: 'Off',
    flushHint:
      'On: suits count — a flush (5 same colour) even beats a full house. Off: colours are decorative only, no flush.',
    createTable: 'Create new table',
    or: 'or',
    codePlaceholder: 'CODE',
    join: 'Join',
    shareCode: 'Table code to share:',
    copyLink: 'Copy invite link',
    startGame: 'Start game',
    rulesSummary: 'Rules',
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
    playerWins: (name, n) => `${name} wins ${n} 🪙`,
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
let myCode = null;
let lastState = null;
let lastLobby = null;
let raiseOpen = false;
let createOpts = { maxPlayers: 6, flush: false };

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
  if (lastLobby) renderLobby(lastLobby);
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

// ---------- Lobby-Optionen ----------
$('maxPlayersSeg').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  createOpts.maxPlayers = +b.dataset.val;
  segActivate('maxPlayersSeg', b);
});
$('flushSeg').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  createOpts.flush = b.dataset.val === 'on';
  segActivate('flushSeg', b);
  $('rulesBody').innerHTML = t('rulesHtml', createOpts.flush);
});
function segActivate(segId, btn) {
  $(segId).querySelectorAll('button').forEach((x) => x.classList.toggle('active', x === btn));
}

$('nameInput').value = localStorage.getItem('kuhpoker_name') || '';

$('createBtn').onclick = () => {
  const name = $('nameInput').value.trim();
  localStorage.setItem('kuhpoker_name', name);
  socket.emit('createRoom', { name, token: myToken, maxPlayers: createOpts.maxPlayers, flush: createOpts.flush }, (res) => {
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

socket.on('connect', () => {
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

const urlCode = new URLSearchParams(location.search).get('code');
if (urlCode) $('codeInput').value = urlCode.toUpperCase();

// ---------- Server-Events ----------
socket.on('lobby', (lob) => {
  lastLobby = lob;
  rememberRoom(lob.code);
  renderLobby(lob);
});
socket.on('state', (s) => {
  lastState = s;
  render(s);
});
socket.on('errorMsg', (msg) => toast(msg));

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

function renderConnStatus(lob) {
  const el = $('connStatus');
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

// Sitz-Positionen (Prozent) je Anzahl Gegner. "Ich" bin immer unten Mitte.
const OPP_SLOTS = {
  0: [],
  1: [[50, 8]],
  2: [[15, 22], [85, 22]],
  3: [[12, 40], [50, 6], [88, 40]],
  4: [[8, 34], [30, 8], [70, 8], [92, 34]],
  5: [[7, 36], [25, 8], [50, 4], [75, 8], [93, 36]],
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

function render(s) {
  const me = s.players[s.meIdx];
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

  renderResult(s, me);
  renderControls(s, me);
  renderMyHand(s);
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
  }

  prevHandNo = s.handNo;
  prevCommunityCount = s.community.length;
  prevStage = s.stage;
  prevYourTurn = s.yourTurn;
  prevPot = s.pot;
}

function renderSeats(s, animate, revealAnim) {
  const container = $('seats');
  container.innerHTML = '';
  const n = s.players.length;
  const meIdx = s.meIdx;

  // Reihenfolge der Gegner: ab dem Sitz nach mir, im Uhrzeigersinn.
  const opps = [];
  for (let k = 1; k < n; k++) opps.push(s.players[(meIdx + k) % n]);
  const slots = OPP_SLOTS[opps.length] || OPP_SLOTS[5];

  opps.forEach((p, idx) => {
    const [x, y] = slots[idx];
    const seat = buildSeat(s, p, false, animate, revealAnim);
    seat.style.left = `${x}%`;
    seat.style.top = `${y}%`;
    container.appendChild(seat);
  });

  // Ich unten Mitte
  const meSeat = buildSeat(s, s.players[meIdx], true, animate, revealAnim);
  meSeat.style.left = '50%';
  meSeat.style.bottom = '2%';
  meSeat.classList.add('seat-bottom');
  container.appendChild(meSeat);
}

function buildSeat(s, p, isMe, animate, revealAnim) {
  const seat = document.createElement('div');
  seat.className = 'seat';
  if (isMe) seat.classList.add('me');
  if (p.out) seat.classList.add('out');
  else if (p.folded) seat.classList.add('folded');
  if (p.id === s.toActId) seat.classList.add('active-turn');

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
  } else {
    seat.appendChild(hole);
    seat.appendChild(bet);
    seat.appendChild(label);
    if (equity) seat.appendChild(equity);
    seat.appendChild(info);
  }
  return seat;
}

function renderCommunity(s) {
  const com = $('community');
  com.innerHTML = '';
  let dealIdx = 0;
  for (const c of s.community) {
    const el = cardEl(c);
    if (newCardKeys.has(`${c.rank}-${c.copy}`)) {
      el.classList.add('dealing');
      el.style.animationDelay = `${dealIdx++ * 0.12}s`;
    }
    com.appendChild(el);
  }
  for (let i = s.community.length; i < 5; i++) {
    const ph = document.createElement('div');
    ph.className = 'card placeholder';
    com.appendChild(ph);
  }
}

function renderResult(s, me) {
  const banner = $('resultBanner');
  if (s.stage === 'handover' && s.result) {
    banner.classList.remove('hidden', 'win', 'lose');
    const myWin = s.result.winnings?.find((w) => w.i === s.meIdx)?.amount || 0;
    if (myWin > 0) {
      banner.textContent = t('youWin', myWin);
      banner.classList.add('win');
    } else if (s.result.winners.length > 1) {
      banner.textContent = t('splitPot', s.result.pot);
    } else {
      const w = s.result.winners[0];
      const name = s.players[w]?.name || '?';
      banner.textContent = t('playerWins', name, s.result.pot);
      banner.classList.add('lose');
    }
  } else {
    banner.classList.add('hidden');
  }
}

function renderControls(s, me) {
  const turnInd = $('turnIndicator');
  const actionButtons = $('actionButtons');
  const raisePanel = $('raisePanel');
  const nextBtn = $('nextHandBtn');
  const matchOver = $('matchOver');
  const showBtn = $('showCardsBtn');

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
    nextBtn.textContent = s.stage === 'idle' ? t('firstHand') : t('nextHand');
    actionButtons.classList.add('hidden');
    raisePanel.classList.add('hidden');
    turnInd.textContent = '';
    raiseOpen = false;
    return;
  }
  nextBtn.classList.add('hidden');

  $('foldBtn').textContent = t('fold');

  if (s.yourTurn && s.actions) {
    turnInd.textContent = t('yourTurn');
    turnInd.className = 'turn-indicator active';
    const a = s.actions;
    const ccBtn = $('checkCallBtn');
    if (a.canCheck) {
      ccBtn.textContent = t('check');
      ccBtn.dataset.act = 'check';
    } else {
      ccBtn.textContent = t('call', a.toCall);
      ccBtn.dataset.act = 'call';
    }
    $('raiseBtn').classList.toggle('hidden', !a.canRaise);
    $('raiseBtn').textContent = a.canCheck ? t('bet') : t('raise');

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

// Live-Handstaerke: zeigt, was ich aktuell als beste Hand halte (Paar, Zwei Paare …).
function renderMyHand(s) {
  const el = $('myHandLabel');
  if (!el) return;
  if (s.myHand && s.myHand.cat) {
    el.innerHTML = `<span class="mh-label">${escapeHtml(t('myHandTitle'))}</span> <span class="mh-cat">${escapeHtml(catName(lang, s.myHand.cat, s.flush))}</span>`;
    el.classList.remove('hidden');
  } else {
    el.classList.add('hidden');
  }
}

function renderLog(log) {
  const el = $('log');
  el.innerHTML = log
    .map((ev) => {
      const fn = I18N[lang].log[ev.key];
      const text = fn ? fn(ev) : ev.key;
      return `<div>${escapeHtml(text)}</div>`;
    })
    .join('');
  el.scrollTop = el.scrollHeight;
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
    if (b.dataset.quick === 'pot') v = Math.min(a.maxRaiseTo, Math.max(a.minRaiseTo, lastState.pot));
    if (b.dataset.quick === 'max') v = a.maxRaiseTo;
    $('raiseAmount').value = v;
    $('raiseSlider').value = v;
  };
});
$('nextHandBtn').onclick = () => socket.emit('startHand');
$('showCardsBtn').onclick = () => socket.emit('showCards');
$('rematchBtn').onclick = () => socket.emit('rematch');

// Tisch verlassen -> zurueck zur Lobby. Loescht den gemerkten Raum, damit kein
// automatisches Resume beim naechsten Laden passiert.
$('leaveBtn').onclick = () => {
  if (!confirm(t('leaveConfirm'))) return;
  socket.emit('leaveRoom');
  forgetRoom();
  lastState = null;
  lastLobby = null;
  chatMsgs = [];
  renderChat();
  $('seats').innerHTML = '';
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
