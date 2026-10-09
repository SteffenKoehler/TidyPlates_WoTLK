--[[TPTP Tank Toggle Command]] --
local L = LibStub("AceLocale-3.0"):GetLocale("TidyPlatesThreat", false)

local Active = function()
	return GetActiveTalentGroup()
end
local function toggleDPS()
	TidyPlatesThreat:setSpecDPS(Active())
	TidyPlatesThreat.db.char.threat.tanking = false
	TidyPlatesThreat.db.profile.threat.ON = true
	if TidyPlatesThreat.db.profile.verbose then
		print(L["-->>|cffff0000DPS Plates Enabled|r<<--"])
		print(L["|cff89F559Threat Plates|r: DPS switch detected, you are now in your |cff89F559"] .. TidyPlatesThreat:dualSpec() .. L["|r spec and are now in your |cffff0000dpsing / healing|r role."])
	end
	TidyPlates:ForceUpdate()
end
local function toggleTANK()
	TidyPlatesThreat:setSpecTank(Active())
	TidyPlatesThreat.db.char.threat.tanking = true
	TidyPlatesThreat.db.profile.threat.ON = true
	if TidyPlatesThreat.db.profile.verbose then
		print(L["-->>|cff00ff00Tank Plates Enabled|r<<--"])
		print(L["|cff89F559Threat Plates|r: Tank switch detected, you are now in your |cff89F559"] .. TidyPlatesThreat:dualSpec() .. L["|r spec and are now in your |cff00ff00tanking|r role."])
	end
	TidyPlates:ForceUpdate()
end

local function TPTPDPS()
	toggleDPS()
end
SLASH_TPTPDPS1 = "/tptpdps"
SlashCmdList["TPTPDPS"] = TPTPDPS

local function TPTPTANK()
	toggleTANK()
end
SLASH_TPTPTANK1 = "/tptptank"
SlashCmdList["TPTPTANK"] = TPTPTANK

local function TPTPTOGGLE()
	TidyPlatesThreat.db.char.threat.tanking = not TidyPlatesThreat.db.char.threat.tanking
	if TidyPlatesThreat.db.char.threat.tanking then
		toggleTANK()
	else
		toggleDPS()
	end
end
SLASH_TPTPTOGGLE1 = "/tptptoggle"
SlashCmdList["TPTPTOGGLE"] = TPTPTOGGLE

local function TPTPOVERLAP()
	SetCVar("nameplateAllowOverlap", abs(GetCVar("nameplateAllowOverlap") - 1))
	if GetCVar("nameplateAllowOverlap") == "0" and TidyPlatesThreat.db.profile.verbose then
		print(L["-->>Nameplate Overlapping is now |cffff0000OFF!|r<<--"])
	else
		print(L["-->>Nameplate Overlapping is now |cff00ff00ON!|r<<--"])
	end
end
SLASH_TPTPOVERLAP1 = "/tptpol"
SlashCmdList["TPTPOVERLAP"] = TPTPOVERLAP

local function TPTPVERBOSE()
	TidyPlatesThreat.db.profile.verbose = not TidyPlatesThreat.db.profile.verbose
	if TidyPlatesThreat.db.profile.verbose then
		print(L["-->>Threat Plates verbose is now |cff00ff00ON!|r<<--"])
	else
		print(L["-->>Threat Plates verbose is now |cffff0000OFF!|r<<-- shhh!!"])
	end
end
SLASH_TPTPVERBOSE1 = "/tptpverbose"
SlashCmdList["TPTPVERBOSE"] = TPTPVERBOSE

--[[Plater-Optik als eigenes Profil]] --
-- /tptpplater          Profil "Plater" aktivieren (beim ersten Mal als Kopie des aktuellen Profils anlegen)
-- /tptpplater reset    Plater-Optik im Profil "Plater" erneut anwenden
-- /tptpplater default  zurück zum Profil "Default"
-- /tptpclassic [reset|default|info]  dasselbe für die Classic-Optik (Profil "Classic", weiter unten)
-- Wirkt sofort: Stile und Widgets werden beim Profilwechsel neu gebaut (ApplyProfileLive).
local PLATER_PROFILE = "Plater"
-- Version der Plater-Optik. Kommen neue Einstellungen dazu: Version erhöhen und unten
-- in PlaterMigrations nur die neuen Werte nachtragen. Bestehende Plater-Profile werden
-- dann beim Einloggen bzw. beim Wechsel ins Profil ergänzt, ohne eigene Anpassungen
-- zu überschreiben (kein /tptpplater reset nötig).
local PLATER_LOOK_VERSION = 3

