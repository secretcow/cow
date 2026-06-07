--!nonstrict
-- Monetarisierungs-Katalog fuer KuhPoker (Roblox). Keine Roblox-API — daher
-- standalone via luau-CLI testbar. Die eigentliche MarketplaceService-Anbindung
-- (Kauf-Prompts, ProcessReceipt, GamePass-Pruefung) liegt im Server; hier nur die
-- reine, testbare Katalog-/Berechnungslogik.
--
-- COMPLIANCE / fair play:
--   * Gekauft werden ausschliesslich SPIEL-Chips (Spass-Waehrung) und Kosmetik.
--   * Chips haben KEINEN Echtgeldwert und sind NICHT auszahlbar (kein Robux-Rueck-
--     fluss) — damit kein Gluecksspiel.
--   * Alles ist DETERMINISTISCH: jeder Kauf liefert eine bekannte Menge/ein
--     bekanntes Item. KEINE zufaelligen, kostenpflichtigen Beutelkisten/Lootboxen.
--   * VIP gewaehrt nur Komfort + Optik (mehr Spass-Chips, exklusive Looks, Tag) —
--     KEINEN Vorteil am Pokertisch (faires Spiel bleibt gewahrt).

local Monetization = {}

-- ---- Chip-Pakete (Developer Products, konsumierbar) ----
-- productId = Asset-Id aus dem Roblox-Dashboard. 0 = noch nicht angelegt -> der
-- Eintrag wird im UI ausgeblendet und serverseitig ignoriert (sicherer Default).
-- robux dient nur der Anzeige; den echten Preis legt das Dashboard fest.
Monetization.CHIP_PACKS = {
	{ id = "chips_small", productId = 0, chips = 5000, robux = 25, name = "Handvoll Chips", nameEn = "Handful of Chips" },
	{ id = "chips_medium", productId = 0, chips = 15000, robux = 60, name = "Stapel Chips", nameEn = "Stack of Chips" },
	{ id = "chips_large", productId = 0, chips = 50000, robux = 160, name = "Tresor Chips", nameEn = "Vault of Chips" },
	{ id = "chips_mega", productId = 0, chips = 150000, robux = 400, name = "Berg Chips", nameEn = "Mountain of Chips" },
}

-- ---- VIP (Game Pass, einmaliger Kauf) ----
-- passId = Game-Pass-Id aus dem Dashboard (0 = noch nicht angelegt).
Monetization.VIP = {
	passId = 0,
	name = "VIP",
	nameEn = "VIP",
	robux = 250,
	dailyMultiplier = 2, -- doppelter taeglicher Login-Bonus (reine Spass-Chips)
	tag = "👑", -- Abzeichen am Namen
	-- Vorteile rein als Text fuer das Shop-UI (DE/EN).
	perks = {
		"👑 VIP-Abzeichen am Namen",
		"💰 Doppelter taeglicher Login-Bonus",
		"🎨 Exklusive VIP-Kartenrueckseite & -Rahmen",
	},
	perksEn = {
		"👑 VIP badge by your name",
		"💰 Double daily login bonus",
		"🎨 Exclusive VIP card back & frame",
	},
}

-- Findet ein Chip-Paket per id (oder nil).
function Monetization.findPack(id)
	for _, pack in Monetization.CHIP_PACKS do
		if pack.id == id then
			return pack
		end
	end
	return nil
end

-- Findet ein Chip-Paket per (Roblox-)productId. productId 0 zaehlt als "nicht
-- konfiguriert" und matcht nie — schuetzt vor versehentlichen Gutschriften.
function Monetization.packByProductId(productId)
	local pid = tonumber(productId)
	if not pid or pid == 0 then
		return nil
	end
	for _, pack in Monetization.CHIP_PACKS do
		if pack.productId == pid then
			return pack
		end
	end
	return nil
end

-- Wie viele Chips gibt ein gekauftes Developer Product? (0, falls unbekannt.)
function Monetization.chipsForProduct(productId)
	local pack = Monetization.packByProductId(productId)
	return pack and pack.chips or 0
end

-- Ist ein Chip-Paket im Shop kaufbar? (Nur wenn eine echte productId gesetzt ist.)
function Monetization.packAvailable(pack)
	return pack ~= nil and tonumber(pack.productId) ~= nil and pack.productId ~= 0
end

-- Ist der VIP-Pass im Shop kaufbar? (Nur wenn eine echte passId gesetzt ist.)
function Monetization.vipAvailable()
	return tonumber(Monetization.VIP.passId) ~= nil and Monetization.VIP.passId ~= 0
end

-- Wendet den VIP-Multiplikator auf einen Bonusbetrag an (Nicht-VIP: unveraendert).
function Monetization.applyVipBonus(amount, isVip)
	local a = math.max(0, math.floor(tonumber(amount) or 0))
	if isVip then
		return a * math.max(1, math.floor(Monetization.VIP.dailyMultiplier or 1))
	end
	return a
end

return Monetization
