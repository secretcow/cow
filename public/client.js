/* global io */
const socket = io();

const ANIMALS = {
  1: { name: 'Hahn', value: 10, emoji: '🐓' },
  2: { name: 'Gans', value: 40, emoji: '🪿' },
  3: { name: 'Katze', value: 90, emoji: '🐈' },
  4: { name: 'Hund', value: 160, emoji: '🐕' },
  5: { name: 'Schaf', value: 250, emoji: '🐑' },
  6: { name: 'Ziege', value: 350, emoji: '🐐' },
  7: { name: 'Esel', value: 500, emoji: '🫏' },
  8: { name: 'Schwein', value: 650, emoji: '🐖' },
  9: { name: 'Kuh', value: 800, emoji: '🐄' },
  10: { name: 'Pferd', value: 1000, emoji: '🐎' },
};

const $ = (id) => document.getElementById(id);
let myCode = null;
let lastState = null;
let lastLobby = null;
let raiseOpen = false;

// Stabiler Spieler-Token fuer Reconnect (ueberlebt Reload/Verbindungsabbruch).
function getToken() {
  let t = localStorage.getItem('kuhpoker_token');
  if (!t) {
    t = (crypto.randomUUID && crypto.randomUUID()) || `t${Date.now()}${Math.random()}`;
    localStorage.setItem('kuhpoker_token', t);
  }
  return t;
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

// ---------- Lobby ----------
function loadName() {
  return localStorage.getItem('kuhpoker_name') || '';
}
$('nameInput').value = loadName();

$('createBtn').onclick = () => {
  const name = $('nameInput').value.trim();
  localStorage.setItem('kuhpoker_name', name);
  socket.emit('createRoom', { name, token: myToken }, (res) => {
    if (res?.error) return toast(res.error);
    rememberRoom(res.code);
    showWaiting(res.code);
  });
};

$('joinBtn').onclick = () => {
  const name = $('nameInput').value.trim();
  const code = $('codeInput').value.trim().toUpperCase();
  if (!code) return toast('Bitte einen Code eingeben.');
  localStorage.setItem('kuhpoker_name', name);
  socket.emit('joinRoom', { code, name, token: myToken }, (res) => {
    if (res?.error) return toast(res.error);
    rememberRoom(res.code);
  });
};

// Automatischer Reconnect: bei (Wieder-)Verbindung den gespeicherten Sitz zurueckholen.
socket.on('connect', () => {
  const code = localStorage.getItem('kuhpoker_code');
  if (!code) return;
  socket.emit('resume', { code, token: myToken }, (res) => {
    if (res?.error) {
      // Raum existiert nicht mehr -> zurueck zur Lobby.
      forgetRoom();
      $('game').classList.add('hidden');
      $('lobby').classList.remove('hidden');
    }
  });
});

// Beitritt per ?code= in der URL
const urlCode = new URLSearchParams(location.search).get('code');
if (urlCode) $('codeInput').value = urlCode.toUpperCase();

function showWaiting(code) {
  $('waiting').classList.remove('hidden');
  $('roomCode').textContent = code;
}

$('copyLinkBtn').onclick = () => {
  const link = `${location.origin}/?code=${myCode}`;
  navigator.clipboard?.writeText(link).then(
    () => toast('Link kopiert!'),
    () => toast(link)
  );
};

// ---------- Server-Events ----------
socket.on('lobby', (lob) => {
  lastLobby = lob;
  rememberRoom(lob.code);
  if (lob.hasTable) {
    $('lobby').classList.add('hidden');
    $('game').classList.remove('hidden');
    $('topCode').textContent = `Tisch ${lob.code}`;
    renderConnStatus(lob);
  } else if (myCode) {
    showWaiting(lob.code);
    const others = lob.players.length;
    $('waitHint').textContent =
      others < 2 ? 'Warte auf zweiten Spieler …' : 'Spieler verbunden!';
  }
});

function renderConnStatus(lob) {
  // Verbindungsstatus des Gegners (zweiter Sitz, der nicht zu meinem Token gehoert kennen wir hier nicht;
  // wir zeigen einfach, ob beide Sitze verbunden sind).
  const el = $('connStatus');
  const disconnected = lob.players.filter((p) => !p.connected);
  if (lob.players.length < 2) {
    el.textContent = '● wartet auf Gegner';
    el.className = 'conn waiting';
  } else if (disconnected.length > 0) {
    el.textContent = '● Gegner getrennt – wartet auf Reconnect';
    el.className = 'conn off';
  } else {
    el.textContent = '● verbunden';
    el.className = 'conn on';
  }
}

socket.on('state', (s) => {
  lastState = s;
  render(s);
});

socket.on('errorMsg', (msg) => toast(msg));

// ---------- Sound (WebAudio, keine Asset-Dateien noetig) ----------
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
    const t = ctx.currentTime;
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.start(t);
    o.stop(t + dur);
  } catch (_) {}
}
const sfx = {
  deal: () => beep(440, 0.08, 'triangle', 0.05),
  turn: () => { beep(660, 0.1, 'sine', 0.09); },
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

// Zustand fuer Sound-/Animations-Trigger
let prevCommunityCount = 0;
let prevHandNo = 0;
let prevStage = null;
let prevYourTurn = false;
let prevPot = 0;
let newCardKeys = new Set(); // Karten, die in diesem Render frisch ausgeteilt wurden

// ---------- Rendering ----------
function cardEl(card) {
  const el = document.createElement('div');
  if (!card) {
    el.className = 'card back';
    el.innerHTML = '<div class="back-pattern">🐄</div>';
    return el;
  }
  const a = ANIMALS[card.rank];
  el.className = 'card';
  el.innerHTML = `
    <div class="card-top">${a.value}</div>
    <div class="card-emoji">${a.emoji}</div>
    <div class="card-name">${a.name}</div>
    <div class="card-bot">${a.value}</div>`;
  return el;
}

function renderHole(container, cards, highlight = [], animate = false) {
  container.innerHTML = '';
  const hi = new Set(highlight.map((c) => `${c.rank}-${c.copy}`));
  cards.forEach((c, idx) => {
    const el = cardEl(c);
    if (c && hi.has(`${c.rank}-${c.copy}`)) el.classList.add('used');
    if (animate) {
      el.classList.add('dealing');
      el.style.animationDelay = `${idx * 0.12}s`;
    }
    container.appendChild(el);
  });
}

function render(s) {
  const me = s.players[s.meIdx];
  const opp = s.players[s.meIdx === 0 ? 1 : 0];

  // --- Trigger fuer Sound & Deal-Animation erkennen ---
  const handChanged = s.handNo !== prevHandNo;
  const communityGrew = s.community.length > prevCommunityCount;
  newCardKeys = new Set();
  if (communityGrew) {
    for (let i = prevCommunityCount; i < s.community.length; i++) {
      const c = s.community[i];
      newCardKeys.add(`${c.rank}-${c.copy}`);
    }
  }

  // Namen / Stacks
  $('meName').textContent = me.name + (me.isMe ? ' (Du)' : '');
  $('oppName').textContent = opp.name;
  $('meStack').textContent = `${me.stack} 🪙`;
  $('oppStack').textContent = `${opp.stack} 🪙`;
  toggle($('meBtn'), me.isButton);
  toggle($('oppBtn'), opp.isButton);

  // Handkarten
  const usedMe = s.result?.reveal?.find((r) => r.i === s.meIdx)?.eval?.cards || [];
  const usedOpp = s.result?.reveal?.find((r) => r.i !== s.meIdx)?.eval?.cards || [];
  renderHole($('meHole'), me.hole.length ? me.hole : [null, null], usedMe, handChanged);
  renderHole($('oppHole'), opp.hole.length ? opp.hole : [null, null], usedOpp, handChanged);

  // Einsatz-Chips
  betChip($('meBet'), me.bet);
  betChip($('oppBet'), opp.bet);

  // Community
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

  // Pot & Stage
  $('pot').textContent = `Pot: ${s.pot} 🪙`;
  $('stageLabel').textContent = stageName(s.stage);

  // Hand-Labels beim Showdown
  showHandLabel($('meHandLabel'), s, s.meIdx);
  showHandLabel($('oppHandLabel'), s, s.meIdx === 0 ? 1 : 0);

  // Ergebnis-Banner
  renderResult(s, me, opp);

  // Steuerung
  renderControls(s, me);

  // Log
  renderLog(s.log);

  // Folded-Optik
  $('meHole').parentElement.classList.toggle('folded', me.folded);
  $('oppHole').parentElement.classList.toggle('folded', opp.folded);

  if (lastLobby) renderConnStatus(lastLobby);

  // --- Sound-Trigger ---
  if (handChanged && s.handNo > 0) sfx.deal();
  if (communityGrew) sfx.deal();
  if (s.pot > prevPot && !handChanged && s.stage !== 'handover') sfx.chip();
  if (s.yourTurn && !prevYourTurn) sfx.turn();
  if (s.stage === 'handover' && prevStage !== 'handover' && s.result) {
    if (s.result.winners.includes(s.meIdx) && s.result.winners.length === 1) sfx.win();
    else if (!s.result.winners.includes(s.meIdx)) sfx.lose();
  }

  prevHandNo = s.handNo;
  prevCommunityCount = s.community.length;
  prevStage = s.stage;
  prevYourTurn = s.yourTurn;
  prevPot = s.pot;
}

function showHandLabel(el, s, idx) {
  const rev = s.result?.reveal?.find((r) => r.i === idx);
  if ((s.stage === 'showdown' || s.stage === 'handover') && rev?.eval && !s.players[idx].folded) {
    el.textContent = rev.eval.name;
    el.classList.remove('hidden');
  } else {
    el.classList.add('hidden');
  }
}

function renderResult(s, me, opp) {
  const banner = $('resultBanner');
  if (s.stage === 'handover' && s.result) {
    const won = s.result.winners.includes(s.meIdx);
    const split = s.result.winners.length > 1;
    banner.classList.remove('hidden', 'win', 'lose');
    if (split) {
      banner.textContent = `Split Pot — ${s.result.pot} geteilt`;
    } else if (won) {
      banner.textContent = `Du gewinnst ${s.result.pot} 🪙!`;
      banner.classList.add('win');
    } else {
      banner.textContent = `${opp.name} gewinnt ${s.result.pot} 🪙`;
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

  // Match-Ende
  if (s.matchOver) {
    matchOver.classList.remove('hidden');
    const iWon = s.matchWinnerId === me.id;
    $('matchOverText').textContent = iWon
      ? '🏆 Du hast das Match gewonnen!'
      : '😿 Match verloren.';
    actionButtons.classList.add('hidden');
    raisePanel.classList.add('hidden');
    nextBtn.classList.add('hidden');
    turnInd.textContent = '';
    return;
  }
  matchOver.classList.add('hidden');

  // Zwischen den Händen: "Nächste Hand"
  if (s.stage === 'idle' || s.stage === 'handover') {
    nextBtn.classList.remove('hidden');
    nextBtn.textContent = s.stage === 'idle' ? 'Erste Hand starten' : 'Nächste Hand';
    actionButtons.classList.add('hidden');
    raisePanel.classList.add('hidden');
    turnInd.textContent = '';
    raiseOpen = false;
    return;
  }
  nextBtn.classList.add('hidden');

  if (s.yourTurn && s.actions) {
    turnInd.textContent = 'Du bist am Zug';
    turnInd.className = 'turn-indicator active';
    const a = s.actions;

    const ccBtn = $('checkCallBtn');
    if (a.canCheck) {
      ccBtn.textContent = 'Check';
      ccBtn.dataset.act = 'check';
    } else {
      ccBtn.textContent = `Call ${a.toCall}`;
      ccBtn.dataset.act = 'call';
    }
    $('raiseBtn').classList.toggle('hidden', !a.canRaise);
    $('raiseBtn').textContent = a.canCheck ? 'Bet' : 'Raise';

    if (raiseOpen && a.canRaise) {
      actionButtons.classList.add('hidden');
      raisePanel.classList.remove('hidden');
      setupRaise(a);
    } else {
      actionButtons.classList.remove('hidden');
      raisePanel.classList.add('hidden');
    }
  } else {
    turnInd.textContent =
      s.toActId === null ? '' : `Warte auf ${opponentName(s)} …`;
    turnInd.className = 'turn-indicator';
    actionButtons.classList.add('hidden');
    raisePanel.classList.add('hidden');
    raiseOpen = false;
  }
}

function opponentName(s) {
  const opp = s.players[s.meIdx === 0 ? 1 : 0];
  return opp.name;
}

function setupRaise(a) {
  const slider = $('raiseSlider');
  const amount = $('raiseAmount');
  slider.min = a.minRaiseTo;
  slider.max = a.maxRaiseTo;
  amount.min = a.minRaiseTo;
  amount.max = a.maxRaiseTo;
  if (!amount.value || +amount.value < a.minRaiseTo || +amount.value > a.maxRaiseTo) {
    amount.value = a.minRaiseTo;
    slider.value = a.minRaiseTo;
  }
}

function stageName(stage) {
  return (
    {
      idle: 'Bereit',
      preflop: 'Pre-Flop',
      flop: 'Flop',
      turn: 'Turn',
      river: 'River',
      showdown: 'Showdown',
      handover: 'Hand vorbei',
    }[stage] || stage
  );
}

function renderLog(log) {
  const el = $('log');
  el.innerHTML = log.map((l) => `<div>${escapeHtml(l)}</div>`).join('');
  el.scrollTop = el.scrollHeight;
}

function betChip(el, amount) {
  if (amount > 0) {
    el.textContent = `${amount}`;
    el.classList.remove('hidden');
  } else {
    el.classList.add('hidden');
  }
}

function toggle(el, on) {
  el.classList.toggle('hidden', !on);
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
  const amount = +$('raiseAmount').value;
  socket.emit('action', { type: 'raise', amount });
  raiseOpen = false;
};
$('raiseCancel').onclick = () => {
  raiseOpen = false;
  render(lastState);
};
$('raiseSlider').oninput = (e) => {
  $('raiseAmount').value = e.target.value;
};
$('raiseAmount').oninput = (e) => {
  $('raiseSlider').value = e.target.value;
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
$('rematchBtn').onclick = () => socket.emit('rematch');

// ---------- Toast ----------
let toastTimer = null;
function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), 2600);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