-- Positionen, die von der Balkengröße abhängen. Läuft beim Anwenden der Optik und erneut,
-- wenn im Profil "Plater" Breite/Höhe geändert wird; Schriftgrößen u. ä. bleiben unberührt.
local function PlaterLayout(p)
	local s = p.settings
	local width, height = s.healthbar.width or 170, s.healthbar.height or 18
	local top, bottom, left, right = height / 2, -height / 2, -width / 2, width / 2

	-- Zauberleiste unter dem Balken; sie überdeckt beim Zaubern den Namen
	local castHeight = s.castbar.height or 16
	local castY = bottom - 2 - castHeight / 2
	s.castbar.y = castY
	s.castborder.y = castY
	s.castnostop.y = castY

	-- Name unter dem Balken, volle Breite, damit lange Namen nicht so früh abgeschnitten werden
	s.name.width = width
	s.name.y = castY

	-- Lebenspunkte-Text mittig im Balken
	s.customtext.width = width - 10

	-- Zaubername links in der Zauberleiste (rechts steht die Restzeit), Symbol links daneben
	local spellWidth = width - 40
	s.spelltext.width = spellWidth
	s.spelltext.x = left + 3 + spellWidth / 2
	s.spelltext.y = castY
	s.spellicon.scale = castHeight
	s.spellicon.x = left - castHeight / 2 - 2
	s.spellicon.y = castY

	-- Stufe klein über der rechten oberen Ecke
	s.level.x = right - 15
	s.level.y = top + 6

	-- Raid-Symbol links neben dem Balken
	s.raidicon.x = left - (s.raidicon.scale or 20) / 2 - 3
	s.raidicon.y = 0

	-- Auren direkt über dem Balken (Versatz wird mit der Skalierung des Widgets multipliziert)
	local auraScale = p.debuffWidget.scale or 1.15
	p.debuffWidget.y = (top + 3) / auraScale + 9
end

-- keepSize: Balkengröße des Profils behalten (Optik zurücksetzen), sonst Ausgangsgröße
local function ApplyPlaterLook(p, keepSize)
	local s = p.settings
	p.platerLookVersion = PLATER_LOOK_VERSION
	p.platerBorder.ON = true
	p.platerBorder.size = 1

	-- Mitskalierte Rahmengrafiken aus, der scharfe Rahmen ersetzt sie
	s.healthborder.show = false
	s.elitehealthborder.show = false
	s.castborder.show = false
	s.castnostop.show = false
	s.threatborder.show = false
	-- Ziel/Mouseover: weiß/grau über den Rahmen statt Leuchtgrafik (Pfeile bleiben)
	s.target.texture = "Empty"
	s.highlight.texture = "Empty"

	-- Lebenspunkte-Text "4.3k (100%)"
	p.text.parens = true

	-- Konstante Größe wie bei Plater: Aggro nur über die Farbe, nicht über die Größe
	-- (sonst schrumpfen normale Mobs im Kampf um 20 % und je nach Aggro-Stufe)
	p.threat.useScale = false
	-- Keine Aggro-Zacken um die Plakette: die Information steckt schon in der Balkenfarbe,
	-- und mit Tank-Ansicht auf DD/Heiler zeigen sie sonst bei jedem getankten Mob eine Warnung
	p.threat.art.ON = false
	-- Zauberleiste nach Unterbrechbarkeit färben
	p.platerCast.ON = true

	-- Plaketten stapeln (ersetzt die WeakAura "Enhanced Stacking Nameplate")
	p.stacking.ON = true

	-- Schlichte Schrift mit Kontur
	for _, key in ipairs({"name", "customtext", "spelltext", "level"}) do
		s[key].typeface = "Arial Narrow"
		s[key].flags = "OUTLINE"
		s[key].shadow = false
	end

	-- Etwas größer als vorher (150x15), Zauberleiste übernimmt die Breite
	if not keepSize then
		s.healthbar.width = 170
		s.healthbar.height = 18
	end

	-- Zauberleiste so hoch wie der Name
	s.castbar.height = 16

	s.name.size = 13
	s.name.align = "CENTER"

	s.customtext.size = 12
	s.customtext.x = 0
	s.customtext.y = 0
	s.customtext.align = "CENTER"

	s.spelltext.size = 11
	s.spelltext.align = "LEFT"

	s.level.show = true
	s.level.size = 10
	s.level.width = 30
	s.level.align = "RIGHT"
	s.level.vertical = "CENTER"

	-- Raid-Symbol links neben dem Balken (darüber sitzen jetzt die Auren)
	s.raidicon.scale = 20

	-- Auren mittig (3 Symbole à 24 px + 2 px Abstand)
	p.debuffWidget.scale = 1.15
	p.debuffWidget.anchor = "CENTER"
	p.debuffWidget.x = 64 - (3 * 24 + 2 * 2) / 2 -- Widget ist 128 breit, Symbole beginnen links

	PlaterLayout(p)
