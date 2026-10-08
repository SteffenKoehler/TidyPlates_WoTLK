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
-- Stile werden nur beim Laden gebaut, daher jeweils /reload.
local PLATER_PROFILE = "Plater"
-- Version der Plater-Optik. Kommen neue Einstellungen dazu: Version erhöhen und unten
-- in PlaterMigrations nur die neuen Werte nachtragen. Bestehende Plater-Profile werden
-- dann beim Einloggen bzw. beim Wechsel ins Profil ergänzt, ohne eigene Anpassungen
-- zu überschreiben (kein /tptpplater reset nötig).
local PLATER_LOOK_VERSION = 3

local function ApplyPlaterLook(p)
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
	s.healthbar.width = 170
	s.healthbar.height = 18
	local height = s.healthbar.height
	local width = s.healthbar.width
	local top, bottom, left, right = height / 2, -height / 2, -width / 2, width / 2

	-- Zauberleiste unter dem Balken, so hoch wie der Name; sie überdeckt beim Zaubern den Namen
	local castHeight = 16
	local castY = bottom - 2 - castHeight / 2
	s.castbar.height = castHeight
	s.castbar.y = castY
	s.castborder.y = castY
	s.castnostop.y = castY

	-- Name unter dem Balken
	s.name.size = 13
	s.name.width = width -- volle Breite, damit lange Namen nicht so früh abgeschnitten werden
	s.name.y = castY
	s.name.align = "CENTER"

	-- Lebenspunkte-Text mittig im Balken
	s.customtext.size = 12
	s.customtext.width = width - 10
	s.customtext.x = 0
	s.customtext.y = 0
	s.customtext.align = "CENTER"

	-- Zaubername links in der Zauberleiste (rechts steht die Restzeit), Symbol links daneben
	local spellWidth = width - 40
	s.spelltext.size = 11
	s.spelltext.width = spellWidth
	s.spelltext.align = "LEFT"
	s.spelltext.x = left + 3 + spellWidth / 2
	s.spelltext.y = castY
	s.spellicon.scale = castHeight
	s.spellicon.x = left - castHeight / 2 - 2
	s.spellicon.y = castY

	-- Stufe klein über der rechten oberen Ecke
	s.level.show = true
	s.level.size = 10
	s.level.width = 30
	s.level.align = "RIGHT"
	s.level.vertical = "CENTER"
	s.level.x = right - 15
	s.level.y = top + 6

	-- Raid-Symbol links neben dem Balken (darüber sitzen jetzt die Auren)
	s.raidicon.scale = 20
	s.raidicon.x = left - 13
	s.raidicon.y = 0

	-- Auren direkt über dem Balken, mittig (3 Symbole à 24 px + 2 px Abstand).
	-- Versatz wird mit der Skalierung des Widgets multipliziert, daher umgerechnet.
	local auraScale = 1.15
	p.debuffWidget.scale = auraScale
	p.debuffWidget.anchor = "CENTER"
	p.debuffWidget.x = 64 - (3 * 24 + 2 * 2) / 2 -- Widget ist 128 breit, Symbole beginnen links
	p.debuffWidget.y = (top + 3) / auraScale + 9
end

-- Classic-Optik: originale Blizzard-Grafiken (Goldrahmen mit Stufen-Feld) über dem
-- Classic-Widget, Name über dem Balken, Lebenspunkte-Text wie im Default-Profil.
-- Gleiche Versionsregel wie bei Plater (CLASSIC_LOOK_VERSION + ClassicMigrations).
local CLASSIC_PROFILE = "Classic"
local CLASSIC_LOOK_VERSION = 2

-- Version 2 (Vorbild Classic-Client): Name auf Balkenbreite gekürzt, dünne orange Zauber-
-- leiste direkt unter dem Rahmen, Zaubername klein links darunter (Restzeit rechts), kein
-- Zaubersymbol, Quest-Symbol an. Rahmenfarbe/Größen kommen aus den classicLook-Vorgaben.
local function ApplyClassicV2(p)
	local s = p.settings
	local width, height = s.healthbar.width or 150, s.healthbar.height or 12
	local bottom, left = -height / 2, -width / 2
	-- Unterkante des Blizzard-Rahmens, falls schon vermessen
	local borderBottom = bottom - 4
	local art = TidyPlates.BlizzardArt and TidyPlates.BlizzardArt.health
	if art and art.healthborder then
		borderBottom = math.min(bottom, (art.healthborder.bottom - 0.5) * height)
	end

	s.name.width = width

	local castHeight = 5
	local castY = borderBottom - 1 - castHeight / 2
	s.castbar.height = castHeight
	s.castbar.y = castY
	s.castborder.y = castY
	s.castnostop.y = castY
	s.spelltext.size = 9
	s.spelltext.width = width - 30
	s.spelltext.align = "LEFT"
	s.spelltext.x = left + (width - 30) / 2
	s.spelltext.y = castY - castHeight / 2 - 7
	s.spellicon.show = false

	p.questIcon.ON = true
