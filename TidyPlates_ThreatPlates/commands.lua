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
-- Stile werden nur beim Laden gebaut, daher jeweils /reload.
local PLATER_PROFILE = "Plater"

local function ApplyPlaterLook(p)
	local s = p.settings
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

local function ProfileExists(db, name)
	for _, profile in ipairs(db:GetProfiles()) do
		if profile == name then
			return true
		end
	end
	return false
end

-- Legt das Profil "Plater" an, falls es auf diesem Account noch fehlt (Kopie von
-- "Default" + Plater-Look), ohne den aktuellen Charakter umzustellen. So steht es
-- jedem Charakter im Profil-Dropdown zur Auswahl.
function TidyPlatesThreat:EnsurePlaterProfile()
	local db = self.db
	if ProfileExists(db, PLATER_PROFILE) then
		return
	end
	local current = db:GetCurrentProfile()
	self.suppressReloadPrompt = true
	db:SetProfile(PLATER_PROFILE)
	if ProfileExists(db, "Default") then
		db:CopyProfile("Default", true)
	end
	ApplyPlaterLook(db.profile)
	db:SetProfile(current)
	self.suppressReloadPrompt = nil
end

local function TPTPPLATER(msg)
	local db = TidyPlatesThreat.db
	msg = strlower(strtrim(msg or ""))
	if msg == "default" then
		TidyPlatesThreat.suppressReloadPrompt = true -- lädt am Ende ohnehin neu
		db:SetProfile("Default")
		print("|cff89F559Threat Plates|r: Profil \"Default\" aktiv, lade neu ...")
		ReloadUI()
		return
	end

	TidyPlatesThreat.suppressReloadPrompt = true -- lädt am Ende ohnehin neu
	local current = db:GetCurrentProfile()
	local isNew = not ProfileExists(db, PLATER_PROFILE)
	if current ~= PLATER_PROFILE then
		db:SetProfile(PLATER_PROFILE)
		if isNew then
			db:CopyProfile(current)
		end
	end
	if isNew or msg == "reset" then
		ApplyPlaterLook(db.profile)
	end
	print("|cff89F559Threat Plates|r: Profil \"Plater\" aktiv, lade neu ... (zurück mit /tptpplater default)")
	ReloadUI()
end
SLASH_TPTPPLATER1 = "/tptpplater"
SlashCmdList["TPTPPLATER"] = TPTPPLATER