end

-- Classic-Optik: originale Blizzard-Grafiken (Goldrahmen mit Stufen-Feld) über dem
-- Classic-Widget, Name über dem Balken, Lebenspunkte-Text wie im Default-Profil.
-- Gleiche Versionsregel wie bei Plater (CLASSIC_LOOK_VERSION + ClassicMigrations).
local CLASSIC_PROFILE = "Classic"
local CLASSIC_LOOK_VERSION = 11

-- Zauberleiste "unterbrechbar, Kick bereit" in Gold wie bei WoW Forever (Mittelton der
-- dort hell/dunkel verlaufenden Leiste; vorher Cyan)
local CLASSIC_CAST_READY = {r = 1, g = 0.8, b = 0.2}

-- Positionen, die von Balkengröße und Rahmenstil abhängen. Läuft beim Anwenden der Optik
-- und erneut, wenn im Profil "Classic" Breite/Höhe, Rahmen oder Rahmenstärke geändert werden.
local function ClassicLayout(p)
	local s = p.settings
	local width, height = s.healthbar.width or 150, s.healthbar.height or 12
	local top, bottom, left = height / 2, -height / 2, -width / 2
	local gold = p.classicLook.frameStyle == "GOLD"
	-- Unterkante des Rahmens: schlichte Linie bzw. Blizzard-Goldrahmen (falls schon vermessen)
	local borderBottom = bottom - 4
	local art = TidyPlates.BlizzardArt and TidyPlates.BlizzardArt.health
	if gold and art and art.healthborder then
		borderBottom = math.min(bottom, (art.healthborder.bottom - 0.5) * height)
	end

	-- Name gekürzt auf Balkenbreite, beim schlichten Rahmen näher am Balken
	s.name.width = width
	s.name.y = top + (gold and 11 or 10)
	local auraScale = p.debuffWidget.scale or 1.15
	p.debuffWidget.y = (s.name.y + s.name.size / 2 + 2) / auraScale + 9

	-- Lebenspunkte-Text mittig im Balken, Raid-Symbol links neben dem Rahmen
	s.customtext.width = width - 10
	s.raidicon.x = left - 22

	local castHeight, castY
	if gold then
		-- Gold: dünne Leiste direkt unter dem Rahmen, Zaubername klein darunter, kein Symbol
		castHeight = 5
		castY = borderBottom - 1 - castHeight / 2
		s.spelltext.width = width - 30
		s.spelltext.align = "LEFT"
		s.spelltext.x = left + (width - 30) / 2
		s.spelltext.y = castY - castHeight / 2 - 7
		s.spellicon.show = false
	else
		-- Schlicht: Zauberleiste im selben Rahmen wie der Balken, 9 px hoch, Zaubername links
		-- in der Leiste (Restzeit rechts), Zaubersymbol links daneben so hoch wie der Rahmen
		local inset = math.floor((6 + 2 * (p.classicLook.lineSize or 2)) / 3 + 0.5)
		castHeight = 9
		-- direkt unter dem Balkenrahmen; mit Combo-Punkten rückt das Widget die Leiste tiefer
		castY = bottom - inset - 2 - inset - castHeight / 2
		local textWidth = width - 34
		s.spelltext.width = textWidth
		s.spelltext.align = "LEFT"
		s.spelltext.x = left + 3 + textWidth / 2
		s.spelltext.y = castY
		local icon = castHeight + 2 * inset
		s.spellicon.show = true
		s.spellicon.scale = icon
		s.spellicon.x = left - inset - 2 - icon / 2
		s.spellicon.y = castY
	end
	s.castbar.height = castHeight
	s.castbar.y = castY
	s.castborder.y = castY
	s.castnostop.y = castY
