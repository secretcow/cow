--!nonstrict
-- i18n fuer den Roblox-Client: uebersetzt die strukturierten Log-Events der Engine
-- ({ key, ...params }) sowie Kategorie-/Strassennamen nach DE/EN.
-- Treuer Port der Uebersetzungslogik aus public/client.js (I18N.*.log, catName,
-- streetName, cardWords).

local Cards = require(script and script.Parent.Cards or "./Cards")

local Strings = {}

-- Kategorie-Codes -> stabile IDs (abhaengig vom Flush-Modus, da Code 8/9/10
-- je nach Modus etwas anderes bedeuten).
local CAT_IDS_FLUSH = {
	[10] = "sflush",
	[9] = "quads",
	[8] = "flush",
	[7] = "full",
	[6] = "straight",
	[5] = "trips",
	[4] = "twopair",
	[3] = "pair",
	[2] = "high",
}
local CAT_IDS_NOFLUSH = {
	[8] = "quads",
	[7] = "full",
	[6] = "straight",
	[5] = "trips",
	[4] = "twopair",
	[3] = "pair",
	[2] = "high",
}
local CAT_LABELS = {
	sflush = { de = "Straße Flush", en = "Straight Flush" },
	quads = { de = "Vierling", en = "Four of a Kind" },
	flush = { de = "Flush", en = "Flush" },
	full = { de = "Full House", en = "Full House" },
	straight = { de = "Straße", en = "Straight" },
	trips = { de = "Drilling", en = "Three of a Kind" },
	twopair = { de = "Zwei Paare", en = "Two Pair" },
	pair = { de = "Paar", en = "Pair" },
	high = { de = "Hohe Karte", en = "High Card" },
}

local STREETS = {
	flop = "Flop",
	turn = "Turn",
	river = "River",
}

function Strings.streetName(_lang: string, s: string): string
	return STREETS[s] or s
end

-- Tiername in der gewuenschten Sprache.
function Strings.cardWords(lang: string, c): string
	local a = Cards.animalByRank(c.rank)
	if not a then
		return "?"
	end
	return if lang == "en" then a.nameEn else a.name
end

function Strings.catName(lang: string, code: number, flush: boolean): string
	local id = (if flush then CAT_IDS_FLUSH else CAT_IDS_NOFLUSH)[code]
	if not id then
		return ""
	end
	local lbl = CAT_LABELS[id]
	return if lang == "en" then lbl.en else lbl.de
end

local function joinCards(lang, cards)
	local parts = {}
	for _, c in cards do
		table.insert(parts, Strings.cardWords(lang, c))
	end
	return table.concat(parts, ", ")
end

-- ---- Log-Event -> Text ----
local LOG_DE = {
	handStart = function(e)
		return `— Hand {e.hand} — {e.name} hat den Button.`
	end,
	fold = function(e)
		return `{e.name} steigt aus (Fold).`
	end,
	check = function(e)
		return `{e.name} checkt.`
	end,
	call = function(e)
		return `{e.name} geht mit ({e.amount}).` .. (if e.allIn then " All-In!" else "")
	end,
	raise = function(e)
		return `{e.name} erhöht auf {e.to}.` .. (if e.allIn then " All-In!" else "")
	end,
	community = function(e)
		return `{Strings.streetName("de", e.street)}: {joinCards("de", e.cards)}`
	end,
	winFold = function(e)
		return `{e.name} gewinnt den Pot ({e.pot}) — alle anderen ausgestiegen.`
	end,
	shown = function(e)
		return `{e.name} zeigt die Karten.`
	end,
	win = function(e)
		local suffix = if e.cat then ` mit {Strings.catName("de", e.cat, e.flush)}` else ""
		return `{e.name} gewinnt {e.amount}{suffix}.`
	end,
	matchOver = function(e)
		return `Match beendet — {e.name} gewinnt!`
	end,
	rematch = function()
		return "Revanche! Neue Stacks, neues Glück."
	end,
	blindsUp = function(e)
		return `⬆ Blinds steigen auf {e.sb}/{e.bb} (Stufe {e.level}).`
	end,
	rebuy = function(e)
		return `{e.name} kauft nach: +{e.amount} 🪙 (Rebuy).`
	end,
}

local LOG_EN = {
	handStart = function(e)
		return `— Hand {e.hand} — {e.name} is on the button.`
	end,
	fold = function(e)
		return `{e.name} folds.`
	end,
	check = function(e)
		return `{e.name} checks.`
	end,
	call = function(e)
		return `{e.name} calls ({e.amount}).` .. (if e.allIn then " All-In!" else "")
	end,
	raise = function(e)
		return `{e.name} raises to {e.to}.` .. (if e.allIn then " All-In!" else "")
	end,
	community = function(e)
		return `{Strings.streetName("en", e.street)}: {joinCards("en", e.cards)}`
	end,
	winFold = function(e)
		return `{e.name} wins the pot ({e.pot}) — everyone else folded.`
	end,
	shown = function(e)
		return `{e.name} shows their cards.`
	end,
	win = function(e)
		local suffix = if e.cat then ` with {Strings.catName("en", e.cat, e.flush)}` else ""
		return `{e.name} wins {e.amount}{suffix}.`
	end,
	matchOver = function(e)
		return `Match over — {e.name} wins!`
	end,
	rematch = function()
		return "Rematch! Fresh stacks, fresh luck."
	end,
	blindsUp = function(e)
		return `⬆ Blinds rise to {e.sb}/{e.bb} (level {e.level}).`
	end,
	rebuy = function(e)
		return `{e.name} rebuys: +{e.amount} 🪙.`
	end,
}

-- Uebersetzt ein einzelnes Log-Event. Faellt bei unbekanntem key auf den key zurueck.
function Strings.translateLog(lang: string, event): string
	local tableForLang = if lang == "en" then LOG_EN else LOG_DE
	local fn = tableForLang[event.key]
	if not fn then
		return tostring(event.key)
	end
	return fn(event)
end

return Strings
