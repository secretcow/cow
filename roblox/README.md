# KuhPoker — Roblox-Port

Vollwertige Roblox-/Luau-Portierung des KuhPoker-Web-Spiels (Texas Hold'em mit
Kuhhandel-Tierkarten). Autoritativer Server über RemoteEvents/-Functions,
programmatisch aufgebaute UI (keine `.rbxlx`-Assets nötig), DataStore-Persistenz.

## Funktionsumfang

- **Mehrtisch-Lobby** (Code-basiert): Tisch erstellen mit Einstellungen
  (max. Spieler, Start-Chips, Modus Normal/Turnier/Cash, Flush) oder per Code beitreten.
- **Persistenz** (DataStore): Wallet + Statistiken (Matches/Hände gewonnen, größter Pot).
- **Reconnect/Disconnect**: Sitz bleibt erhalten, Schonfrist-Auto-Fold, automatische Raumaufräumung.
- **Gestaffelter All-In-Run-out** mit Equity-Anzeige je Sitz (TV-Poker-Stil).
- **Tisch-Chat**, Sprachumschaltung DE/EN.

## Projektstruktur

```
roblox/
├── default.project.json   # Rojo-Mapping (siehe unten)
├── aftman.toml            # pinnt die Rojo-Version
├── src/
│   ├── shared/            # → ReplicatedStorage.Shared  (reine, testbare Logik)
│   │   ├── Cards.luau, HandEval.luau, PokerEngine.luau,
│   │   ├── RoomManager.luau, Profile.luau, Strings.luau
│   ├── server/            # → ServerScriptService.Server
│   │   ├── GameServer.server.luau   # autoritativer Server (Script)
│   │   └── ProfileStore.luau        # DataStore-Anbindung (ModuleScript)
│   └── client/            # → StarterPlayer.StarterPlayerScripts.Client
│       └── GameClient.client.luau   # Lobby- + Tisch-UI (LocalScript)
└── tests/
    └── run.luau           # 113 Tests, standalone via luau-CLI
```

Rojo bildet `src/` so in den DataModel ab (aus `default.project.json`):

| Ordner        | Ziel in Roblox                               |
|---------------|----------------------------------------------|
| `src/shared`  | `ReplicatedStorage.Shared`                   |
| `src/server`  | `ServerScriptService.Server`                 |
| `src/client`  | `StarterPlayer.StarterPlayerScripts.Client`  |

> Hinweis: `GameServer` lädt `ProfileStore` über `script.Parent` — beide liegen
> als Geschwister unter `ServerScriptService.Server`.

## Tests laufen lassen (ohne Roblox)

Die reine Logik (`src/shared`) ist über die luau-CLI testbar:

```bash
# luau-CLI einmalig holen (falls nicht vorhanden), dann:
luau tests/run.luau        # erwartet: "113 bestanden, 0 fehlgeschlagen"
```

Server-/Client-Skripte nutzen `game:GetService` und sind daher nur ein
Parse-Check (Syntax gültig, wenn der einzige Fehler in der `GetService`-Zeile auftritt).

## Setup & Sync in Roblox Studio

1. **Toolchain installieren** (im Ordner `roblox/`):
   ```bash
   aftman install        # installiert Rojo in der gepinnten Version
   # Alternativ einmalig global:  cargo install rojo
   ```
2. **Rojo-Plugin** in Studio installieren: <https://rojo.space/docs/v7/getting-started/installation/>
   (Roblox Studio → Plugins → „Rojo").
3. **Server starten** (im Ordner `roblox/`):
   ```bash
   rojo serve
   ```
4. In **Studio**: neues *Baseplate* öffnen → Rojo-Plugin → **Connect**.
   Der Code aus `src/` erscheint an den oben genannten Stellen.

## DataStore aktivieren (Persistenz)

Game Settings → **Security** → **„Enable Studio Access to API Services"** aktivieren.

Ohne diese Option (oder bei DataStore-Ausfall) läuft alles **rein im Speicher**
weiter — der `ProfileStore` fängt das ab, das Spiel bleibt spielbar, nur nicht
persistent. Im veröffentlichten Spiel funktioniert DataStore zuverlässig.

## Lokal testen (Mehrspieler)

Studio → Reiter **Test** → *Clients and Servers*: **Players = 2** → **Start**.

Checkliste für den Playtest:
- Lobby → **Tisch erstellen** (Einstellungen prüfen) → Code merken.
- Zweiter Client → Code eingeben → **Beitreten**.
- Host startet die Hand → spielen, **All-In** auslösen → gestaffeltes Aufdecken + Equities.
- **Chat** senden, **Verlassen** und Reconnect (Client schließen/öffnen) testen.
- Cash-Modus: **Rebuy** zwischen den Händen.

## Veröffentlichen

1. **File → Publish to Roblox** → neues Erlebnis anlegen (oder bestehendes wählen).
2. Auf der **Creator-Seite**: Name, Beschreibung, Genre, Icon/Thumbnail setzen,
   Sichtbarkeit auf **Public**.
3. DataStore ist im veröffentlichten Spiel automatisch aktiv (kein Studio-Flag nötig).

## Build ohne laufende Sync (Place-Datei erzeugen)

```bash
rojo build -o KuhPoker.rbxlx     # erzeugt eine Place-Datei zum direkten Öffnen
```

## Offene Punkte / mögliche Erweiterungen

- **Wallet ↔ Cash-Game-Kopplung**: Buy-in/Cash-out gegen das persistente Wallet
  (derzeit zeigt das Wallet nur Guthaben + Statistiken; gespielt wird mit Tisch-Chips).
- **Monetarisierung** (Robux): Chip-Nachkauf als Developer Product mit idempotentem
  `ProcessReceipt`. Achtung: Robux-kaufbare Chips, die man gewinnen/verlieren kann,
  unterliegen Roblox' Glücksspiel-Richtlinien.