end

-- Version 2 (Vorbild Classic-Client): Name auf Balkenbreite gekürzt, Zauberleiste direkt
-- unter dem Rahmen, Zaubername klein, Quest-Symbol an. Auch als Migration verwendet.
local function ApplyClassicV2(p)
	local s = p.settings
	s.spelltext.size = 9
	if p.classicLook.frameStyle ~= "GOLD" then
		s.spelltext.flags = "OUTLINE"
		s.spelltext.shadow = false
	end
	ClassicLayout(p)
	p.questIcon.ON = true
end

-- keepSize: Balkengröße des Profils behalten (Optik zurücksetzen), sonst Ausgangsgröße
local function ApplyClassicLook(p, keepSize)
	local s = p.settings
	p.classicLook.frameStyle = "SIMPLE"
	p.classicLookVersion = CLASSIC_LOOK_VERSION
	p.classicLook.ON = true
	p.platerBorder.ON = false

	-- Threat-Plates-eigene Rahmen, Elite-Symbol und Ziel-Pfeile aus; Rahmen, Drache und
	-- Leuchten kommen vom Classic-Widget
	s.healthborder.show = false
	s.elitehealthborder.show = false
	s.castborder.show = false
	s.castnostop.show = false
	s.threatborder.show = false
	s.eliteicon.show = false
	s.target.texture = "Empty"
	s.highlight.texture = "Empty"
	p.targetWidget.ON = false

	-- Wie bei Plater: konstante Größe, keine Aggro-Zacken, Kick-Farben, Stapeln
	p.threat.useScale = false
	p.threat.art.ON = false
	p.platerCast.ON = true
	p.platerCast.shieldIcon = false -- nicht unterbrechbar zeigt der Blizzard-Schildrahmen
	local c = CLASSIC_CAST_READY
	p.platerCast.colorReady = {r = c.r, g = c.g, b = c.b}
	p.stacking.ON = true

	-- Flache Balkenfüllung, Breite etwas größer als das Original. Höhe im Seitenverhältnis
	-- der Original-Leiste, damit der Rahmen nicht verzerrt (falls schon vermessen).
	s.healthbar.texture = "Flat"
	s.castbar.texture = "Flat"
	if not keepSize then
		local width = 150
		local height = 12
		local art = TidyPlates.BlizzardArt and TidyPlates.BlizzardArt.health
		if art and art.width > 0 then
			height = math.floor(width * art.height / art.width + 0.5)
		end
		s.healthbar.width = width
		s.healthbar.height = height
	end

	-- Schriften wie Blizzard (Friz Quadrata mit Schatten), Lebenspunkte-Text mit Kontur
	for _, key in ipairs({"name", "spelltext", "level"}) do
		s[key].typeface = "Friz Quadrata TT"
		s[key].flags = "NONE"
		s[key].shadow = true
	end
	s.customtext.typeface = "Arial Narrow"
	s.customtext.flags = "OUTLINE"
	s.customtext.shadow = false

	-- Name weiß über dem Rahmen
	s.name.show = true
	s.name.size = 12
	s.name.align = "CENTER"
	s.name.vertical = "CENTER"
	s.name.x = 0

	-- Lebenspunkte-Text mittig im Balken (Format bleibt wie im Default-Profil)
	s.customtext.size = 10
	s.customtext.x = 0
	s.customtext.y = 0
	s.customtext.align = "CENTER"

	-- Stufe: Lage bestimmt das Classic-Widget (Feld im Rahmen)
	s.level.show = true
	s.level.size = 10
	s.level.width = 30

	s.raidicon.scale = 20
	s.raidicon.y = 0

	-- Auren im Plater-Stil mittig über dem Namen
	p.debuffWidget.scale = 1.15
	p.debuffWidget.anchor = "CENTER"
	p.debuffWidget.x = 64 - (3 * 24 + 2 * 2) / 2

	ApplyClassicV2(p)
