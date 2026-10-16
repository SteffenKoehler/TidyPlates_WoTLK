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

--[[Plater look as a separate profile]] --
-- /tptpplater          activate profile "Plater" (created as a copy of the current profile the first time)
-- /tptpplater reset    re-apply the Plater look in profile "Plater"
-- /tptpplater default  back to profile "Default"
-- /tptpclassic [reset|default|info]  same for the Classic look (profile "Classic", further below)
-- Takes effect immediately: styles and widgets are rebuilt on profile switch (ApplyProfileLive).
local PLATER_PROFILE = "Plater"
-- Version of the Plater look. When new settings are added: bump the version and add only
-- the new values in PlaterMigrations below. Existing Plater profiles are then
-- updated on login or when switching to the profile, without overwriting
-- custom adjustments (no /tptpplater reset needed).
local PLATER_LOOK_VERSION = 3

-- Positions that depend on the bar size. Runs when the look is applied and again
-- when width/height is changed in profile "Plater"; font sizes etc. stay untouched.
local function PlaterLayout(p)
	local s = p.settings
	local width, height = s.healthbar.width or 170, s.healthbar.height or 18
	local top, bottom, left, right = height / 2, -height / 2, -width / 2, width / 2

	-- castbar below the bar; it covers the name while casting
	local castHeight = s.castbar.height or 16
	local castY = bottom - 2 - castHeight / 2
	s.castbar.y = castY
	s.castborder.y = castY
	s.castnostop.y = castY

	-- Name below the bar, full width, so long names are not truncated as early
	s.name.width = width
	s.name.y = castY

	-- Health text centered in the bar
	s.customtext.width = width - 10

	-- Spell name on the left of the castbar (remaining time on the right), icon to its left
	local spellWidth = width - 40
	s.spelltext.width = spellWidth
	s.spelltext.x = left + 3 + spellWidth / 2
	s.spelltext.y = castY
	s.spellicon.scale = castHeight
	s.spellicon.x = left - castHeight / 2 - 2
	s.spellicon.y = castY

	-- Level small above the top right corner
	s.level.x = right - 15
	s.level.y = top + 6

	-- Raid marker to the left of the bar
	s.raidicon.x = left - (s.raidicon.scale or 20) / 2 - 3
	s.raidicon.y = 0

	-- Auras directly above the bar (offset is multiplied by the widget's scale)
	local auraScale = p.debuffWidget.scale or 1.15
	p.debuffWidget.y = (top + 3) / auraScale + 9
end

-- keepSize: keep the profile's bar size (look reset), otherwise default size
local function ApplyPlaterLook(p, keepSize)
	local s = p.settings
	p.platerLookVersion = PLATER_LOOK_VERSION
	p.platerBorder.ON = true
	p.platerBorder.size = 1

	-- Scaled border textures off, the crisp border replaces them
	s.healthborder.show = false
	s.elitehealthborder.show = false
	s.castborder.show = false
	s.castnostop.show = false
	s.threatborder.show = false
	-- Target/mouseover: white/gray via the border instead of glow texture (arrows stay)
	s.target.texture = "Empty"
	s.highlight.texture = "Empty"

	-- Health text "4.3k (100%)"
	p.text.parens = true

	-- Constant size like Plater: aggro only via color, not via size
	-- (otherwise normal mobs shrink by 20 % in combat and depending on threat level)
	p.threat.useScale = false
	-- No threat spikes around the nameplate: the bar color already carries the information,
	-- and with tank view on DPS/healers they would otherwise warn on every tanked mob
	p.threat.art.ON = false
	-- Color castbar by interruptibility
	p.platerCast.ON = true

	-- Stack nameplates (replaces the WeakAura "Enhanced Stacking Nameplate")
	p.stacking.ON = true

	-- Plain font with outline
	for _, key in ipairs({"name", "customtext", "spelltext", "level"}) do
		s[key].typeface = "Arial Narrow"
		s[key].flags = "OUTLINE"
		s[key].shadow = false
	end

	-- Slightly larger than before (150x15), castbar takes over the width
	if not keepSize then
		s.healthbar.width = 170
		s.healthbar.height = 18
	end

	-- Castbar as tall as the name
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

	-- Raid marker to the left of the bar (auras now sit above it)
	s.raidicon.scale = 20

	-- Auras centered (3 icons of 24 px + 2 px spacing)
	p.debuffWidget.scale = 1.15
	p.debuffWidget.anchor = "CENTER"
	p.debuffWidget.x = 64 - (3 * 24 + 2 * 2) / 2 -- widget is 128 wide, icons start on the left

	PlaterLayout(p)
end

-- Classic look: original Blizzard textures (gold border with level box) via the
-- Classic widget, name above the bar, health text as in the Default profile.
-- Same versioning rule as for Plater (CLASSIC_LOOK_VERSION + ClassicMigrations).
local CLASSIC_PROFILE = "Classic"
local CLASSIC_LOOK_VERSION = 22

-- Castbar "interruptible, kick ready" in gold like WoW Forever (mid tone of
-- its light-to-dark gradient bar; previously cyan)
local CLASSIC_CAST_READY = {r = 1, g = 0.8, b = 0.2}

-- Target glow in the Blizzard UI gold
local CLASSIC_GLOW = {r = 1, g = 0.82, b = 0, a = 0.9}

-- Positions that depend on bar size and border style. Runs when the look is applied
-- and again when width/height, border or border thickness is changed in profile "Classic".
-- Forever values: name 2 above
-- the bar (Modern) or 4 above it (Classic), castbar 2 (Modern) / 4 (Classic) below.
local function ClassicLayout(p)
	local s = p.settings
	local width, height = s.healthbar.width or 150, s.healthbar.height or 12
	local top, bottom, left = height / 2, -height / 2, -width / 2
	local style = p.classicLook.frameStyle
	local gold = style == "GOLD"
	local modern = style == "MODERN"
	-- Edges of the border: plain line or Blizzard gold border (if already measured)
	local borderBottom = bottom - 4
	local art = TidyPlates.BlizzardArt and TidyPlates.BlizzardArt.health
	if gold and art and art.healthborder then
		borderBottom = math.min(bottom, (art.healthborder.bottom - 0.5) * height)
	end
	local auraScale = p.debuffWidget.scale or 1.15

	-- Name truncated to the frame width
	local nameSize = s.name.size or 12
	if modern then
		-- Forever Modern: level box to the right of the bar, name across bar + box; the gap
		-- grows with the target line (Widgets.lua: MODERN_BOX_GAP x line scale)
		local k = height / 13
		local lineScale = math.floor((p.classicLook.modernLineScale or 1) * 4 + 0.5) / 4
		local boxW, gap = math.floor(24 * k + 0.5), 4 * lineScale * k
		s.name.width = width + gap + boxW
		s.name.x = (gap + boxW) / 2
		s.name.y = top + 2 + nameSize / 2
		-- auras left-aligned with the bar (the widget is 128 wide, icons start on its left)
		p.debuffWidget.x = left / auraScale + 64
	else
		s.name.width = width
		s.name.x = 0
		s.name.y = gold and (top + 4 + nameSize / 2) or (top + 10)
		p.debuffWidget.x = 64 - (3 * 24 + 2 * 2) / 2
	end
	p.debuffWidget.y = (s.name.y + nameSize / 2 + 2) / auraScale + 9

	-- Health text in the bar, raid marker to the left of the border
	s.customtext.width = width - 8
	s.customtext.x = 0
	s.raidicon.x = left - 22

	local castHeight, castY
	if modern then
		-- Forever Modern: 6 high bar 4 below the health bar, as wide as bar + level box;
		-- icon (10) and spell name (10) below it on the left, remaining time on the right.
		-- The widget anchors these again on every cast (combo points move it lower).
		local k = height / 13
		local lineScale = math.floor((p.classicLook.modernLineScale or 1) * 4 + 0.5) / 4
		local boxW, gap = math.floor(24 * k + 0.5), 4 * lineScale * k
		local full = width + gap + boxW
		castHeight = math.max(4, math.floor(6 * k + 0.5))
		-- 2 + line width below the bar (Widgets.lua: MODERN_CAST_GAP)
		castY = bottom - (2 + 2 * lineScale) * k - castHeight / 2
		local icon = math.floor(10 * k + 0.5)
		local textY = castY - castHeight / 2 - 2 - icon / 2
		local textWidth = full - icon - 2 - 30
		s.spelltext.width = textWidth
		s.spelltext.align = "LEFT"
		s.spelltext.x = left + icon + 2 + textWidth / 2
		s.spelltext.y = textY
		s.spellicon.show = true
		s.spellicon.scale = icon
		s.spellicon.x = left + icon / 2
		s.spellicon.y = textY
	elseif gold and p.classicLook.castBorder then
		-- Forever Classic: castbar as tall and wide as the health bar in the Blizzard castbar
		-- border, 4 below the health border; spell name centered inside, icon from the border art
		castHeight = height
		local pad = 3
		local cast = TidyPlates.BlizzardArt and TidyPlates.BlizzardArt.cast
		if cast and cast.castborder then
			pad = math.max(0, (cast.castborder.top - 1) * castHeight)
		end
		castY = borderBottom - 4 - pad - castHeight / 2
		s.spelltext.width = width - 10
		s.spelltext.align = "CENTER"
		s.spelltext.x = 0
		s.spelltext.y = castY
		s.spellicon.show = true
	elseif gold then
		-- Gold: thin bar directly below the border, small spell name below it, no icon
		castHeight = 5
		castY = borderBottom - 1 - castHeight / 2
		s.spelltext.width = width - 30
		s.spelltext.align = "LEFT"
		s.spelltext.x = left + (width - 30) / 2
		s.spelltext.y = castY - castHeight / 2 - 7
		s.spellicon.show = false
	else
		-- Plain: castbar in the same border as the bar, 9 px tall, spell name on the left
		-- inside the bar (remaining time on the right), spell icon to its left as tall as the border
		local _, inset = ThreatPlatesWidgets.ClassicSimpleEdge(p.classicLook.lineSize)
		castHeight = 9
		-- directly below the bar border; with combo points the widget moves the castbar lower
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

-- Sizes, fonts and fills per border style. Switching the style sets these (the user's
-- choice: dimensions change along with the style).
local FRAME_STYLES = {
	-- Forever Modern: 190 wide nameplate minus 2 x 12 inset and the level box (28 + 5)
	-- = 133 x 13 bar; name Friz Quadrata 12, health text 10 (both outlined), health text right in the bar
	MODERN = {width = 133, height = 13, nameSize = 12, outline = true, textSize = 10, textFont = "Friz Quadrata TT", textAlign = "RIGHT", spellSize = 10, texture = "Forever", castTexture = "Forever Cast", castBorder = false},
	-- Forever Classic: classic gold border 128 x 16 around a 104 x 10 bar,
	-- name and health text 10, castbar in the classic castbar border
	GOLD = {width = 104, height = 10, nameSize = 10, textSize = 10, textFont = "Arial Narrow", textAlign = "CENTER", spellSize = 10, texture = "Blizzard Nameplate", castTexture = "Blizzard Nameplate", castBorder = true},
	-- simple tooltip border (the look before the Forever styles)
	SIMPLE = {width = 150, height = 12, nameSize = 12, textSize = 10, textFont = "Arial Narrow", textAlign = "CENTER", spellSize = 9, texture = "Flat", castTexture = "Flat", castBorder = false},
}

-- keepSize: keep the profile's bar size (look reset)
local function ApplyClassicFrameStyle(p, style, keepSize)
	local d = FRAME_STYLES[style]
	if not d then
		style, d = "MODERN", FRAME_STYLES.MODERN
	end
	local s = p.settings
	p.classicLook.frameStyle = style
	p.classicLook.castBorder = d.castBorder
	if not keepSize then
		local height = d.height
		-- gold: keep the aspect ratio of the measured original bar so the border is not distorted
		local art = TidyPlates.BlizzardArt and TidyPlates.BlizzardArt.health
		if style ~= "MODERN" and art and art.width > 0 then
			height = math.floor(d.width * art.height / art.width + 0.5)
		end
		s.healthbar.width = d.width
		s.healthbar.height = height
	end
	s.healthbar.texture = d.texture
	s.castbar.texture = d.castTexture
	s.name.size = d.nameSize
	s.name.flags = d.outline and "OUTLINE" or "NONE"
	s.name.shadow = not d.outline
	s.customtext.typeface = d.textFont
	s.customtext.flags = "OUTLINE"
	s.customtext.shadow = false
	s.customtext.size = d.textSize
	s.customtext.align = d.textAlign
	s.spelltext.size = d.spellSize
	ClassicLayout(p)
end

-- Version 2 (modeled on the Classic client): name truncated to bar width, castbar directly
-- below the border, small spell name, quest icon on. Also used as a migration.
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

-- keepSize: keep the profile's bar size (look reset), otherwise default size
local function ApplyClassicLook(p, keepSize)
	local s = p.settings
	-- reset keeps the chosen border style, new profiles start with Forever Modern
	local style = keepSize and p.classicLook.frameStyle or "MODERN"
	p.classicLook.frameStyle = "SIMPLE"
	p.classicLookVersion = CLASSIC_LOOK_VERSION
	p.classicLook.ON = true
	p.classicLook.lineSize = 1
	p.classicLook.targetGlow = true
	p.classicLook.glowSize = 5
	p.classicLook.glowColor = {r = CLASSIC_GLOW.r, g = CLASSIC_GLOW.g, b = CLASSIC_GLOW.b, a = CLASSIC_GLOW.a}
	p.platerBorder.ON = false

	-- Threat Plates' own borders, elite icon and target arrows off; border, dragon and
	-- glow come from the Classic widget
	s.healthborder.show = false
	s.elitehealthborder.show = false
	s.castborder.show = false
	s.castnostop.show = false
	s.threatborder.show = false
	s.eliteicon.show = false
	s.target.texture = "Empty"
	s.highlight.texture = "Empty"
	p.targetWidget.ON = false

	-- Like Plater: constant size, no threat spikes, kick colors, stacking
	p.threat.useScale = false
	p.threat.art.ON = false
	p.platerCast.ON = true
	p.platerCast.shieldIcon = false -- non-interruptible is shown by the Blizzard shield border
	local c = CLASSIC_CAST_READY
	p.platerCast.colorReady = {r = c.r, g = c.g, b = c.b}
	p.stacking.ON = true

	-- Flat bar fill, width slightly larger than the original. Height keeps the aspect ratio
	-- of the original bar so the border is not distorted (if already measured).
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

	-- Fonts like Blizzard (Friz Quadrata with shadow), health text with outline
	for _, key in ipairs({"name", "spelltext", "level"}) do
		s[key].typeface = "Friz Quadrata TT"
		s[key].flags = "NONE"
		s[key].shadow = true
	end
	s.customtext.typeface = "Arial Narrow"
	s.customtext.flags = "OUTLINE"
	s.customtext.shadow = false

	-- Name in white above the border
	s.name.show = true
	s.name.size = 12
	s.name.align = "CENTER"
	s.name.vertical = "CENTER"
	s.name.x = 0

	-- Health text centered in the bar (format stays as in the Default profile)
	s.customtext.size = 10
	s.customtext.x = 0
	s.customtext.y = 0
	s.customtext.align = "CENTER"

	-- Level: position is set by the Classic widget (level box in the border)
	s.level.show = true
	s.level.size = 10
	s.level.width = 30

	s.raidicon.scale = 20
	s.raidicon.y = 0

	-- Plater-style auras centered above the name
	p.debuffWidget.scale = 1.15
	p.debuffWidget.anchor = "CENTER"
	p.debuffWidget.x = 64 - (3 * 24 + 2 * 2) / 2

	ApplyClassicV2(p)
	ApplyClassicFrameStyle(p, style, keepSize)
end

local function ProfileExists(db, name)
	for _, profile in ipairs(db:GetProfiles()) do
		if profile == name then
			return true
		end
	end
	return false
end

-- Additions per version (profiles without a version number are version 1)
local PlaterMigrations = {
	[2] = function(p)
		p.threat.art.ON = false -- no threat spikes
	end,
	[3] = function(p)
		p.platerCast.ON = true -- color castbar by interruptibility
	end
}
local ClassicMigrations = {
	[2] = ApplyClassicV2,
	[3] = function(p)
		-- flat bar fill instead of "Blizzard" (light at the top, black at the bottom)
		p.settings.healthbar.texture = "Blizzard Nameplate"
		p.settings.castbar.texture = "Blizzard Nameplate"
	end,
	[4] = function(p)
		-- plain border like in the Classic Era client (gold remains an option)
		p.classicLook.frameStyle = "SIMPLE"
		ApplyClassicV2(p)
	end,
	-- plain border now a tooltip border (slightly wider): adjust name/castbar to match
	[5] = ApplyClassicV2,
	[6] = function(p)
		-- "Blizzard Nameplate" has dark stripes at top/bottom: completely flat fill
		p.settings.healthbar.texture = "Flat"
		p.settings.castbar.texture = "Flat"
	end,
	-- more prominent castbar (border, name inside the bar, icon), combo points below it
	[7] = ApplyClassicV2,
	-- combo points as a strip below the bar, castbar slightly lower
	[8] = ApplyClassicV2,
	-- castbar directly below the bar again (gap for combo points only when needed)
	[9] = ApplyClassicV2,
	-- cyan for "kick ready", only if the old orange is still set (custom choice is kept)
	[10] = function(p)
		local cr = p.platerCast.colorReady
		if cr.r == 1 and cr.g == 0.56 and cr.b == 0.06 then
			local c = CLASSIC_CAST_READY
			p.platerCast.colorReady = {r = c.r, g = c.g, b = c.b}
		end
	end,
	-- gold like WoW Forever instead of cyan; replaces only a blue hue (including
	-- self-chosen cyan), other custom colors are kept
	[11] = function(p)
		local cr = p.platerCast.colorReady
		if cr and cr.b > cr.r + 0.3 then
			local c = CLASSIC_CAST_READY
			p.platerCast.colorReady = {r = c.r, g = c.g, b = c.b}
		end
	end,
	-- back to the thin border (version 12 had doubled it): relayout
	[12] = ClassicLayout,
	[13] = ClassicLayout,
	-- soft golden glow around the target's border
	[14] = function(p)
		p.classicLook.targetGlow = true
	end,
	-- glow in the Blizzard UI gold
	[15] = function(p)
		local c = CLASSIC_GLOW
		p.classicLook.glowColor = {r = c.r, g = c.g, b = c.b, a = c.a}
	end,
	-- Forever spacing of name and castbar (the style itself stays as chosen)
	[16] = ClassicLayout,
	-- Forever Modern: health text in Friz Quadrata with outline like the name (Forever's font)
	[17] = function(p)
		if p.classicLook.frameStyle == "MODERN" then
			local t = p.settings.customtext
			t.typeface = "Friz Quadrata TT"
			t.flags = "OUTLINE"
			t.shadow = false
		end
	end,
	-- Forever Modern: health text 12 (14 touched the bar edges), level box 3 instead of 5 from the bar
	[18] = function(p)
		if p.classicLook.frameStyle == "MODERN" then
			p.settings.customtext.size = 12
		end
		ClassicLayout(p)
	end,
	-- Forever Modern: level box measured at its gold rim (24 wide instead of 28)
	[19] = ClassicLayout,
	-- Forever Modern: level box 4 from the bar (3 let the target lines merge)
	[20] = ClassicLayout,
	-- Forever Modern: castbar 4 below the bar (2 let the target line touch the kick line)
	[21] = ClassicLayout,
	-- Forever Modern: name 12 and health text 10 (14/12 looked too big); glow stays on
	-- (its switch and size now apply to this style as well)
	[22] = function(p)
		if p.classicLook.frameStyle == "MODERN" then
			p.settings.name.size = 12
			p.settings.customtext.size = 10
			p.classicLook.targetGlow = true
		end
		ClassicLayout(p)
	end
}

-- Custom look profiles: name, apply, version (field in the profile) and migrations
local Looks = {
	{profile = PLATER_PROFILE, apply = ApplyPlaterLook, version = PLATER_LOOK_VERSION, key = "platerLookVersion", migrations = PlaterMigrations},
	{profile = CLASSIC_PROFILE, apply = ApplyClassicLook, version = CLASSIC_LOOK_VERSION, key = "classicLookVersion", migrations = ClassicMigrations}
}

-- If a look profile is active and older than the current version, add only the new values
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

-- Recalculate the size-dependent positions in profile "Plater" or "Classic"
-- (from the options when bar width/height, border or border thickness changes)
local Layouts = {[PLATER_PROFILE] = PlaterLayout, [CLASSIC_PROFILE] = ClassicLayout}
function TidyPlatesThreat:RelayoutLook()
	local layout = self.db and Layouts[self.db:GetCurrentProfile()]
	if layout then
		layout(self.db.profile)
	end
end

-- Border style of the Classic look changed in the options: sizes, fonts and fills of the
-- style (Forever Modern / Forever Classic / simple) are set together with it
function TidyPlatesThreat:SetClassicFrameStyle(style)
	ApplyClassicFrameStyle(self.db.profile, style)
end

-- Creates the look profiles if they are still missing on this account (copy of
-- "Default" + look), without switching the current character. This makes them
-- available to every character in the profile dropdown.
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

-- /tptpplater or /tptpclassic: activate profile (created as a copy of the current
-- profile the first time), "reset" = re-apply look, "default" = back to profile "Default".
-- Takes effect immediately (styles/widgets are rebuilt, no /reload needed).
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
		-- reset keeps the custom bar size
		look.apply(db.profile, not isNew)
		TidyPlatesThreat:ApplyProfileLive() -- look was changed after the profile switch
	end
	print("|cff89F559Threat Plates|r: " .. format(L["Profile \"%s\" active (back with %s default)."], look.profile, command))
end

SLASH_TPTPPLATER1 = "/tptpplater"
SlashCmdList["TPTPPLATER"] = function(msg)
	LookCommand(Looks[1], "/tptpplater", msg)
end

-- Print measurements of the original nameplate (for fine-tuning the Classic look)
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
