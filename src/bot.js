// Test-Bot: tritt einem Raum bei und checkt/callt automatisch.
// Aufruf: node src/bot.js <CODE> [name]
import { io } from 'socket.io-client';

const code = process.argv[2];
const name = process.argv[3] || 'Ben';
const s = io('http://localhost:3000', { transports: ['websocket'] });

const token = process.argv[4] || `bot-${name}-${Math.random().toString(36).slice(2, 8)}`;
s.on('connect', () => {
  s.emit('joinRoom', { code, name, token }, (r) => console.log('join:', JSON.stringify(r)));
});

s.on('state', (st) => {
  if (st.yourTurn && st.actions) {
    setTimeout(() => {
      if (st.actions.canCheck) s.emit('action', { type: 'check' });
      else s.emit('action', { type: 'call' });
    }, 400);
  }
});

s.on('errorMsg', (m) => console.log('err:', m));
console.log(`Bot ${name} verbindet zu Raum ${code} ...`);