end

local function ProfileExists(db, name)
	for _, profile in ipairs(db:GetProfiles()) do
		if profile == name then
			return true
		end
	end
	return false
end

-- Nachträge pro Version (Profile ohne Versionsnummer haben Version 1)
local PlaterMigrations = {
	[2] = function(p)
		p.threat.art.ON = false -- keine Aggro-Zacken
	end,
	[3] = function(p)
		p.platerCast.ON = true -- Zauberleiste nach Unterbrechbarkeit färben
	end
}
local ClassicMigrations = {
	[2] = ApplyClassicV2,
	[3] = function(p)
		-- flache Balkenfüllung statt "Blizzard" (oben hell, unten schwarz)
		p.settings.healthbar.texture = "Blizzard Nameplate"
		p.settings.castbar.texture = "Blizzard Nameplate"
	end,
	[4] = function(p)
		-- schlichter Rahmen wie im Classic-Era-Client (Gold bleibt als Option)
		p.classicLook.frameStyle = "SIMPLE"
		ApplyClassicV2(p)
	end,
	-- schlichter Rahmen jetzt als Tooltip-Rahmen (etwas breiter): Name/Zauberleiste nachziehen
	[5] = ApplyClassicV2,
	[6] = function(p)
		-- "Blizzard Nameplate" hat dunkle Streifen oben/unten: komplett flache Füllung
		p.settings.healthbar.texture = "Flat"
		p.settings.castbar.texture = "Flat"
	end,
	-- auffälligere Zauberleiste (Rahmen, Name in der Leiste, Symbol), Combo-Punkte darunter
	[7] = ApplyClassicV2,
	-- Combo-Punkte als Streifen unter dem Balken, Zauberleiste etwas tiefer
	[8] = ApplyClassicV2,
	-- Zauberleiste wieder direkt unter dem Balken (Abstand für Combo-Punkte nur bei Bedarf)
	[9] = ApplyClassicV2,
	-- Cyan für "Kick bereit", nur wenn noch das alte Orange eingestellt ist (eigene Wahl bleibt)
	[10] = function(p)
		local cr = p.platerCast.colorReady
		if cr.r == 1 and cr.g == 0.56 and cr.b == 0.06 then
			local c = CLASSIC_CAST_READY
			p.platerCast.colorReady = {r = c.r, g = c.g, b = c.b}
		end
	end,
	-- Gold wie bei WoW Forever statt Cyan; ersetzt nur einen blauen Farbton (auch selbst
	-- gewähltes Cyan), andere eigene Farben bleiben
	[11] = function(p)
		local cr = p.platerCast.colorReady
		if cr and cr.b > cr.r + 0.3 then
			local c = CLASSIC_CAST_READY
			p.platerCast.colorReady = {r = c.r, g = c.g, b = c.b}
		end
	end
}

-- Eigene Optik-Profile: Name, Anwenden, Version (Feld im Profil) und Nachträge
local Looks = {
	{profile = PLATER_PROFILE, apply = ApplyPlaterLook, version = PLATER_LOOK_VERSION, key = "platerLookVersion", migrations = PlaterMigrations},
	{profile = CLASSIC_PROFILE, apply = ApplyClassicLook, version = CLASSIC_LOOK_VERSION, key = "classicLookVersion", migrations = ClassicMigrations}
}

-- Ist ein Optik-Profil aktiv und älter als die aktuelle Version, nur die neuen Werte ergänzen
function TidyPlatesThreat:UpgradePlaterProfile()
	local db = self.db
	if not db then
		return
	end
	local current = db:GetCurrentProfile()
	for _, look in ipairs(Looks) do
		if current == look.profile then
			local p = db.profile
			local version = p[look.key] or 1
			if version >= look.version then
				return
			end
			for v = version + 1, look.version do
				if look.migrations[v] then
					look.migrations[v](p)
				end
			end
			p[look.key] = look.version
			return true
		end
	end
end