end

local function ApplyClassicLook(p)
	local s = p.settings
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
	p.stacking.ON = true

	-- Blizzard-Balkengrafik, Breite etwas größer als das Original. Höhe im Seitenverhältnis
	-- der Original-Leiste, damit der Rahmen nicht verzerrt (falls schon vermessen).
	s.healthbar.texture = "Blizzard"
	s.castbar.texture = "Blizzard"
	local width = 150
	local height = 12
	local art = TidyPlates.BlizzardArt and TidyPlates.BlizzardArt.health
	if art and art.width > 0 then
		height = math.floor(width * art.height / art.width + 0.5)
	end
	s.healthbar.width = width
	s.healthbar.height = height
	local top, bottom, left = height / 2, -height / 2, -width / 2

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
	s.name.width = width + 30
	s.name.align = "CENTER"
	s.name.vertical = "CENTER"
	s.name.x = 0
	s.name.y = top + 11

	-- Lebenspunkte-Text mittig im Balken (Format bleibt wie im Default-Profil)
	s.customtext.size = 10
	s.customtext.width = width - 10
	s.customtext.x = 0
	s.customtext.y = 0
	s.customtext.align = "CENTER"

	-- Stufe: Lage bestimmt das Classic-Widget (Feld im Rahmen)
	s.level.show = true
	s.level.size = 10
	s.level.width = 30

	-- Zauberleiste unter dem Balken, Zaubername mittig, Symbol links (das Widget setzt
	-- Rahmen und Symbol an Blizzards Platz, sobald die Zauberleiste vermessen ist)
	local castHeight = height
	local castY = bottom - 8 - castHeight / 2
	s.castbar.height = castHeight
	s.castbar.y = castY
	s.castborder.y = castY
	s.castnostop.y = castY
	s.spelltext.size = 9
	s.spelltext.width = width - 40
	s.spelltext.align = "CENTER"
	s.spelltext.x = 0
	s.spelltext.y = castY
	s.spellicon.scale = castHeight + 6
	s.spellicon.x = left - castHeight / 2 - 5
	s.spellicon.y = castY
	s.spellicon.show = true

	-- Raid-Symbol links neben dem Rahmen
	s.raidicon.scale = 20
	s.raidicon.x = left - 22
	s.raidicon.y = 0

	-- Auren im Plater-Stil mittig über dem Namen
	local auraScale = 1.15
	local nameTop = s.name.y + s.name.size / 2
	p.debuffWidget.scale = auraScale
	p.debuffWidget.anchor = "CENTER"
	p.debuffWidget.x = 64 - (3 * 24 + 2 * 2) / 2
	p.debuffWidget.y = (nameTop + 2) / auraScale + 9

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
	[2] = ApplyClassicV2
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
-- Stile werden nur beim Laden gebaut, daher jeweils /reload.
local function LookCommand(look, command, msg)
	local db = TidyPlatesThreat.db
	msg = strlower(strtrim(msg or ""))
	TidyPlatesThreat.suppressReloadPrompt = true -- lädt am Ende ohnehin neu
	if msg == "default" then
		db:SetProfile("Default")
		print("|cff89F559Threat Plates|r: Profil \"Default\" aktiv, lade neu ...")
		ReloadUI()
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
		look.apply(db.profile)
	end
	print("|cff89F559Threat Plates|r: Profil \"" .. look.profile .. "\" aktiv, lade neu ... (zurück mit " .. command .. " default)")
	ReloadUI()
end

SLASH_TPTPPLATER1 = "/tptpplater"
SlashCmdList["TPTPPLATER"] = function(msg)
	LookCommand(Looks[1], "/tptpplater", msg)
end

-- Vermessung der Original-Plakette ausgeben (zum Feinjustieren der Classic-Optik)
local function PrintClassicInfo()
	local art = TidyPlates.BlizzardArt
	if not art then
		print("|cff89F559Threat Plates|r: Noch keine Plakette vermessen.")
		return
	end
	local function rect(r)
		return r and format("L %.2f R %.2f O %.2f U %.2f", r.left, r.right, r.top, r.bottom) or "-"
	end
	local h, c = art.health, art.cast
	print(format("|cff89F559Classic|r Leiste %s, Stufe am Punkt %s", h and format("%.1f x %.1f", h.width, h.height) or "nicht vermessen", tostring(art.levelPoint)))
	if h then
		for _, key in ipairs({"healthborder", "threatglow", "highlight", "eliteicon", "skullicon", "level"}) do
			print("  " .. key .. ": " .. rect(h[key]) .. "  " .. tostring(art[key] and art[key].texture or ""))
		end
	end
	print("  Zauberleiste " .. (c and format("%.1f x %.1f", c.width, c.height) or "nicht vermessen"))
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
