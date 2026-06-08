--!nonstrict
-- Reine Freundes-/Empfehlungs-Logik fuer KuhPoker. Keine Roblox-API — daher
-- standalone via luau-CLI testbar. Die Roblox-Anbindung (SocialService-Einladung,
-- LaunchData-Auswertung, Belohnungs-Gutschrift) liegt im Server bzw. Client.
--
-- Idee (viraler Wachstums-Hebel): Spieler laden Freunde ins Spiel ein. Tritt ein
-- NEUER Spieler ueber die Einladung bei, bekommen BEIDE Spass-Chips/XP:
--   * der Eingeladene einen Willkommensbonus (einmalig),
--   * der Einladende eine Empfehlungs-Belohnung pro neuem Freund (bis zu einem Cap).
--
-- Reine Spass-Chips/XP — kein Echtgeldwert, kein Gluecksspiel, kein Pay-to-Win.

local Friends = {}

-- Willkommensbonus fuer den Eingeladenen (einmalig, beim Beitritt ueber Einladung).
Friends.INVITEE_CHIPS = 2500
Friends.INVITEE_XP = 50

-- Empfehlungs-Belohnung fuer den Einladenden je erfolgreich geworbenem Freund.
Friends.INVITER_CHIPS = 1500
Friends.INVITER_XP = 40

-- Bis zu so vielen geworbenen Freunden wird der Einladende belohnt (begrenzt Farming;
-- weitere Empfehlungen werden weiter GEZAEHLT, aber nicht mehr verguetet).
Friends.MAX_REWARDED = 50

local function toInt(v, default)
	local n = tonumber(v)
	if n == nil or n ~= n then
		return default
	end
	return math.floor(n)
end

-- Darf dieses Profil noch geworben werden? Nur, wenn es noch nie geworben wurde.
function Friends.eligibleInvitee(p)
	return type(p) == "table" and (p.referredBy == nil or p.referredBy == "")
end

-- Markiert den Eingeladenen als von `inviterId` geworben (einmalig) und gibt den
-- Willkommensbonus zurueck. Tut nichts (gibt nil zurueck), wenn schon geworben oder
-- die Inviter-Id ungueltig/Selbstwerbung ist. Mutiert das Profil.
function Friends.markReferred(p, inviterId, inviteeId)
	if not Friends.eligibleInvitee(p) then
		return nil
	end
	local inv = tostring(inviterId or "")
	if inv == "" or inv == tostring(inviteeId or p.userId or "") then
		return nil -- keine gueltige Inviter-Id oder Selbstwerbung
	end
	p.referredBy = inv
	return { chips = Friends.INVITEE_CHIPS, xp = Friends.INVITEE_XP }
end

-- Verbucht beim Einladenden einen erfolgreich geworbenen Freund. Erhoeht den Zaehler
-- und gibt die Belohnung zurueck — oder nil, wenn der Cap ueberschritten ist (dann
-- wird nur noch gezaehlt, nicht verguetet). Mutiert das Profil.
function Friends.recordSuccess(p)
	p.invitesAccepted = math.max(0, toInt(p.invitesAccepted, 0)) + 1
	if p.invitesAccepted > Friends.MAX_REWARDED then
		return { chips = 0, xp = 0, count = p.invitesAccepted, rewarded = false }
	end
	return {
		chips = Friends.INVITER_CHIPS,
		xp = Friends.INVITER_XP,
		count = p.invitesAccepted,
		rewarded = true,
	}
end

-- Anzeige-Sicht (fuer den Client): Anzahl geworbener Freunde + ob selbst geworben.
function Friends.view(p)
	p = p or {}
	return {
		invitesAccepted = math.max(0, toInt(p.invitesAccepted, 0)),
		wasReferred = type(p.referredBy) == "string" and p.referredBy ~= "",
	}
end

return Friends