-- Im Profil "Plater" bzw. "Classic" die größenabhängigen Positionen neu berechnen
-- (aus den Optionen bei Änderung von Balkenbreite/-höhe, Rahmen oder Rahmenstärke)
local Layouts = {[PLATER_PROFILE] = PlaterLayout, [CLASSIC_PROFILE] = ClassicLayout}
function TidyPlatesThreat:RelayoutLook()
	local layout = self.db and Layouts[self.db:GetCurrentProfile()]
	if layout then
		layout(self.db.profile)
	end
end

-- Legt die Optik-Profile an, falls sie auf diesem Account noch fehlen (Kopie von
-- "Default" + Optik), ohne den aktuellen Charakter umzustellen. So stehen sie
-- jedem Charakter im Profil-Dropdown zur Auswahl.
function TidyPlatesThreat:EnsurePlaterProfile()
	local db = self.db
	for _, look in ipairs(Looks) do
		if not ProfileExists(db, look.profile) then
			local current = db:GetCurrentProfile()
			self.suppressReloadPrompt = true
			db:SetProfile(look.profile)
			if ProfileExists(db, "Default") then
				db:CopyProfile("Default", true)
			end
			look.apply(db.profile)
			db:SetProfile(current)
			self.suppressReloadPrompt = nil
		end
	end
end

-- /tptpplater bzw. /tptpclassic: Profil aktivieren (beim ersten Mal als Kopie des aktuellen
-- Profils anlegen), "reset" = Optik erneut anwenden, "default" = zurück zum Profil "Default".
-- Wirkt sofort (Stile/Widgets werden neu gebaut, kein /reload nötig).
local function LookCommand(look, command, msg)
	local db = TidyPlatesThreat.db
	msg = strlower(strtrim(msg or ""))
	if msg == "default" then
		db:SetProfile("Default")
		print("|cff89F559Threat Plates|r: " .. L["Profile \"Default\" active."])
		return
	end

	local current = db:GetCurrentProfile()
	local isNew = not ProfileExists(db, look.profile)
	if current ~= look.profile then
		db:SetProfile(look.profile)
		if isNew then
			db:CopyProfile(current)
		end
	end
	if isNew or msg == "reset" then
		-- reset behält die eigene Balkengröße
		look.apply(db.profile, not isNew)
		TidyPlatesThreat:ApplyProfileLive() -- Optik wurde nach dem Profilwechsel geändert
	end
	print("|cff89F559Threat Plates|r: " .. format(L["Profile \"%s\" active (back with %s default)."], look.profile, command))
end

SLASH_TPTPPLATER1 = "/tptpplater"
SlashCmdList["TPTPPLATER"] = function(msg)
	LookCommand(Looks[1], "/tptpplater", msg)
end

-- Vermessung der Original-Plakette ausgeben (zum Feinjustieren der Classic-Optik)
local function PrintClassicInfo()
	local art = TidyPlates.BlizzardArt
	if not art then
		print("|cff89F559Threat Plates|r: " .. L["No nameplate measured yet."])
		return
	end
	local function rect(r)
		return r and format("L %.2f R %.2f O %.2f U %.2f", r.left, r.right, r.top, r.bottom) or "-"
	end
	local h, c = art.health, art.cast
	print(format(L["|cff89F559Classic|r bar %s, level at point %s"], h and format("%.1f x %.1f", h.width, h.height) or L["not measured"], tostring(art.levelPoint)))
	if h then
		for _, key in ipairs({"healthborder", "threatglow", "highlight", "eliteicon", "skullicon", "level"}) do
			print("  " .. key .. ": " .. rect(h[key]) .. "  " .. tostring(art[key] and art[key].texture or ""))
		end
	end
	print("  " .. L["Castbar"] .. " " .. (c and format("%.1f x %.1f", c.width, c.height) or L["not measured"]))
	if c then
		for _, key in ipairs({"castborder", "castnostop", "spellicon"}) do
			print("  " .. key .. ": " .. rect(c[key]) .. "  " .. tostring(art[key] and art[key].texture or ""))
		end
	end
end

SLASH_TPTPCLASSIC1 = "/tptpclassic"
SlashCmdList["TPTPCLASSIC"] = function(msg)
	if strlower(strtrim(msg or "")) == "info" then
		PrintClassicInfo()
		return
	end
	LookCommand(Looks[2], "/tptpclassic", msg)
end
