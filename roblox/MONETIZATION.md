# KuhPoker – Monetarisierung einrichten

Diese Anleitung zeigt Schritt für Schritt, wie du im Roblox Creator Dashboard
die **Chip-Pakete** (Developer Products) und den **VIP-Pass** (Game Pass) anlegst
und ihre IDs ins Spiel einträgst.

> **Wichtig:** Solange die IDs auf `0` stehen, ist der Shop **unsichtbar** und der
> Server ignoriert alle Käufe. Es kann also nichts schiefgehen, bevor du fertig
> konfiguriert hast. Erst wenn echte IDs gesetzt sind, erscheinen die Angebote.

---

## 1. Chip-Pakete anlegen (Developer Products)

Developer Products sind **mehrfach kaufbar** (konsumierbar) — ideal für Chips.

1. Öffne **[create.roblox.com](https://create.roblox.com)** → wähle deine Experience.
2. Linkes Menü: **Monetization → Developer Products → „Create a Developer Product"**.
3. Lege **vier** Produkte an (Name + Preis in Robux frei wählbar), z. B.:

   | Spiel-Eintrag (`id`) | Vorschlag Name | Chips | Preis (Robux) |
   |---|---|---|---|
   | `chips_small`  | Handvoll Chips | 5 000   | 25  |
   | `chips_medium` | Stapel Chips   | 15 000  | 60  |
   | `chips_large`  | Tresor Chips   | 50 000  | 160 |
   | `chips_mega`   | Berg Chips     | 150 000 | 400 |

4. Nach dem Erstellen zeigt jedes Produkt eine **Product-ID** (eine Zahl).
   Kopiere sie.

5. Trage die IDs in **`roblox/src/shared/Monetization.luau`** ein — ersetze die
   `productId = 0` durch deine echten Zahlen:

   ```lua
   Monetization.CHIP_PACKS = {
       { id = "chips_small",  productId = 123456789, chips = 5000,   robux = 25,  ... },
       { id = "chips_medium", productId = 123456790, chips = 15000,  robux = 60,  ... },
       { id = "chips_large",  productId = 123456791, chips = 50000,  robux = 160, ... },
       { id = "chips_mega",   productId = 123456792, chips = 150000, robux = 400, ... },
   }
   ```

   - `chips` = wie viele Spaß-Chips gutgeschrieben werden (Server-autoritativ).
   - `robux` = nur **Anzeige** im Shop. Der echte Preis kommt aus dem Dashboard.

---

## 2. VIP anlegen (Game Pass)

Ein Game Pass ist ein **einmaliger** Kauf — perfekt für VIP.

1. Dashboard → **Monetization → Passes → „Create a Pass"**.
2. Name `VIP`, Bild + Preis (z. B. 250 Robux) festlegen, speichern.
3. Kopiere die **Pass-ID** und trage sie in `Monetization.luau` ein:

   ```lua
   Monetization.VIP = {
       passId = 987654321,   -- <- deine Pass-ID hier
       dailyMultiplier = 2,  -- doppelter Tagesbonus (reine Spaß-Chips)
       ...
   }
   ```

   VIP gewährt automatisch:
   - 👑 VIP-Abzeichen an Name & Tisch-Sitz,
   - doppelter täglicher Login-Bonus,
   - exklusive VIP-Kosmetik (`vip_royal`-Kartenrückseite, `vip_crown`-Rahmen).

---

## 3. Veröffentlichen & testen

1. Mit **Rojo** synchronisieren und in Roblox Studio **publishen**.
2. Im **echten Spiel** (nicht nur Studio) testen: In Studio funktionieren Käufe
   nur eingeschränkt. Am besten über einen Test-Account im veröffentlichten Spiel.
3. Kauf-Flow prüfen:
   - Chip-Kauf → Server schreibt Chips gut (`ProcessReceipt`) → Toast „Kauf
     erfolgreich" + Wallet aktualisiert sich.
   - VIP-Kauf → 👑 erscheint, Tagesbonus verdoppelt sich, VIP-Kosmetik
     freigeschaltet.

---

## 4. ✅ Compliance-Checkliste (Pflicht bei einem Poker-Spiel)

Roblox stuft Poker als **simuliertes Glücksspiel** ein. Beachte:

- [ ] **Maturity-&-Compliance-Fragebogen** ehrlich ausfüllen (Dashboard →
      Settings → Maturity). Poker führt i. d. R. zu einer **17+**-Einstufung.
- [ ] **Alters-/ID-Verifizierung** als Creator abschließen (für 17+ & für DevEx).
- [ ] Bewusst sein: **17+-Experiences** sind nur für verifizierte 17+-Nutzer
      sichtbar → kleinere Reichweite.

Was das Spiel **bereits richtig macht** (bitte so lassen):

- ✅ Nur **Spaß-Chips ohne Echtgeldwert**, **nicht auszahlbar** (keine
      Rückumwandlung Chips → Robux).
- ✅ **Kein Verwetten von Robux**, kein Tausch Chips ↔ Robux.
- ✅ **Keine Zufalls-Käufe / Lootboxen** (sonst müssten Gewinnchancen offen
      gelegt werden).
- ✅ VIP gibt nur **Komfort + Optik**, keinen Vorteil am Pokertisch.

> Kein Rechtsrat — die finale Einstufung trifft Roblox bei der Veröffentlichung.

---

## 5. Kostenüberblick

- **Veröffentlichen, Hosting, DataStore, Produkte anlegen:** kostenlos.
- **Marketplace-Gebühr:** Roblox behält ~30 %, du bekommst ~70 % in Robux.
- **Auszahlung (DevEx):** ab 30 000 Robux, mit ID-Verifizierung; Einnahmen sind
  steuerpflichtig (Steuerformular im Dashboard hinterlegen).
- **Keine** Vorab- oder Monatskosten.
