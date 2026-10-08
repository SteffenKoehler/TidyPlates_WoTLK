-- Tidy Plates - Dedicated to the loves-of-my-life..
--------------------------------------------------------------------------------------------------------------
-- I. Variables and Functions
--------------------------------------------------------------------------------------------------------------
local addonName, TidyPlates = ...
_G.TidyPlates = TidyPlates

-- Stelle sicher, dass TidyPlatesData immer existiert (auch vor ADDON_LOADED)
TidyPlatesData = TidyPlatesData or {}

-- Merkt sich pro Zauber(name), ob er unterbrechbar ist. Verlässlich weiß der Client das
-- nur beim Ziel und Mouseover; gespeichert gilt es dann auch für Nicht-Ziel-Zauberleisten
-- (über das Kampflog ist die Information nicht verfügbar).
local function LearnCastShield(spell, notInterruptible)
	if not spell then
		return
	end
	local known = TidyPlatesData.CastShield
	if not known then
		known = {}
		TidyPlatesData.CastShield = known
	end
	known[spell] = notInterruptible and true or false
end

TidyPlates.callbacks = TidyPlates.callbacks or LibStub("CallbackHandler-1.0"):New(TidyPlates)

local _
local numChildren = -1
local activetheme = {}

local weaktable = {__mode = "k"}

-- TODO: keep an eye on weaktable and revert if they cause issues
local massQueue = setmetatable({}, weaktable)
local functionQueue = setmetatable({}, weaktable)
local targetQueue = setmetatable({}, weaktable)
-- Eigene Warteschlangen, damit während der Abarbeitung von targetQueue keine neuen
-- Schlüssel in dieselbe Tabelle geschrieben werden (in Lua bei pairs() undefiniert)
local healthQueue = setmetatable({}, weaktable)
local delegateQueue = setmetatable({}, weaktable)
local widgetQueue = setmetatable({}, weaktable) -- Widgets nach neuer GUID-Zuordnung auffrischen

local ForEachPlate
local EMPTY_TEXTURE = "Interface\\Addons\\TidyPlates\\Media\\Empty"
local select, pairs, tostring = select, pairs, tostring
local CreateTidyPlatesStatusbar = CreateTidyPlatesStatusbar

-- TODO: keep an eye on weaktable and revert if they cause issues
local Plates = setmetatable({}, weaktable)
local PlatesVisible = setmetatable({}, weaktable)
local PlatesFading = setmetatable({}, weaktable)
local GUID = setmetatable({}, weaktable)

local nameplate, extended, bars, regions, visual
local unit, unitcache, style, stylename, unitchanged
local currentTarget
local extendedSetAlpha, HighlightIsShown, HighlightSetAlpha
local PlateSetAlpha, PlateGetAlpha
local InCombat, HasTarget = false, false
TidyPlates.InCombat = InCombat

----------------------------
-- Internal Functions
----------------------------
-- Simple Functions
local function ClearIndices(t)
	if t then
		for i, v in pairs(t) do
			t[i] = nil
		end
		return t
	end
end
local function IsPlateShown(plate)
	return plate and plate:IsShown()
end
local function SetTargetQueue(plate, func)
	if func then
		targetQueue[plate] = func
	end
end
local function SetMassQueue(func)
	if func then
		massQueue[func] = true
	end
end
local function SetFunctionQueue(func)
	if func then
		functionQueue[func] = true
	end
end

-- Indicator Functions
local UpdateIndicator_CustomScaleText, UpdateIndicator_Standard, UpdateIndicator_CustomAlpha
local UpdateIndicator_Level, UpdateIndicator_ThreatGlow, UpdateIndicator_Target, UpdateIndicator_RaidIcon, UpdateIndicator_EliteIcon, UpdateIndicator_UnitColor, UpdateIndicator_Name
local UpdateIndicator_HealthBar, UpdateHitboxShape

-- Data and Condition Functions
local OnNewNameplate, OnShowNameplate, OnHideNameplate, OnUpdateNameplate, OnResetNameplate, OnEchoNewNameplate
local OnUpdateHealth, OnUpdateLevel, OnUpdateThreatSituation, OnUpdateRaidIcon, OnUpdateHealthRange
local OnMouseoverNameplate, OnRequestWidgetUpdate, OnRequestDelegateUpdate
local OnShowCastbar, OnHideCastbar, OnValueChangedCastbar
local PollPlateState, ProcessHealthUpdate, OnTargetChangedNameplate, LearnGUIDs
local CorrelateDamage, AssignFromMarkers, NameNeedsGUID
local ResetStackedPlate
-- Gegner, die mit mir/meinem Pet/meiner Gruppe im Kampf sind (aus dem Kampflog)
local EngagedGUID, EngagedNames = {}, {} -- [guid] = name / [name] = Anzahl
local StartTargetCastFallback, StopTargetCastFallback

-- Spell Casting
local StartCastAnimation, StopCastAnimation, OnUpdateTargetCastbar

-- Main Loop
local OnUpdate
local ApplyPlateExtension

--------------------------------------------------------------------------------------------------------------
-- II. Frame/Layer Appearance Functions:  These functions set the appearance of specific object types
--------------------------------------------------------------------------------------------------------------

local function SetObjectShape(object, width, height)
	object:SetWidth(width)
	object:SetHeight(height)
end
local function SetObjectFont(object, font, size, flags)
	object:SetFont(font, size, flags)
end
local function SetObjectJustify(object, horz, vert)
	object:SetJustifyH(horz)
	object:SetJustifyV(vert)
end
local function SetObjectShadow(object, shadow)
	if shadow then
		object:SetShadowColor(0, 0, 0, tonumber(shadow) or 1)
		object:SetShadowOffset(.5, -.5)
	else
		object:SetShadowColor(0, 0, 0, 0)
	end
end
local function SetObjectAnchor(object, anchor, anchorTo, x, y)
	object:ClearAllPoints()
	object:SetPoint(anchor, anchorTo, anchor, x, y)
end
local function SetObjectTexture(object, texture)
	object:SetTexture(texture)
	object:SetTexCoord(0, 1, 0, 1)
end
local function SetObjectBartexture(obj, tex, ori, crop)
	obj:SetStatusBarTexture(tex)
	obj:SetOrientation(ori)
end

-- SetFontGroupObject
local function SetFontGroupObject(object, objectstyle)
	SetObjectFont(object, objectstyle.typeface, objectstyle.size, objectstyle.flags)
	SetObjectJustify(object, objectstyle.align, objectstyle.vertical)
	SetObjectShadow(object, objectstyle.shadow)
end

-- SetAnchorGroupObject
local function SetAnchorGroupObject(object, objectstyle, anchorTo)
	SetObjectShape(object, objectstyle.width, objectstyle.height) --end
	SetObjectAnchor(object, objectstyle.anchor, anchorTo, objectstyle.x, objectstyle.y)
end

-- SetBarGroupObject
local backdropTable = {}
local function SetBarGroupObject(object, objectstyle, anchorTo)
	SetObjectShape(object, objectstyle.width, objectstyle.height)
	SetObjectAnchor(object, objectstyle.anchor, anchorTo, objectstyle.x, objectstyle.y)
	SetObjectBartexture(object, objectstyle.texture, objectstyle.orientation, objectstyle.texcoord)
	backdropTable.bgFile = objectstyle.backdrop
	object:SetBackdrop(backdropTable)
	if objectstyle.backdropcolor then
		object:SetBackdropColor(unpack(objectstyle.backdropcolor))
	end
end
local function MatchTextWidth()
	local stringwidth = visual.name:GetStringWidth() or 100
	bars.healthbar:SetWidth(stringwidth + style.healthbar.width)
	visual.healthborder:SetWidth(stringwidth + style.healthborder.width)
	visual.target:SetWidth(stringwidth + style.target.width)
	extended:SetWidth(stringwidth + style.frame.width)
end

--------------------------------------------------------------------------------------------------------------
-- III. Nameplate Style: These functions request updates for the appearance of the various graphical objects
--------------------------------------------------------------------------------------------------------------
local UpdateStyle
do
	-- Style Property Groups
	local fontgroup = {"name", "level", "spelltext", "customtext"}
	local anchorgroup = {"healthborder", "threatborder", "castborder", "castnostop", "name", "spelltext", "customtext", "level", "customart", "spellicon", "raidicon", "skullicon", "eliteicon", "target"}
	local bargroup = {"castbar", "healthbar"}
	local texturegroup = {"castborder", "castnostop", "healthborder", "threatborder", "eliteicon", "skullicon", "highlight", "target"}
	-- UpdateStyle:
	function UpdateStyle()
		-- Frame
		SetAnchorGroupObject(extended, style.frame, nameplate)
		-- Anchorgroup
		for index = 1, #anchorgroup do
			local objectname = anchorgroup[index]
			SetAnchorGroupObject(visual[objectname], style[objectname], extended)
			if style[objectname].show then
				visual[objectname]:Show()
			else
				visual[objectname]:Hide()
			end
		end
		-- Bars
		for index = 1, #bargroup do
			local objectname = bargroup[index]
			SetBarGroupObject(bars[objectname], style[objectname], extended)
		end
		-- Texture
		for index = 1, #texturegroup do
			local objectname = texturegroup[index]
			SetObjectTexture(visual[objectname], style[objectname].texture)
		end
		-- Font Group
		for index = 1, #fontgroup do
			local objectname = fontgroup[index]
			SetFontGroupObject(visual[objectname], style[objectname])
		end
		-- Hide Stuff
		if unit.isElite then
			visual.eliteicon:Hide()
		else
			visual.eliteicon:Hide()
		end
		if unit.isBoss then
			visual.level:Hide()
		else
			visual.skullicon:Hide()
		end
		if not unit.isTarget then
			visual.target:Hide()
		end
		if not unit.isMarked then
			visual.raidicon:Hide()
		end
		if activetheme.SetStatusbarWidthMatching then
			MatchTextWidth()
		end
	end
end
--------------------------------------------------------------------------------------------------------------
-- IV. Indicators: These functions update the actual data shown on the graphical objects
--------------------------------------------------------------------------------------------------------------

do
	local color = {}
	local threatborder, alpha, forcealpha, scale
	-- UpdateIndicator_HealthBar: Updates the value on the health bar
	function UpdateIndicator_HealthBar()
		bars.healthbar:SetMinMaxValues(bars.health:GetMinMaxValues())
		bars.healthbar:SetValue(bars.health:GetValue())
	end
	-- UpdateIndicator_Name:
	function UpdateIndicator_Name()
		visual.name:SetText(unit.name)
		-- Name Color
		if activetheme.SetNameColor then
			visual.name:SetTextColor(activetheme.SetNameColor(unit))
		else
			visual.name:SetTextColor(1, 1, 1, 1)
		end
		if activetheme.SetStatusbarWidthMatching then
			MatchTextWidth()
		end
	end
	-- UpdateIndicator_Level:
	function UpdateIndicator_Level()
		visual.level:SetText(unit.level)
		local tr, tg, tb = regions.level:GetTextColor()
		visual.level:SetTextColor(tr, tg, tb)
	end
	-- UpdateIndicator_ThreatGlow: Updates the aggro glow
	function UpdateIndicator_ThreatGlow()
		if not style.threatborder.show then
			return
		end
		threatborder = visual.threatborder
		if activetheme.SetThreatColor then
			threatborder:SetVertexColor(activetheme.SetThreatColor(unit))
		else
			if InCombat and unit.reaction ~= "FRIENDLY" and unit.type == "NPC" then
				color.r = style.threatcolor[unit.threatSituation].r
				color.g = style.threatcolor[unit.threatSituation].g
				color.b = style.threatcolor[unit.threatSituation].b
				color.a = style.threatcolor[unit.threatSituation].a
				threatborder:Show()
				threatborder:SetVertexColor(color.r, color.g, color.b, (color.a or 1))
			else
				threatborder:Hide()
			end
		end
	end
	-- UpdateIndicator_Target
	function UpdateIndicator_Target()
		if unit.isTarget and style.target.show then
			visual.target:Show()
		else
			visual.target:Hide()
		end
	end
	-- UpdateIndicator_RaidIcon
	function UpdateIndicator_RaidIcon()
		if unit.isMarked and style.raidicon.show then
			visual.raidicon:Show()
			visual.raidicon:SetTexCoord(regions.raidicon:GetTexCoord())
		else
			visual.raidicon:Hide()
		end
	end
	-- UpdateIndicator_EliteIcon: Updates the border overlay art and threat glow to Elite or Non-Elite art
	function UpdateIndicator_EliteIcon()
		threatborder = visual.threatborder
		if unit.isElite and style.eliteicon.show then
			visual.eliteicon:Show()
		else
			visual.eliteicon:Hide()
		end
	end
	-- UpdateIndicator_UnitColor: Update the health bar coloring, if needed
	function UpdateIndicator_UnitColor()
		-- Crowd Control Farbänderung
		if TidyPlatesWidgets and TidyPlatesWidgets.IsUnitCrowdControlled and TidyPlatesWidgets.IsUnitCrowdControlled(unit) then
			local color = CROWD_CONTROL_COLOR or {r=0.2, g=0.5, b=1.0}
			bars.healthbar:SetForegroundColor(color.r, color.g, color.b)
			visual.name:SetTextColor(color.r, color.g, color.b, 1)
			return
		end

		-- Set Health Bar
		if activetheme.SetHealthbarColor then
			--bars.healthbar:SetForegroundColor(activetheme.SetHealthbarColor(unit))
			bars.healthbar:SetStatusBarSmartGradient(activetheme.SetHealthbarColor(unit)) -- Testing Gradient
		else
			bars.healthbar:SetForegroundColor(bars.health:GetStatusBarColor())
		end
		-- Name Color
		if activetheme.SetNameColor then
			visual.name:SetTextColor(activetheme.SetNameColor(unit))
		else
			visual.name:SetTextColor(1, 1, 1, 1)
		end
	end
	-- UpdateIndicator_Standard: Updates Non-Delegate Indicators
	function UpdateIndicator_Standard()
		if IsPlateShown(nameplate) then
			if unitcache.name ~= unit.name then
				UpdateIndicator_Name()
			end
			if unitcache.level ~= unit.level then
				UpdateIndicator_Level()
			end
			UpdateIndicator_RaidIcon()
			if unitcache.isElite ~= unit.isElite then
				UpdateIndicator_EliteIcon()
			end
		end
	end
	-- UpdateIndicator_CustomAlpha: Calls the alpha delegate to get the requested alpha
	function UpdateIndicator_CustomAlpha()
		if activetheme.SetAlpha then
			local previousAlpha = extended.requestedAlpha
			extended.requestedAlpha = activetheme.SetAlpha(unit) or previousAlpha or unit.alpha or 1
		else
			extended.requestedAlpha = unit.alpha or 1
		end

		if not PlatesFading[nameplate] then
			extended:SetAlpha(extended.requestedAlpha)
		end
	end
	-- UpdateIndicator_CustomScaleText: Updates the custom indicators (text, image, alpha, scale)
	function UpdateIndicator_CustomScaleText()
		threatborder = visual.threatborder

		if unit.health and (extended.requestedAlpha > 0) then
			-- Scale
			if activetheme.SetScale then
				scale = activetheme.SetScale(unit)
				if scale then
					extended:SetScale(math.max(0.0001, scale))
				end
			end

			-- Set Special-Case Regions
			if style.customtext.show then
				if activetheme.SetCustomText then
					local text, r, g, b, a = activetheme.SetCustomText(unit)
					visual.customtext:SetText(text or "")
					visual.customtext:SetTextColor(r or 1, g or 1, b or 1, a or 1)
				else
					visual.customtext:SetText("")
				end
			end
			if style.customart.show then
				if activetheme.SetCustomArt then
					visual.customart:SetTexture(activetheme.SetCustomArt(unit))
				else
					visual.customart:SetTexture(EMPTY_TEXTURE)
				end
			end
			UpdateIndicator_UnitColor()
		end
	end
	-- UpdateHitboxShape:  Updates the nameplate's hitbox, but only out of combat
	function UpdateHitboxShape()
		if not InCombat then
			SetObjectShape(nameplate, style.hitbox.width, style.hitbox.height)
		end
	end
end

--------------------------------------------------------------------------------------------------------------
-- V. Data Gather: Gathers Information about the unit and requests updates, if needed
--------------------------------------------------------------------------------------------------------------
local UpdateReferences
do
	--------------------------------
	-- References and Cache
	--------------------------------
	-- UpdateUnitCache
	local function UpdateUnitCache()
		for key, value in pairs(unit) do
			unitcache[key] = value
		end
	end
	-- UpdateReferences
	function UpdateReferences(plate)
		nameplate = plate
		extended = plate.extended
		bars = extended.bars
		regions = extended.regions
		unit = extended.unit
		unitcache = extended.unitcache
		visual = extended.visual
		style = extended.style
	end

	--------------------------------
	-- GUID-Zuordnung
	-- Plaketten haben in 3.3.5a keine GUID. Neben Ziel/Mouseover (sicher) gibt es
	-- zwei Heuristiken, die NUR bei Eindeutigkeit zuordnen:
	--  1. Fingerabdruck: Beim Verschwinden einer Plakette werden GUID, Name, Stufe,
	--     Lebenspunkte usw. gemerkt und beim Wiederauftauchen abgeglichen.
	--  2. Schadens-Abgleich: Kampflog-Schaden an GUID X in Höhe Y wird mit einer
	--     Plakette abgeglichen, deren Lebenspunkte im selben Moment um Y sanken.
	-- Ziel/Mouseover sind maßgeblich und korrigieren falsche Zuordnungen.
	--------------------------------
	local HiddenFingerprints = {} -- [guid] = {name, level, healthmax, health, isElite, time}
	local FINGERPRINT_TTL = 30

	-- authoritative = true bei Ziel/Mouseover: darf bestehende Zuordnungen überschreiben
	local function AssignGUID(plate, guid, authoritative)
		if not plate or not guid then
			return false
		end
		local u = plate.extended.unit
		if u.guid == guid then
			return true
		end

		local other = GUID[guid]
		if other and other ~= plate then
			if not authoritative then
				return false
			end
			local ou = other.extended.unit
			if ou.guid == guid then
				ou.guid = nil
				widgetQueue[other] = true
			end
		end
		if u.guid then
			if not authoritative then
				return false
			end
			if GUID[u.guid] == plate then
				GUID[u.guid] = nil
			end
		end

		u.guid = guid
		GUID[guid] = plate
		HiddenFingerprints[guid] = nil
		widgetQueue[plate] = true -- Debuffs, Tank-Status, laufende Zauber nachziehen
		return true
	end

	-- Fingerabdruck: Darf die (sichtbare) Plakette u der gemerkte Gegner fp sein?
	-- Lebenspunkte dürfen seit dem Verschwinden nur gesunken sein (DoTs ticken weiter),
	-- mit kleiner Toleranz für Regeneration, und nicht beliebig stark.
	local function FingerprintMatches(fp, u, now)
		if fp.name ~= u.name or fp.level ~= u.level or fp.healthmax ~= u.healthmax or fp.isElite ~= u.isElite then
			return false
		end
		local hp = u.health
		if not hp or hp <= 0 then
			return false
		end
		local hidden = now - fp.time
		local maxDrop = fp.healthmax * math.min(0.5, 0.05 + 0.03 * hidden)
		return hp <= fp.health + fp.healthmax * 0.05 and hp >= fp.health - maxDrop
	end

	local function RememberFingerprint(u)
		if not (u.guid and u.name and u.healthmax and u.healthmax > 0 and u.health) then
			return
		end
		-- Unverletzte Gegner sind in Gruppen gleichnamiger Mobs nicht unterscheidbar
		if u.health >= u.healthmax or u.reaction == "FRIENDLY" or u.type == "PLAYER" then
			return
		end
		local fp = HiddenFingerprints[u.guid] or {}
		fp.name, fp.level, fp.healthmax, fp.health = u.name, u.level, u.healthmax, u.health
		fp.isElite, fp.time = u.isElite, GetTime()
		HiddenFingerprints[u.guid] = fp
	end

	-- Versucht für alle sichtbaren Plaketten ohne GUID einen gemerkten Gegner zu finden.
	-- Zugeordnet wird nur, wenn Plakette und Fingerabdruck sich gegenseitig eindeutig sind.
	local function RestoreFromFingerprints()
		if not next(HiddenFingerprints) then
			return
		end
		local now = GetTime()
		for guid, fp in pairs(HiddenFingerprints) do
			if GUID[guid] or (now - fp.time) > FINGERPRINT_TTL then
				HiddenFingerprints[guid] = nil
			end
		end
		for plate in pairs(PlatesVisible) do
			local u = plate.extended.unit
			if not u.guid and u.name then
				local found
				for guid, fp in pairs(HiddenFingerprints) do
					if FingerprintMatches(fp, u, now) then
						if found then
							found = false -- mehrdeutig
							break
						end
						found = guid
					end
				end
				if found then
					local fp = HiddenFingerprints[found]
					local unique = true
					for other in pairs(PlatesVisible) do
						local ou = other.extended.unit
						if other ~= plate and not ou.guid and FingerprintMatches(fp, ou, now) then
							unique = false
							break
						end
					end
					if unique then
						AssignGUID(plate, found)
					end
				end
			end
		end
	end

	-- Schadens-Abgleich
	local PendingDamage = {} -- Kampflog: {guid, name, amount, t}
	local PlateDamage = {}   -- Plaketten: {plate, amount, t}
	local CORRELATE_WINDOW = 0.35
	local MAX_PENDING = 200

	local DamageDirty = false -- neue Einträge seit dem letzten Abgleich

	local function PruneDamage(list, now)
		local j = 0
		for i = 1, #list do
			local r = list[i]
			if not r.done and (now - r.t) <= CORRELATE_WINDOW then
				j = j + 1
				list[j] = r
			end
		end
		for i = #list, j + 1, -1 do
			list[i] = nil
		end
	end

	local function AddDamageRecord(list, key, keyField, name, amount, now)
		-- Mehrere Treffer im selben Frame zusammenfassen
		for i = #list, 1, -1 do
			local r = list[i]
			if r.t ~= now then
				break
			end
			if r[keyField] == key then
				r.amount = r.amount + amount
				r.new = true
				DamageDirty = true
				return
			end
		end
		if #list >= MAX_PENDING then
			PruneDamage(list, now) -- alte Einträge zuerst verwerfen
			if #list >= MAX_PENDING then
				return
			end
		end
		list[#list + 1] = {[keyField] = key, name = name, amount = amount, t = now, new = true}
		DamageDirty = true
	end

	local function RecordCombatDamage(guid, name, amount)
		AddDamageRecord(PendingDamage, guid, "guid", name, amount, GetTime())
	end

	local function RecordPlateDamage(plate, amount)
		AddDamageRecord(PlateDamage, plate, "plate", nil, amount, GetTime())
	end

	-- Läuft nur, wenn seit dem letzten Frame neue Einträge kamen, und prüft nur Paare,
	-- an denen ein neuer Eintrag beteiligt ist (vorher: jeden Frame alle gegen alle).
	local abs = math.abs
	function CorrelateDamage()
		if not DamageDirty then
			return
		end
		DamageDirty = false
		local now = GetTime()
		PruneDamage(PendingDamage, now)
		PruneDamage(PlateDamage, now)

		-- Neue Plaketten-Einträge: passende Kampflog-Einträge erneut prüfen
		for k = 1, #PlateDamage do
			local d = PlateDamage[k]
			if d.new then
				d.new = nil
				local du = d.plate.extended.unit
				if not d.done and not du.guid then
					for i = 1, #PendingDamage do
						local e = PendingDamage[i]
						if e.amount == d.amount and e.name == du.name then
							e.new = true
						end
					end
				end
			end
		end

		for i = 1, #PendingDamage do
			local e = PendingDamage[i]
			local isNew = e.new
			e.new = nil
			if isNew and not e.done and not GUID[e.guid] then
				local match, count = nil, 0
				for k = 1, #PlateDamage do
					local d = PlateDamage[k]
					local du = d.plate.extended.unit
					if not d.done and d.amount == e.amount and abs(d.t - e.t) <= CORRELATE_WINDOW
						and not du.guid and du.name == e.name then
						count = count + 1
						match = d
					end
				end
				if count == 1 then
					-- Gegenprobe: kein anderer Gegner mit gleichem Namen und gleichem Schaden
					local unique = true
					for k = 1, #PendingDamage do
						local e2 = PendingDamage[k]
						if e2 ~= e and e2.guid ~= e.guid and not e2.done and e2.amount == e.amount
							and e2.name == e.name and abs(e2.t - match.t) <= CORRELATE_WINDOW then
							unique = false
							break
						end
					end
					if unique and AssignGUID(match.plate, e.guid) then
						match.done = true
						for k = 1, #PendingDamage do
							if PendingDamage[k].guid == e.guid then
								PendingDamage[k].done = true
							end
						end
					end
				end
			end
		end
	end

	-- Raid-Marker: Kampflog-Flags (und Einheiten wie raidXtarget) verraten, welche GUID
	-- welches Symbol trägt. Da jedes Symbol nur einmal vergeben ist, ist die Zuordnung zur
	-- Plakette mit demselben Symbol (und gleichem Namen) eindeutig - auch bei gleichnamigen
	-- Mobs mit voller Gesundheit.
	local MarkerGUID, MarkerName = {}, {} -- [icon] = guid / name
	local MarkersDirty = false
	local MarkerByIndex = {"STAR", "CIRCLE", "DIAMOND", "TRIANGLE", "MOON", "SQUARE", "CROSS", "SKULL"}
	local RAIDTARGET_MASK = 0x0FF00000
	local MarkerByBit = {}
	for i = 1, 8 do
		MarkerByBit[0x00080000 * 2 ^ i] = MarkerByIndex[i] -- 0x00100000 .. 0x08000000
	end

	local function RecordMarker(icon, guid, name)
		if icon and guid and MarkerGUID[icon] ~= guid then
			MarkerGUID[icon] = guid
			MarkerName[icon] = name
			MarkersDirty = true
		end
	end

	-- force = false: nur wenn seit dem letzten Lauf neue Marker-Informationen kamen
	function AssignFromMarkers(force)
		if not (force or MarkersDirty) then
			return
		end
		MarkersDirty = false
		if not next(MarkerGUID) then
			return
		end
		for plate in pairs(PlatesVisible) do
			local u = plate.extended.unit
			-- Symbol direkt aus der Region lesen: unit.raidIcon wird erst im nächsten Frame
			-- aktualisiert und wäre direkt nach dem Umsetzen eines Markers veraltet
			local raidicon = plate.extended.regions.raidicon
			local icon
			if raidicon:IsShown() then
				local ux, uy = raidicon:GetTexCoord()
				icon = MarkerByIndex[floor(ux * 4 + 0.5) + 1 + (uy > 0.1 and 4 or 0)]
			end
			if icon then
				local guid = MarkerGUID[icon]
				if guid and u.guid ~= guid and u.name == MarkerName[icon] then
					AssignGUID(plate, guid, true)
				end
			end
		end
	end

	-- Symbole wurden umverteilt: alte Zuordnungen verwerfen, Kampflog füllt sie neu
	do
		local MarkerWatcher = CreateFrame("Frame")
		MarkerWatcher:RegisterEvent("RAID_TARGET_UPDATE")
		MarkerWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
		MarkerWatcher:SetScript("OnEvent", function()
			wipe(MarkerGUID)
			wipe(MarkerName)
		end)
	end

	-- Kampflog: Schaden an Gegnern ohne bekannte Plakette vormerken
	do
		local band = bit.band
		local CONTROL_NPC = COMBATLOG_OBJECT_CONTROL_NPC
		local REACTION_FRIENDLY = COMBATLOG_OBJECT_REACTION_FRIENDLY
		local SpellDamageEvents = {
			SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, RANGE_DAMAGE = true,
			DAMAGE_SHIELD = true, DAMAGE_SPLIT = true
		}
		-- Namen sichtbarer Plaketten ohne GUID, höchstens einmal pro Frame neu erfasst.
		-- Schaden an Gegnern, die gar nicht zuzuordnen sind, wird so nicht gespeichert.
		local UnassignedNames, namesStamp = {}, nil
		function NameNeedsGUID(name)
			local now = GetTime()
			if namesStamp ~= now then
				namesStamp = now
				wipe(UnassignedNames)
				for plate in pairs(PlatesVisible) do
					local u = plate.extended.unit
					if not u.guid and u.name then
						UnassignedNames[u.name] = true
					end
				end
			end
			return UnassignedNames[name]
		end

		local AFFILIATION_OURS = 0x00000007 -- MINE, PARTY, RAID
		local NotEngaging = {
			UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true,
			SPELL_AURA_REMOVED = true, SPELL_AURA_REMOVED_DOSE = true, SPELL_AURA_BROKEN = true,
			SPELL_AURA_BROKEN_SPELL = true, ENCHANT_APPLIED = true, ENCHANT_REMOVED = true
		}

		local DamageWatcher = CreateFrame("Frame")
		DamageWatcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		DamageWatcher:SetScript("OnEvent", function(self, event, ...)
			local _, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags = ...
			local raid = sourceFlags and band(sourceFlags, RAIDTARGET_MASK)
			if raid and raid ~= 0 then
				RecordMarker(MarkerByBit[raid], sourceGUID, sourceName)
			end
			raid = destFlags and band(destFlags, RAIDTARGET_MASK)
			if raid and raid ~= 0 then
				RecordMarker(MarkerByBit[raid], destGUID, destName)
			end

			-- Beteiligte Gegner merken: eine Seite gehört zu mir/meiner Gruppe/meinem Raid,
			-- die andere ist ein nicht freundlicher NPC (Schaden, Verfehlen, Debuffs ...)
			if InCombat and sourceFlags and destFlags and not NotEngaging[subevent] then
				local gid, gname
				if band(sourceFlags, AFFILIATION_OURS) ~= 0 then
					if band(destFlags, CONTROL_NPC) ~= 0 and band(destFlags, REACTION_FRIENDLY) == 0 then
						gid, gname = destGUID, destName
					end
				elseif band(destFlags, AFFILIATION_OURS) ~= 0 then
					if band(sourceFlags, CONTROL_NPC) ~= 0 and band(sourceFlags, REACTION_FRIENDLY) == 0 then
						gid, gname = sourceGUID, sourceName
					end
				end
				if gid and gname and not EngagedGUID[gid] then
					EngagedGUID[gid] = gname
					EngagedNames[gname] = (EngagedNames[gname] or 0) + 1
				end
			end

			local amount, overkill
			if subevent == "SWING_DAMAGE" then
				amount, overkill = select(9, ...)
			elseif SpellDamageEvents[subevent] then
				amount, overkill = select(12, ...)
			elseif subevent == "UNIT_DIED" then
				if destGUID then
					HiddenFingerprints[destGUID] = nil
					local gname = EngagedGUID[destGUID]
					if gname then
						EngagedGUID[destGUID] = nil
						local n = (EngagedNames[gname] or 1) - 1
						EngagedNames[gname] = n > 0 and n or nil
					end
				end
				return
			else
				return
			end
			if not InCombat or not destGUID or GUID[destGUID] or not amount then
				return
			end
			if band(destFlags, CONTROL_NPC) == 0 or band(destFlags, REACTION_FRIENDLY) ~= 0 then
				return
			end
			if overkill and overkill > 0 then
				amount = amount - overkill
			end
			if amount > 0 and NameNeedsGUID(destName) then
				RecordCombatDamage(destGUID, destName, amount)
			end
		end)
	end

	--------------------------------
	-- Data Conversion Functions
	local ClassReference = {}
	-- ColorToString: Converts a color to a string with a C- prefix
	local function ColorToString(r, g, b)
		return "C" .. math.floor((100 * r) + 0.5) .. math.floor((100 * g) + 0.5) .. math.floor((100 * b) + 0.5)
	end
	-- GetUnitCombatStatus: Determines if a unit is in combat by checking the name text color
	local function GetUnitCombatStatus(r, g, b)
		return (r > .5 and g < .5)
	end
	-- GetUnitAggroStatus: Determines if a unit is attacking, by looking at aggro glow region
	local GetUnitAggroStatus
	do
		local shown
		local red, green, blue
		function GetUnitAggroStatus(region)
			-- High = 1, 0, 0	-- Medium High = 1, .6, 0  -- Medium Low = 1, 1, .47
			shown = region:IsShown()
			if not shown then
				return "LOW", 0
			end
			red, green, blue = region:GetVertexColor()
			if red > 0 then
				if green > 0 then
					if blue > 0 then
						return "MEDIUM", 1
					end
					return "MEDIUM", 2
				end
				return "HIGH", 3
			end
			return "LOW", 0
		end
	end
	-- GetUnitReaction: Determines the reaction, and type of unit from the health bar color
	local function GetUnitReaction(red, green, blue)
		if red < .01 and blue < .01 and green > .99 then
			return "FRIENDLY", "NPC"
		elseif red < .01 and blue > .99 and green < .01 then
			return "FRIENDLY", "PLAYER"
		elseif red > .99 and blue < .01 and green > .99 then
			return "NEUTRAL", "NPC"
		elseif red > .99 and blue < .01 and green < .01 then
			return "HOSTILE", "NPC"
		else
			return "HOSTILE", "PLAYER"
		end
	end
	-- Raid Icon Lookup table
	local ux, uy
	local RaidIconCoordinate = {
		--from GetTexCoord. input is ULx and ULy (first 2 values).
		[0] = {[0] = "STAR", [0.25] = "MOON"},
		[0.25] = {[0] = "CIRCLE", [0.25] = "SQUARE"},
		[0.5] = {[0] = "DIAMOND", [0.25] = "CROSS"},
		[0.75] = {[0] = "TRIANGLE", [0.25] = "SKULL"}
	}

	-- Populates the class color lookup table
	for classname, color in pairs(RAID_CLASS_COLORS) do
		ClassReference[ColorToString(color.r, color.g, color.b)] = classname
	end
	--------------------------------
	-- Mass Gather Functions
	--------------------------------
	local function GatherData_Alpha(plate)
		if HasTarget then
			unit.alpha = plate.alpha
		else
			unit.alpha = 1
		end -- Active Alpha

		unit.isTarget = HasTarget and unit.alpha == 1
		unit.isMouseover = regions.highlight:IsShown()
		-- GUID
		if unit.isTarget then
			currentTarget = plate
			OnUpdateTargetCastbar(plate)
			-- UpdateCurrentGUID: Ziel ist maßgeblich und korrigiert ggf. eine heuristische Zuordnung
			local targetGUID = UnitGUID("target")
			if targetGUID and unit.guid ~= targetGUID then
				AssignGUID(plate, targetGUID, true)
			end
			extended:SetFrameLevel(127)
		else
			extended:SetFrameLevel(extended.frameLevel)
		end

		UpdateIndicator_Target()
		if activetheme.OnContextUpdate then
			activetheme.OnContextUpdate(extended, unit)
		end
	end

	-- GatherData_BasicInfo: Updates Unit Variables
	local function GatherData_BasicInfo()
		unit.name = regions.name:GetText()
		unit.isBoss = regions.skullicon:IsShown()
		unit.isDangerous = unit.isBoss
		unit.isElite = (regions.eliteicon:IsShown() or 0) == 1

		if unit.isBoss then
			unit.level = "??"
		else
			unit.level = regions.level:GetText()
		end
		unit.health = bars.health:GetValue() or 0
		_, unit.healthmax = bars.health:GetMinMaxValues()

		if InCombat then
			unit.threatSituation, unit.threatValue = GetUnitAggroStatus(regions.threatglow)
		else
			unit.threatSituation = "LOW"
			unit.threatValue = 0
		end

		unit.isMarked = regions.raidicon:IsShown() or false

		unit.isInCombat = GetUnitCombatStatus(regions.name:GetTextColor())
		unit.red, unit.green, unit.blue = bars.health:GetStatusBarColor()
		unit.levelcolorRed, unit.levelcolorGreen, unit.levelcolorBlue = regions.level:GetTextColor()
		unit.reaction, unit.type = GetUnitReaction(unit.red, unit.green, unit.blue)
		unit.class = ClassReference[ColorToString(unit.red, unit.green, unit.blue)] or "UNKNOWN"
		unit.InCombatLockdown = InCombat

		if unit.isMarked then
			ux, uy = regions.raidicon:GetTexCoord()
			unit.raidIcon = RaidIconCoordinate[ux][uy]
		else
			unit.raidIcon = nil
		end
	end

	--------------------------------
	-- Graphical Updates
	--------------------------------
	-- CheckNameplateStyle
	local function CheckNameplateStyle()
		if activetheme.SetStyle then
			stylename = activetheme.SetStyle(unit)
			extended.style = activetheme[stylename]
		else
			extended.style = activetheme
			stylename = tostring(activetheme)
		end
		style = extended.style
		if extended.stylename ~= stylename then
			UpdateStyle()
			extended.stylename = stylename
			unit.style = stylename
		end
		UpdateHitboxShape()
	end

	-- ProcessUnitChanges
	local function ProcessUnitChanges()
		-- Unit Cache
		unitchanged = false
		for key, value in pairs(unit) do
			if unitcache[key] ~= value then
				unitchanged = true
				break
			end
		end

		-- Update Style/Indicators
		if unitchanged then
			CheckNameplateStyle()
			UpdateIndicator_Standard()
			UpdateIndicator_HealthBar()
		end

		-- Update Widgets
		if activetheme.OnUpdate then
			activetheme.OnUpdate(extended, unit)
		end

		-- Update Delegates
		UpdateIndicator_Target()
		UpdateIndicator_ThreatGlow()
		UpdateIndicator_CustomAlpha()
		UpdateIndicator_CustomScaleText()

		-- Cache the old unit information
		UpdateUnitCache()
	end

	--------------------------------
	-- Setup
	--------------------------------
	local function PrepareNameplate(plate)
		GatherData_BasicInfo()
		unit.frame = extended
		unit.alpha = 1
		unit.isTarget = false
		unit.isMouseover = false
		extended.unitcache = ClearIndices(extended.unitcache)
		extended.stylename = ""

		-- For Fading In
		PlatesFading[plate] = true
		extended.requestedAlpha = 0
		extended.visibleAlpha = 0
		extended:SetAlpha(0)

		-- Graphics
		unit.isCasting = false
		bars.castbar:Hide()
		visual.highlight:Hide()
		regions.highlight:Hide()

		-- Widgets/Extensions
		if activetheme.OnInitialize then
			activetheme.OnInitialize(extended)
		end
	end

	--------------------------------
	-- Individual Gather/Entry-Point Functions
	--------------------------------
	-- OnHideNameplate
	function OnHideNameplate(source)
		local plate = source.parentPlate
		-- Wiederverwendete Plakette darf den Stapel-Versatz des alten Gegners nicht erben
		if ResetStackedPlate then
			ResetStackedPlate(plate)
		end
		UpdateReferences(plate)
		if unit.guid then
			RememberFingerprint(unit) -- für das Wiederauftauchen merken
			if GUID[unit.guid] == plate then
				GUID[unit.guid] = nil
			end
		end
		extended.deltaHealth = nil

		bars.castbar:Hide()
		unit.isCasting = false

		PlatesVisible[plate] = nil
		extended.unit = ClearIndices(extended.unit)
		extended.unitcache = ClearIndices(extended.unitcache)
		for widgetname, widget in pairs(extended.widgets) do
			widget:Hide()
		end
		if plate == currentTarget then
			currentTarget = nil
		end
	end

	-- OnEchoNewNameplate: Intended to reduce CPU by bypassing the full update, and only checking the alpha value
	function OnEchoNewNameplate(plate)
		if not plate:IsShown() then
			return
		end
		-- Gather Information
		UpdateReferences(plate)
		GatherData_Alpha(plate)
		ProcessUnitChanges()
	end
	-- OnNewNameplate: When a new nameplate is generated, this function hooks the appropriate functions
	function OnNewNameplate(plate)
		local health, cast = plate:GetChildren()
		UpdateReferences(plate)
		PrepareNameplate(plate)
		GatherData_BasicInfo()
		extended.deltaHealth = unit.health -- Ausgangswert für den Schadens-Abgleich

		-- Alternative to reduce initial CPU load
		CheckNameplateStyle()
		UpdateIndicator_CustomAlpha()

		-- Hook for Updates
		health:HookScript("OnShow", OnShowNameplate)
		health:HookScript("OnHide", OnHideNameplate)
		health:HookScript("OnValueChanged", OnUpdateHealth)
		health:HookScript("OnMinMaxChanged", OnUpdateHealthRange)

		cast:HookScript("OnShow", OnShowCastbar)
		cast:HookScript("OnHide", OnHideCastbar)
		cast:HookScript("OnValueChanged", OnValueChangedCastbar)

		-- Activates nameplate visibility
		PlatesVisible[plate] = true
		SetTargetQueue(plate, OnEchoNewNameplate) -- Echo for a partial update (alpha only)
	end

	-- OnShowNameplate
	function OnShowNameplate(source)
		local plate = source.parentPlate
		-- Activate Plate
		PlatesVisible[plate] = true
		UpdateReferences(plate)
		PrepareNameplate(plate)
		GatherData_BasicInfo()
		extended.deltaHealth = unit.health -- Ausgangswert für den Schadens-Abgleich

		CheckNameplateStyle()
		UpdateIndicator_CustomAlpha()
		UpdateHitboxShape()

		SetTargetQueue(plate, OnUpdateNameplate) -- Echo for a full update
	end

	function OnShowCastbar(cast)
		StopTargetCastFallback() -- Blizzards Leiste übernimmt wieder
		cast.castbar:SetMinMaxValues(cast:GetMinMaxValues())
	end

	function OnHideCastbar(cast)
		StopCastAnimation(cast.parentPlate)
	end

	function OnValueChangedCastbar(cast, value)
		cast.castbar:SetValue(value)
	end

	-- OnUpdateNameplate
	function OnUpdateNameplate(plate)
		if not plate:IsShown() then
			return
		end
		-- Gather Information
		UpdateReferences(plate)
		GatherData_Alpha(plate)
		GatherData_BasicInfo()
		ProcessUnitChanges()
	end
	-- OnTargetChangedNameplate: Bei einem Zielwechsel brauchen nur das alte und das
	-- neue Ziel ein Vollupdate. Alle anderen Plaketten ändern nur Transparenz/Größe
	-- (Blizzard-Alpha für Nicht-Ziele, Ausblenden von Nicht-Zielen).
	function OnTargetChangedNameplate(plate)
		if not plate:IsShown() then
			return
		end
		UpdateReferences(plate)

		local alpha = HasTarget and plate.alpha or 1
		local isTarget = HasTarget and alpha == 1
		if unit.isTarget or isTarget then
			OnUpdateNameplate(plate)
			return
		end

		unit.alpha = alpha
		UpdateIndicator_CustomAlpha()
		UpdateIndicator_CustomScaleText()
	end

	-- OnUpdateLevel
	function OnUpdateLevel(plate)
		if not IsPlateShown(plate) then
			return
		end
		UpdateReferences(plate)
		if unit.isBoss then
			unit.level = "??"
		else
			unit.level = regions.level:GetText()
		end
		UpdateIndicator_Level()
	end

	-- OnUpdateThreatSituation
	function OnUpdateThreatSituation(plate)
		if not IsPlateShown(plate) then
			return
		end
		UpdateReferences(plate)

		if InCombat then
			unit.threatSituation, unit.threatValue = GetUnitAggroStatus(regions.threatglow)
		else
			unit.threatSituation = "LOW"
			unit.threatValue = 0
		end
		unit.isInCombat = GetUnitCombatStatus(regions.name:GetTextColor())

		CheckNameplateStyle()
		UpdateIndicator_ThreatGlow()
		UpdateIndicator_CustomAlpha()
		UpdateIndicator_CustomScaleText()
	end

	-- OnUpdateRaidIcon
	function OnUpdateRaidIcon(plate)
		if not IsPlateShown(plate) then
			return
		end
		UpdateReferences(plate)
		unit.isMarked = regions.raidicon:IsShown() or false
		if unit.isMarked then
			ux, uy = regions.raidicon:GetTexCoord()
			unit.raidIcon = RaidIconCoordinate[ux][uy]
		else
			unit.raidIcon = nil
		end
		UpdateIndicator_RaidIcon()
		UpdateIndicator_UnitColor()
	end

	-- OnUpdateReaction
	function OnUpdateReaction(plate)
		if not IsPlateShown(plate) then
			return
		end
		UpdateReferences(plate)
		unit.red, unit.green, unit.blue = bars.health:GetStatusBarColor()
		unit.reaction, unit.type = GetUnitReaction(unit.red, unit.green, unit.blue)
		unit.class = ClassReference[ColorToString(unit.red, unit.green, unit.blue)] or "UNKNOWN"
		UpdateIndicator_CustomScaleText()
	end

	-- OnMouseoverNameplate
	function OnMouseoverNameplate(plate)
		if not IsPlateShown(plate) then
			return
		end
		UpdateReferences(plate)
		unit.isMouseover = regions.highlight:IsShown()

		if unit.isMouseover then
			visual.highlight:Show()
			-- Mouseover ist maßgeblich und korrigiert ggf. eine heuristische Zuordnung
			local mouseoverGUID = UnitGUID("mouseover")
			if mouseoverGUID and unit.guid ~= mouseoverGUID then
				AssignGUID(plate, mouseoverGUID, true)
			end
		else
			visual.highlight:Hide()
		end

		OnUpdateThreatSituation(plate) -- This updates a bunch of properties
		if activetheme.OnContextUpdate then
			activetheme.OnContextUpdate(extended, unit)
		end
		if activetheme.OnUpdate then
			activetheme.OnUpdate(extended, unit)
		end

		-- Mouseover über ein Nicht-Ziel: Laufenden Zauber mit exakten Zeiten anzeigen
		local u = plate.extended.unit
		if u.isMouseover and not u.isTarget and TidyPlates.StartTimedCastOnNameplate
			and (not u.guid or u.guid == UnitGUID("mouseover")) then
			local spell, _, _, icon, startTime, endTime, _, _, notInterruptible = UnitCastingInfo("mouseover")
			local channel = false
			if not spell then
				spell, _, _, icon, startTime, endTime, _, notInterruptible = UnitChannelInfo("mouseover")
				channel = true
			end
			if spell and startTime and endTime then
				LearnCastShield(spell, notInterruptible)
				TidyPlates.StartTimedCastOnNameplate(plate, u.guid, spell, nil, icon, notInterruptible, startTime / 1000, endTime / 1000, channel)
			end
		end
	end

	-- OnRequestWidgetUpdate: Updates just the widgets
	function OnRequestWidgetUpdate(plate)
		if not IsPlateShown(plate) then
			return
		end
		UpdateReferences(plate)
		if activetheme.OnContextUpdate then
			activetheme.OnContextUpdate(extended, unit)
		end
		if activetheme.OnUpdate then
			activetheme.OnUpdate(extended, unit)
		end
	end

	-- OnRequestDelegateUpdate: Updates just the delegate function indicators (excluding Style?)
	function OnRequestDelegateUpdate(plate)
		if not IsPlateShown(plate) then
			return
		end
		UpdateReferences(plate)
		UpdateIndicator_ThreatGlow()
		UpdateIndicator_CustomAlpha()
		UpdateIndicator_CustomScaleText()
	end

	-- OnUpdateHealth: Nur vormerken. Mehrere Lebenspunkte-Ticks einer Plakette
	-- innerhalb eines Frames werden so zu einem Update zusammengefasst.
	function OnUpdateHealth(source)
		local plate = source.parentPlate
		if plate then
			healthQueue[plate] = true
		end
	end

	-- ProcessHealthUpdate: Wird einmal pro Frame aus OnUpdate aufgerufen
	function ProcessHealthUpdate(plate)
		if not IsPlateShown(plate) then
			return
		end
		UpdateReferences(plate)
		unit.health = bars.health:GetValue() or 0
		_, unit.healthmax = bars.health:GetMinMaxValues()

		-- Lebenspunkte-Abzug für den Schadens-Abgleich merken (nur Plaketten ohne GUID)
		local lastHealth = extended.deltaHealth
		extended.deltaHealth = unit.health
		if lastHealth and unit.health < lastHealth and not unit.guid and InCombat then
			RecordPlateDamage(plate, lastHealth - unit.health)
		end

		UpdateIndicator_HealthBar()
		UpdateIndicator_CustomAlpha()
		UpdateIndicator_CustomScaleText()
	end

	-- OnUpdateHealthRange
	function OnUpdateHealthRange(source)
		local plate = source.parentPlate
		plate.extended.deltaHealth = nil -- max. Lebenspunkte geändert: kein Abzug ableitbar
		OnUpdateNameplate(plate)
	end

	-- Shows the Cast Animation (requires references)
	-- minOverride/maxOverride: Für Nicht-Ziele gibt es keine Blizzard-Zauberleiste,
	-- dann wird die Dauer direkt übergeben (siehe TidyPlatesSpellCastMonitor.lua).
	-- Rückgabe: true, wenn die Zauberleiste angezeigt wird.
	function StartCastAnimation(plate, spell, spellid, icon, notInterruptible, channel, minOverride, maxOverride)
		UpdateReferences(plate)
		if (tonumber(GetCVar("showVKeyCastbar")) == 1) and spell then
			local castbar = bars.castbar
			local minval, maxval
			if maxOverride then
				minval, maxval = minOverride or 0, maxOverride
			else
				minval, maxval = castbar.cast:GetMinMaxValues()
			end
			if not (minval or maxval) or maxval == 0 or minval == maxval then
				StopCastAnimation(plate)
				return
			end

			local r, g, b, a = 1, .8, 0, 1
			unit.isCasting = true
			unit.spellName = spell
			unit.spellID = spellid
			-- Unbekannt (Kampflog): gespeichertes Wissen über den Zauber verwenden
			if not notInterruptible and TidyPlatesData.CastShield and TidyPlatesData.CastShield[spell] then
				notInterruptible = true
			end
			unit.spellIsShielded = notInterruptible
			unit.spellInterruptible = not notInterruptible
			-- Restzeit für die Startfarbe (Kick bis Zauberende bereit?); ab dem ersten Frame
			-- führt das Theme sie mit der echten Restzeit nach
			unit.castRemaining = maxval - minval

			if activetheme.SetCastbarColor then
				r, g, b, a = activetheme.SetCastbarColor(unit)
				if not (r and g and b) then
					return
				end
			end

			castbar:SetMinMaxValues(minval, maxval)
			castbar:SetForegroundColor(r, g, b, a or 1)
			visual.spelltext:SetText(spell)

			visual.spellicon:SetTexture(icon)
			-- Rahmengrafiken nur, wenn der Stil sie zeigt (sonst z.B. Plater-Optik überdeckt)
			if notInterruptible then
				visual.castborder:Hide()
				if style.castnostop.show then
					visual.castnostop:Show()
				else
					visual.castnostop:Hide()
				end
			else
				visual.castnostop:Hide()
				if style.castborder.show then
					visual.castborder:Show()
				else
					visual.castborder:Hide()
				end
			end

			castbar:Show()

			UpdateIndicator_CustomScaleText()
			UpdateIndicator_CustomAlpha()
			return true
		end
	end

	-- Hides the Cast Animation (requires references)
	function StopCastAnimation(plate)
		UpdateReferences(plate)
		bars.castbar:Hide()
		unit.isCasting = false
		UpdateIndicator_CustomScaleText()
		UpdateIndicator_CustomAlpha()
	end

	-- OnUpdateTargetCastbar: Called from hooking into the original nameplate castbar's "OnValueChanged"
	-- Ersatz-Steuerung der Ziel-Zauberleiste (siehe OnUpdateTargetCastbar). Werte im
	-- GetTime-Maßstab: Zauber laufen von Start bis Ende, Kanalisieren rückwärts.
	local fallback = {}
	local TargetCastTicker = CreateFrame("Frame")
	TargetCastTicker:Hide()
	TargetCastTicker:SetScript("OnUpdate", function(self)
		local plate, now = fallback.plate, GetTime()
		if not plate or not plate:IsShown() or not plate.extended.unit.isTarget then
			fallback.plate = nil
			self:Hide()
		elseif now >= fallback.endTime then
			fallback.plate = nil
			self:Hide()
			StopCastAnimation(plate)
		elseif fallback.channel then
			plate.extended.bars.castbar:SetValue(fallback.startTime + fallback.endTime - now)
		else
			plate.extended.bars.castbar:SetValue(now)
		end
	end)

	function StartTargetCastFallback(plate, startTime, endTime, channel)
		fallback.plate, fallback.startTime, fallback.endTime, fallback.channel = plate, startTime, endTime, channel
		TargetCastTicker:Show()
	end

	function StopTargetCastFallback()
		fallback.plate = nil
		TargetCastTicker:Hide()
	end

	function OnUpdateTargetCastbar(source)
		if not source then
			return
		end
		local plate
		if PlatesVisible[source] then
			plate = source
		else
			plate = source.parentPlate
		end

		if plate and plate.extended.unit.isTarget then
			-- Grabs the target's casting information
			local spell, icon, nonInt, channel, spellid, startMS, endMS

			spell, _, _, icon, startMS, endMS, _, spellid, nonInt = UnitCastingInfo("target")

			if not spell then
				spell, _, _, icon, startMS, endMS, spellid, nonInt = UnitChannelInfo("target")
				channel = true
			end

			StopTargetCastFallback()
			if spell then
				LearnCastShield(spell, nonInt)
				-- Blizzards Ziel-Zauberleiste läuft erst beim nächsten Zauberbeginn an. Wird ein
				-- Gegner mitten im Zauber anvisiert, hat sie keine Werte: dann selbst steuern.
				local blizz = plate.extended.bars.cast
				local bmin, bmax = blizz:GetMinMaxValues()
				if blizz:IsShown() and bmin and bmax and bmax > bmin then
					StartCastAnimation(plate, spell, spellid, icon, nonInt, channel)
				elseif startMS and endMS and endMS > startMS then
					local st, et = startMS / 1000, endMS / 1000
					if StartCastAnimation(plate, spell, spellid, icon, nonInt, channel, st, et) then
						StartTargetCastFallback(plate, st, et, channel)
					end
				else
					StopCastAnimation(plate)
				end
			else
				StopCastAnimation(plate)
			end
		end
	end

	-- PollPlateState: 3.3.5a liefert kein Event, wenn sich das Aggro-Leuchten oder der
	-- Kampfstatus einer einzelnen Plakette ändert. Darum wird das hier zyklisch geprüft
	-- und nur die Plakette aktualisiert, die sich tatsächlich geändert hat.
	function PollPlateState(plate)
		local ext = plate.extended
		local u = ext.unit
		if not u.name then
			return
		end
		local regs = ext.regions

		local threatSituation = "LOW"
		if InCombat then
			threatSituation = GetUnitAggroStatus(regs.threatglow)
		end
		local isInCombat = GetUnitCombatStatus(regs.name:GetTextColor())

		if threatSituation ~= u.threatSituation or isInCombat ~= u.isInCombat then
			-- Vollupdate (inkl. Widgets wie Threat-Art), überschreibt kleinere Updates
			targetQueue[plate] = OnUpdateNameplate
		end

		-- Crowd-Control-Farbe zurücksetzen/setzen, wenn der Effekt beginnt oder ausläuft
		local isCC = TidyPlatesWidgets and TidyPlatesWidgets.IsUnitCrowdControlled and TidyPlatesWidgets.IsUnitCrowdControlled(u) or false
		if isCC ~= (ext.isCrowdControlled or false) then
			ext.isCrowdControlled = isCC
			if not targetQueue[plate] then
				targetQueue[plate] = OnRequestDelegateUpdate
			end
		end
	end

	-- LearnGUIDs: Plaketten haben in 3.3.5a keine GUID. Bisher wurde sie nur über
	-- Ziel/Mouseover gelernt. Zusätzlich werden hier die Ziele von Fokus, Pet und
	-- Gruppenmitgliedern genutzt: Passt genau EINE sichtbare Plakette ohne GUID zu
	-- Name + Lebenspunkte + max. Lebenspunkte, bekommt sie die GUID. Bei mehreren
	-- Treffern (z.B. Gruppe gleichnamiger Mobs mit voller Gesundheit) wird nichts
	-- zugeordnet, um falsche Debuffs/Zauberleisten zu vermeiden.
	-- boss1-4: Boss-Einheiten (falls der Server sie liefert, sonst wirkungslos)
	local LearnUnits = {"focus", "focustarget", "targettarget", "pettarget", "boss1", "boss2", "boss3", "boss4"}
	local partyTargets, raidTargets = {}, {}
	for i = 1, 4 do partyTargets[i] = "party" .. i .. "target" end
	for i = 1, 40 do raidTargets[i] = "raid" .. i .. "target" end

	local function LearnGUIDFromUnit(uid)
		if not UnitExists(uid) or UnitIsFriend("player", uid) then
			return
		end
		local guid = UnitGUID(uid)
		if not guid then
			return
		end
		local name = UnitName(uid)
		RecordMarker(MarkerByIndex[GetRaidTargetIndex(uid) or 0], guid, name)
		if GUID[guid] then
			return
		end
		local hp, hpmax = UnitHealth(uid), UnitHealthMax(uid)
		local match
		for plate in pairs(PlatesVisible) do
			local u = plate.extended.unit
			if not u.guid and u.name == name and u.health == hp and u.healthmax == hpmax then
				if match then
					return -- mehrdeutig
				end
				match = plate
			end
		end
		if match then
			AssignGUID(match, guid)
		end
	end

	function LearnGUIDs()
		AssignFromMarkers(true) -- auch neu aufgetauchte markierte Plaketten erfassen
		RestoreFromFingerprints()
		for i = 1, #LearnUnits do
			LearnGUIDFromUnit(LearnUnits[i])
		end
		local numRaid = GetNumRaidMembers()
		if numRaid > 0 then
			for i = 1, numRaid do
				LearnGUIDFromUnit(raidTargets[i])
			end
		else
			for i = 1, GetNumPartyMembers() do
				LearnGUIDFromUnit(partyTargets[i])
			end
		end
	end

	-- OnResetNameplate
	function OnResetNameplate(plate)
		local extended = plate.extended
		extended.unitcache = ClearIndices(extended.unitcache)
		extended.stylename = ""
		OnShowNameplate(extended)
	end
end

--------------------------------------------------------------------------------------------------------------
-- VI. Nameplate Extension: Applies scripts, hooks, and adds additional frame variables and elements
--------------------------------------------------------------------------------------------------------------

do
	-- local bars, regions, health, castbar, healthbar, visual
	local castbar, healthbar, region
	local platelevels = 125

	local function GetNameplateRegions(plate, regions, cast)
		regions.threatglow, regions.healthborder, regions.castborder, regions.castnostop, regions.spellicon, regions.highlight, regions.name, regions.level, regions.skullicon, regions.raidicon, regions.eliteicon = plate:GetRegions()
	end

	-- Blizzard-Optik für Themes (TidyPlates.BlizzardArt): Pfad und Ausschnitt der Original-
	-- grafiken sowie ihre Lage relativ zur Original-Lebens- bzw. Zauberleiste (Anteile von
	-- Balkenbreite/-höhe ab der linken unteren Ecke). Muss vor dem Unsichtbarmachen und vor
	-- dem Ändern der Hitbox-Größe laufen; gemessen wird, bis es einmal gelingt.
	local function MeasureRect(region, bar)
		local l, r, t, b = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
		local bl, bb, bw, bh = bar:GetLeft(), bar:GetBottom(), bar:GetWidth(), bar:GetHeight()
		if not (l and r and t and b and bl and bb and bw and bh) or bw < 1 or bh < 1 then
			return
		end
		return {left = (l - bl) / bw, right = (r - bl) / bw, top = (t - bb) / bh, bottom = (b - bb) / bh}
	end

	-- Erster Schlüssel ist Pflicht (Rahmen), die übrigen werden nur übernommen, wenn messbar
	local function MeasureGroup(regions, bar, keys)
		local geo = {width = bar:GetWidth(), height = bar:GetHeight()}
		for index, key in ipairs(keys) do
			local rect = MeasureRect(regions[key], bar)
			if not rect and index == 1 then
				return
			end
			geo[key] = rect
		end
		return geo
	end

	local function CaptureBlizzardArt(regions, bars)
		local art = TidyPlates.BlizzardArt
		if not art then
			art = {}
			for _, key in ipairs({"threatglow", "healthborder", "castborder", "castnostop", "highlight", "eliteicon", "skullicon"}) do
				local region = regions[key]
				art[key] = {texture = region:GetTexture(), coords = {region:GetTexCoord()}}
			end
			art.levelFont = {regions.level:GetFont()}
			art.levelPoint = regions.level:GetPoint(1)
			TidyPlates.BlizzardArt = art
		end
		if not art.health then
			art.health = MeasureGroup(regions, bars.health, {"healthborder", "threatglow", "highlight", "eliteicon", "skullicon", "level"})
		end
		if not art.cast then
			art.cast = MeasureGroup(regions, bars.cast, {"castborder", "castnostop", "spellicon"})
		end
	end

	-- Zauberleiste nachmessen, falls sie beim Erzeugen noch keine Lage hatte. Rahmen und
	-- Symbol hängen an der Zauberleiste selbst, die Hitbox-Größe spielt hier keine Rolle.
	function TidyPlates.MeasureBlizzardCast(extended)
		local art = TidyPlates.BlizzardArt
		if art and not art.cast then
			art.cast = MeasureGroup(extended.regions, extended.bars.cast, {"castborder", "castnostop"})
		end
	end

	function ApplyPlateExtension(plate)
		Plates[plate] = true
		plate.extended = CreateFrame("Frame", nil, plate)
		local extended = plate.extended
		platelevels = platelevels - 1
		if platelevels < 1 then
			platelevels = 1
		end
		extended.frameLevel = platelevels
		extended:SetFrameLevel(platelevels)

		extended.style, extended.unit, extended.unitcache, extended.stylecache, extended.widgets = {}, {}, {}, {}, {}

		extended.regions, extended.bars, extended.visual = {}, {}, {}
		regions = extended.regions
		bars = extended.bars
		bars.health, bars.cast = plate:GetChildren()
		extended.stylename = ""

		-- Set Frame Levels and Parent
		GetNameplateRegions(plate, regions, bars.cast)

		CaptureBlizzardArt(regions, bars)

		-- This block makes the Blizz nameplate invisible
		regions.threatglow:SetTexCoord(0, 0, 0, 0)
		regions.healthborder:SetTexCoord(0, 0, 0, 0)
		regions.castborder:SetTexCoord(0, 0, 0, 0)
		regions.castnostop:SetTexCoord(0, 0, 0, 0)
		regions.skullicon:SetTexCoord(0, 0, 0, 0)
		regions.eliteicon:SetTexCoord(0, 0, 0, 0)
		regions.name:SetWidth(000.1)
		regions.level:SetWidth(000.1)
		regions.spellicon:SetTexCoord(0, 0, 0, 0)
		regions.spellicon:SetWidth(.001)
		regions.raidicon:SetAlpha(0)
		regions.highlight:SetTexture(EMPTY_TEXTURE)
		bars.health:SetStatusBarTexture(EMPTY_TEXTURE)
		bars.cast:SetStatusBarTexture(EMPTY_TEXTURE)

		-- Create Statusbars
		bars.healthbar = CreateTidyPlatesStatusbar(extended)
		bars.castbar = CreateTidyPlatesStatusbar(extended)
		local health, cast, healthbar, castbar = bars.health, bars.cast, bars.healthbar, bars.castbar
		extended.parentPlate = plate
		health.parentPlate = plate
		cast.parentPlate = plate
		castbar.parentPlate = plate

		-- reference to each other
		cast.castbar = castbar
		castbar.cast = cast

		-- Visible Bars
		healthbar:SetFrameLevel(platelevels - 1)
		castbar:Hide()
		castbar:SetFrameLevel(platelevels)
		castbar:SetForegroundColor(1, .8, 0)

		-- Visual Regions
		visual = extended.visual
		visual.customart = extended:CreateTexture(nil, "OVERLAY")
		visual.target = extended:CreateTexture(nil, "ARTWORK")
		visual.raidicon = extended:CreateTexture(nil, "OVERLAY")
		visual.raidicon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
		visual.eliteicon = extended:CreateTexture(nil, "OVERLAY")
		visual.healthborder = healthbar:CreateTexture(nil, "ARTWORK")
		visual.threatborder = healthbar:CreateTexture(nil, "ARTWORK")
		visual.skullicon = healthbar:CreateTexture(nil, "OVERLAY")
		visual.highlight = healthbar:CreateTexture(nil, "OVERLAY")
		visual.highlight:SetAllPoints(visual.healthborder)
		visual.highlight:SetBlendMode("ADD")
		visual.castborder = castbar:CreateTexture(nil, "ARTWORK")
		visual.castnostop = castbar:CreateTexture(nil, "ARTWORK")
		visual.spellicon = castbar:CreateTexture(nil, "OVERLAY")

		for i, v in pairs(visual) do
			v:SetNonBlocking(true)
		end

		visual.customtext = extended:CreateFontString(nil, "OVERLAY")
		visual.name = extended:CreateFontString(nil, "OVERLAY")
		visual.level = extended:CreateFontString(nil, "OVERLAY")
		visual.spelltext = castbar:CreateFontString(nil, "OVERLAY")

		if not extendedSetAlpha then
			PlateSetAlpha = plate.SetAlpha
			PlateGetAlpha = plate.GetAlpha
			extendedSetAlpha = plate.extended.SetAlpha
			HighlightIsShown = plate.extended.visual.highlight.IsShown
		end

		OnNewNameplate(plate)
	end
end

--------------------------------------------------------------------------------------------------------------
-- Stapeln: Gegnerische Plaketten werden nach oben geschoben, statt sich zu überlappen.
-- Übernommen aus der WeakAura "Cheeta - Enhanced Stacking Nameplate" (gleiche Formeln),
-- aber über die bekannten sichtbaren Plaketten statt aller WorldFrame-Kinder. Ohne den
-- Secure-Trick für die Klickfläche im Kampf (der hat offene Fenster geschlossen).
-- Aktiviert/konfiguriert vom Theme über TidyPlates:SetStacking().
--------------------------------------------------------------------------------------------------------------
local UpdateStacking
do
	local abs, exp = math.abs, math.exp
	local cfg = {
		enabled = false,
		xspace = 130, yspace = 20,                         -- Mindestabstand zwischen Plaketten
		speed = 0.7, speedraise = 1, speedlower = 1, speedreset = 1,
		originpos = 20, upperborder = 30,
		interval = 0.02,
		tallBossFix = true,
		pinTarget = true,                                  -- Ziel bleibt an seinem Platz
		extraTop = nil,                                    -- function(extended): zusätzlicher Platz über der Plakette (z.B. Debuffs)
		columnsAt = 0,                                     -- ab so vielen Plaketten in einem Turm zwei Spalten (0 = aus)
		onlyEngaged = false                                -- im Kampf nur beteiligte Gegner stapeln
	}
	local delta = cfg.speed * 5
	local Stacked = {} -- [plate] = {xpos, ypos, position, bottom}
	local nextRun = 0
	local worldFrameEnlarged = false

	local function ResetPlate(plate)
		Stacked[plate] = nil
		plate:SetClampRectInsets(0, 0, 0, 0)
		plate:SetClampedToScreen(false)
	end
	function ResetStackedPlate(plate)
		if Stacked[plate] then
			ResetPlate(plate)
		end
	end

	-- Nach x sortiert; verglichen werden nur Nachbarn innerhalb von xspace
	-- (vorher alle Paare, 50x pro Sekunde)
	local Order, ExOrder, ActiveOrder = {}, {}, {}
	local function ByX(a, b)
		return a.xpos < b.xpos
	end
	local function ByEx(a, b)
		return a.ex < b.ex
	end
	local HSPEED = 0.25 -- Anteil der Reststrecke pro Lauf beim seitlichen Gleiten (~0,2 s)

	-- Ist der Gegner an meinem Kampf beteiligt? Ziel/Mouseover immer; nicht im Kampf (Name
	-- nicht rot) nie; Aggro-Leuchten auf mir ja; sonst über die Kampflog-Liste - per GUID,
	-- ohne GUID über den Namen (im Zweifel beteiligt).
	local function IsEngaged(unit)
		if unit.isTarget or unit.isMouseover then
			return true
		end
		if not unit.isInCombat then
			return false
		end
		if unit.threatSituation and unit.threatSituation ~= "LOW" then
			return true
		end
		if unit.guid then
			return EngagedGUID[unit.guid] ~= nil
		end
		return unit.name and EngagedNames[unit.name] ~= nil
	end

	-- Zwei Spalten: Ein "Turm" sind Plaketten, deren natürliche x-Position innerhalb von
	-- xspace der linken liegt (alle überlappen sich). Ab columnsAt Plaketten bekommt jede
	-- eine Seite (links/rechts); die Spalten liegen eine Plakettenbreite auseinander und
	-- stapeln dadurch unabhängig. Seiten bleiben erhalten, solange die Spalten nicht um mehr
	-- als eine Plakette ungleich sind (kein Springen, wenn sich Mobs bewegen). Das Ziel bleibt
	-- an seinem Platz (zwischen den Spalten).
	local function AssignColumns(order, count, xspace, splitAt)
		local i = 1
		while i <= count do
			local first = order[i]
			local j = i
			while j < count and order[j + 1].xpos - first.xpos < xspace do
				j = j + 1
			end
			local size = j - i + 1
			local wasSplit = false
			for k = i, j do
				if order[k].side then
					wasSplit = true
					break
				end
			end
			-- Etwas Spielraum beim Zurückschalten, damit es an der Grenze nicht flackert
			if splitAt > 1 and (size >= splitAt or (wasSplit and size >= splitAt - 1)) then
				local sum = 0
				for k = i, j do
					sum = sum + order[k].xpos
				end
				local cx = sum / size
				local left, right = 0, 0
				for k = i, j do
					local p = order[k]
					if p.isTarget then
						p.side = nil
					elseif p.side == -1 then
						left = left + 1
					elseif p.side == 1 then
						right = right + 1
					end
				end
				-- Neue Mitglieder auf die kleinere Seite (bei Gleichstand nach Lage zur Mitte)
				for k = i, j do
					local p = order[k]
					if not p.isTarget and not p.side then
						if left < right or (left == right and p.xpos < cx) then
							p.side, left = -1, left + 1
						else
							p.side, right = 1, right + 1
						end
					end
				end
				-- Ausgleichen: von der größeren Seite die Plakette, die am nächsten an der
				-- anderen Seite liegt
				while left - right > 1 or right - left > 1 do
					local from = left > right and -1 or 1
					local best
					for k = i, j do
						local p = order[k]
						if p.side == from and (not best or (from == -1 and p.xpos > best.xpos) or (from == 1 and p.xpos < best.xpos)) then
							best = p
						end
					end
					best.side = -from
					if from == -1 then
						left, right = left - 1, right + 1
					else
						left, right = left + 1, right - 1
					end
				end
				local half = xspace / 2 + 1
				for k = i, j do
					local p = order[k]
					p.hgoal = p.side and (cx + p.side * half - p.xpos) or 0
				end
			else
				for k = i, j do
					order[k].side = nil
					order[k].hgoal = 0
				end
			end
			i = j + 1
		end
	end
	local EXTRA_INTERVAL = 0.1 -- Platz für Debuffs seltener abfragen als gestapelt wird

	-- Plaketten sehr großer Bosse sollen nicht oben aus dem Bild rutschen (wie in der Aura)
	local function EnlargeWorldFrame()
		if worldFrameEnlarged or InCombatLockdown() then
			return
		end
		worldFrameEnlarged = true
		WorldFrame:ClearAllPoints()
		WorldFrame:SetWidth(GetScreenWidth() * UIParent:GetEffectiveScale())
		WorldFrame:SetHeight(768 * 5)
		WorldFrame:SetPoint("BOTTOM")
	end

	-- options = nil schaltet das Stapeln ab
	function TidyPlates:SetStacking(options)
		if options and options.enabled then
			for key, value in pairs(options) do
				cfg[key] = value
			end
			delta = cfg.speed * 5
			if GetCVar("nameplateAllowOverlap") == "0" then
				SetCVar("nameplateAllowOverlap", 1)
			end
			if cfg.tallBossFix then
				EnlargeWorldFrame()
			end
		else
			cfg.enabled = false
			for plate in pairs(Stacked) do
				ResetPlate(plate)
			end
		end
	end

	function UpdateStacking(now)
		if not cfg.enabled or now < nextRun then
			return
		end
		nextRun = now + cfg.interval
		local xspace, yspace, originpos, upperborder = cfg.xspace, cfg.yspace, cfg.originpos, cfg.upperborder

		-- Verschwundene oder freundliche Plaketten zurücksetzen
		for plate in pairs(Stacked) do
			if not PlatesVisible[plate] or not plate:IsShown() or plate.extended.unit.reaction == "FRIENDLY" then
				ResetPlate(plate)
			end
		end
		-- Ursprüngliche Position aller gegnerischen Plaketten
		for plate in pairs(PlatesVisible) do
			if plate:IsShown() and plate.extended.unit.reaction ~= "FRIENDLY" then
				local p = Stacked[plate]
				if not p then
					p = {xpos = 0, ypos = 0, position = 0}
					Stacked[plate] = p
				end
				local _, _, _, x, y = plate:GetPoint(1)
				p.xpos, p.ypos = x or 0, y or 0 -- (Sortieren verträgt kein nil)
				p.plate = plate
				-- Unbeteiligte: schieben niemanden weg, gleiten selbst an ihren Platz zurück
				-- (nur im Kampf; außerhalb wird wie bisher alles gestapelt)
				p.passive = cfg.onlyEngaged and InCombat and not IsEngaged(plate.extended.unit) or nil
				p.isTarget = cfg.pinTarget and plate.extended.unit.isTarget
				if not p.extraAt or now >= p.extraAt then
					p.extraAt = now + EXTRA_INTERVAL
					p.extra = cfg.extraTop and cfg.extraTop(plate.extended) or 0
				end
			end
		end

		local order = Order
		local count = 0
		for _, p in pairs(Stacked) do
			count = count + 1
			order[count] = p
		end
		for i = #order, count + 1, -1 do
			order[i] = nil
		end
		table.sort(order, ByX)

		-- Spalten bestimmen (nur aus beteiligten Plaketten) und seitlich dorthin gleiten
		local active, nActive = ActiveOrder, 0
		for i = 1, count do
			local p = order[i]
			if p.passive then
				p.side, p.hgoal = nil, 0
			else
				nActive = nActive + 1
				active[nActive] = p
			end
		end
		for i = #active, nActive + 1, -1 do
			active[i] = nil
		end
		AssignColumns(active, nActive, xspace, cfg.columnsAt or 0)
		for i = 1, count do
			local p = order[i]
			local h, goal = p.hoff or 0, p.hgoal or 0
			local diff = goal - h
			if abs(diff) < 0.5 then
				h = goal
			else
				h = h + diff * HSPEED
			end
			p.hoff = h
			p.ex = p.xpos + h
		end
		-- Für das Stapeln zählt die tatsächliche (verschobene) x-Position
		local exorder = ExOrder
		for i = 1, count do
			exorder[i] = order[i]
		end
		for i = #exorder, count + 1, -1 do
			exorder[i] = nil
		end
		table.sort(exorder, ByEx)
		order = exorder
		local screenWidth = GetScreenWidth() * UIParent:GetEffectiveScale()

		-- Für jede Plakette den Abstand zur nächsten darunter bestimmen und sanft
		-- anheben, absenken oder zurücksetzen (Formeln unverändert aus der Aura).
		-- Ausnahme Ziel: bleibt an seinem Platz über dem Modell, die anderen weichen aus.
		for i = 1, count do
			local p1 = order[i]
			local plate1 = p1.plate
			local min, reset = 1000, true
			-- erst nach links, dann nach rechts, solange der x-Abstand < xspace ist
			local j, step = i - 1, -1
			while true do
				local p2 = order[j]
				if not p2 or abs(p1.ex - p2.ex) >= xspace then
					if step < 0 then
						j, step = i + 1, 1
						p2 = order[j]
						if not p2 or abs(p1.ex - p2.ex) >= xspace then
							break
						end
					else
						break
					end
				end
				if not p2.passive then
					local ydiff = p1.ypos + p1.position - p2.ypos - p2.position
					-- Eine Plakette, die das Ziel von unten überlappt, gilt als direkt darüber
					-- und wird über das Ziel hinweg nach oben geschoben
					if p2.isTarget and ydiff < 0 and ydiff > -yspace then
						ydiff = 0
					end
					-- Zeigt die Plakette darunter Debuffs, braucht sie nach oben mehr Platz:
					-- ihr Abstand zählt um diesen Betrag kleiner
					if ydiff >= 0 and ydiff - p2.extra < min then
						min = ydiff - p2.extra
					end
					if abs(p1.ypos - p2.ypos - p2.position) < yspace + p2.extra + 2 * delta then
						reset = false
					end
				end
				j = j + step
			end

			local old = p1.position
			local new = old
			if p1.isTarget or p1.passive then
				-- Zügig (ca. 0,2 s) an den natürlichen Platz zurückgleiten
				new = old > 3 * delta and old - 3 * delta or 0
			elseif old >= 2 * delta and reset then
				new = old - exp(-10 / old) * delta * cfg.speedreset
			elseif min < yspace then
				new = old + exp(-min / yspace) * delta * cfg.speedraise
			elseif old >= 2 * delta and min > yspace + 2 * delta then
				new = old - exp(-yspace / min) * delta * 0.8 * cfg.speedlower
			end
			p1.position = new

			-- Seitlich: linke Kante der Plakette ohne Verschiebung merken (Abstand zur
			-- Ankerposition); mit Verschiebung beide Seiten des Clamp-Rechtecks so setzen,
			-- dass genau die gewünschte x-Lage auf den Bildschirm passt
			local left, right = -10, 10
			local hoff = p1.hoff
			if hoff == 0 then
				if p1.wasUnshifted then
					local l = plate1:GetLeft()
					if l then
						p1.kx = l - p1.xpos
					end
				end
				p1.wasUnshifted = true
			else
				p1.wasUnshifted = false
				local w = plate1:GetWidth()
				local nl = p1.xpos + (p1.kx or -w / 2)
				left = -(nl + hoff)
				right = screenWidth - (nl + w + hoff)
			end

			-- Clamp-Rechteck nur neu setzen, wenn es sich spürbar ändert
			local bottom = -p1.ypos - new - originpos + plate1:GetHeight()
			if not p1.bottom or abs(bottom - p1.bottom) > 0.5 or abs(left - p1.left) > 0.5 or abs(right - p1.right) > 0.5 then
				p1.bottom, p1.left, p1.right = bottom, left, right
				plate1:SetClampedToScreen()
				plate1:SetClampRectInsets(left, right, upperborder, bottom)
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------
-- VII. World Update Functions: Refers new plates to 'ApplyPlateExtension()', and watches for Alpha/Transparency
-- and Highlight/Mouseover changes, and sends those changes to the appropriate handler.
-- Also processes the update queue (ie. echos)
--------------------------------------------------------------------------------------------------------------

do
	local plate, curChildren
	local WorldGetNumChildren, WorldGetChildren = WorldFrame.GetNumChildren, WorldFrame.GetChildren

	-- IsFrameNameplate: Checks to see if the frame is a Blizz nameplate
	local function IsFrameNameplate(frame)
		local threatRegion, borderRegion = frame:GetRegions()
		return borderRegion and borderRegion:GetObjectType() == "Texture" and
			borderRegion:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
	end

	-- OnWorldFrameChange: Checks for new Blizz Plates
	local function OnWorldFrameChange(...)
		for index = 1, select("#", ...) do
			plate = select(index, ...)
			if not Plates[plate] and IsFrameNameplate(plate) then
				ApplyPlateExtension(plate)
			end
		end
	end

	-- ForEachPlate
	function ForEachPlate(functionToRun, ...)
		for plate in pairs(PlatesVisible) do
			if plate.extended:IsShown() then -- Plate and extended frame both explicitly visible
				functionToRun(plate, ...)
			end
		end
	end

	-- Nameplate Fade-In
	local visibleAlpha, requestedAlpha
	local fadeInRate, fadeOutRate = .07, .2
	local function UpdateNameplateFade(plate)
		extended = plate.extended
		--if extended then
		visibleAlpha = extended.visibleAlpha
		requestedAlpha = extended.requestedAlpha
		if visibleAlpha < requestedAlpha then
			visibleAlpha = visibleAlpha + fadeInRate
			extended.visibleAlpha = visibleAlpha
			extendedSetAlpha(extended, visibleAlpha)
		else
			extended.visibleAlpha = requestedAlpha
			extendedSetAlpha(extended, visibleAlpha)
			PlatesFading[plate] = nil
		end
		--end
	end

	-- OnUpdate: This function is processed every frame!
	local queuedFunction
	local HasMouseover, LastMouseover, CurrentMouseover
	local highlightRegion
	local POLL_INTERVAL = 0.1
	local NextPoll = 0
	local LastPoll = 0
	local POLL_MIN_GAP = 0.05
	local GUID_LEARN_INTERVAL = 0.5
	local NextGUIDLearn = 0

	-- Erzwingt die Zustandsabfrage im nächsten Frame (z.B. bei Threat-Events)
	-- Höchstens 20x pro Sekunde: Das Event kommt im Raid für jedes Mitglied und
	-- hat vorher die 10-Hz-Drossel praktisch auf "jeden Frame" gesetzt.
	function TidyPlates:RequestStatePoll()
		local soon = LastPoll + POLL_MIN_GAP
		if NextPoll > soon then
			NextPoll = soon
		end
	end

	function OnUpdate(self)
		HasMouseover = false

		-- Zustandsabfrage (Aggro/Kampf/CC), gedrosselt auf POLL_INTERVAL
		local now = GetTime()
		if now >= NextPoll then
			NextPoll = now + POLL_INTERVAL
			LastPoll = now
			for plate in pairs(PlatesVisible) do
				if plate.extended:IsShown() then
					PollPlateState(plate)
				end
			end
		end

		-- GUIDs über Fokus/Pet/Gruppenziele und Fingerabdrücke lernen (2x pro Sekunde)
		if now >= NextGUIDLearn then
			NextGUIDLearn = now + GUID_LEARN_INTERVAL
			LearnGUIDs()
		end
		-- Schadens-Abgleich (Kampflog <-> Lebensbalken), jeden Frame, meist leer
		CorrelateDamage()
		-- Neue Marker-Information aus dem Kampflog sofort anwenden
		AssignFromMarkers()
		-- Plaketten stapeln (gedrosselt, nur wenn vom Theme aktiviert)
		UpdateStacking(now)

		-- Alpha - Highlight - Poll Loop
		for plate in pairs(PlatesVisible) do
			-- Alpha
			if (HasTarget) then
				plate.alpha = PlateGetAlpha(plate)
				PlateSetAlpha(plate, 1)
			end

			-- Highlight: CURSOR_UPDATE events are unreliable for GUID updates.  This provides a much better experience.
			highlightRegion = plate.extended.regions.highlight
			if HighlightIsShown(highlightRegion) then
				HasMouseover = true
				CurrentMouseover = plate
			end
		end

		-- Fade-In Loop
		for plate in pairs(PlatesFading) do
			UpdateNameplateFade(plate)
		end

		-- Process the Update Request Queues
		if massQueue[OnResetNameplate] then
			ForEachPlate(OnResetNameplate)
			for queuedFunction in pairs(massQueue) do
				massQueue[queuedFunction] = nil
			end
		else
			-- Function Queue: Runs the specified function
			for queuedFunction, run in pairs(functionQueue) do
				queuedFunction()
				functionQueue[queuedFunction] = nil
			end
			-- Mass Update Queue: Run the specified function on ALL visible plates
			if massQueue[OnUpdateNameplate] then
				for queuedFunction in pairs(massQueue) do
					massQueue[queuedFunction] = nil
				end
				ForEachPlate(OnUpdateNameplate)
			else
				for queuedFunction in pairs(massQueue) do
					massQueue[queuedFunction] = nil
					ForEachPlate(queuedFunction)
				end
			end
			-- Spefific Nameplate Function Queue: Runs the function on a specific plate
			for plate, queuedFunction in pairs(targetQueue) do
				targetQueue[plate] = nil
				queuedFunction(plate)
			end
		end

		-- Gebündelte Lebenspunkte-Updates (max. eines pro Plakette und Frame)
		for plate in pairs(healthQueue) do
			healthQueue[plate] = nil
			ProcessHealthUpdate(plate)
		end

		-- Delegate-Updates einzelner Plaketten (z.B. vom Debuff-Widget)
		for plate in pairs(delegateQueue) do
			delegateQueue[plate] = nil
			OnRequestDelegateUpdate(plate)
		end

		-- Nach neuer GUID-Zuordnung: Widgets (Debuffs) und Farbe auffrischen,
		-- laufenden Zauber des Gegners fortsetzen
		for plate in pairs(widgetQueue) do
			widgetQueue[plate] = nil
			if plate:IsShown() then
				OnRequestWidgetUpdate(plate)
				OnRequestDelegateUpdate(plate)
				local u = plate.extended.unit
				if u.guid and not u.isTarget and TidyPlates.ResumeCastForGUID then
					TidyPlates.ResumeCastForGUID(plate, u.guid)
				end
			end
		end

		-- Process Mouseover
		if HasMouseover then
			if LastMouseover ~= CurrentMouseover then
				if LastMouseover then
					OnMouseoverNameplate(LastMouseover)
				end
				OnMouseoverNameplate(CurrentMouseover)
				LastMouseover = CurrentMouseover
			end
		elseif LastMouseover then
			OnMouseoverNameplate(LastMouseover)
			LastMouseover = nil
		end

		-- Detect New Nameplates
		curChildren = WorldGetNumChildren(WorldFrame)
		if (curChildren ~= numChildren) then
			numChildren = curChildren
			OnWorldFrameChange(WorldGetChildren(WorldFrame))
		end
	end
end
--------------------------------------------------------------------------------------------------------------
-- VIII. Event Handlers: sends event-driven changes to  the appropriate gather/update handler.
--------------------------------------------------------------------------------------------------------------
do
	local events = {}
	local function EventHandler(self, event, ...)
		events[event](event, ...)
	end
	local PlateHandler = CreateFrame("Frame", nil, WorldFrame)
	PlateHandler:SetFrameStrata("TOOLTIP") -- When parented to WorldFrame, causes OnUpdate handler to run close to last
	PlateHandler:SetScript("OnEvent", EventHandler)

	-- Events
	function events:ADDON_LOADED(name)
		if name == addonName then
			-- SavedVariables werden erst nach vollständigen Laden des Addons vom Client eingespielt
			-- Initialisierung an diesem Zeitpunkt garantiert dass die Tabelle korrekt initialisiert wird
			TidyPlatesData = TidyPlatesData or {}
			PlateHandler:UnregisterEvent("ADDON_LOADED")
		end
	end

	function events:PLAYER_ENTERING_WORLD()
		PlateHandler:SetScript("OnUpdate", OnUpdate)
	end
	function events:PLAYER_REGEN_ENABLED()
		InCombat = false
		wipe(EngagedGUID)
		wipe(EngagedNames)
		SetMassQueue(OnUpdateNameplate)
	end
	function events:PLAYER_REGEN_DISABLED()
		InCombat = true
		SetMassQueue(OnUpdateNameplate)
	end

	function events:PLAYER_TARGET_CHANGED()
		HasTarget = UnitExists("target") == 1 -- Must be bool, never nil!
		if (not HasTarget) then
			currentTarget = nil
		end
		-- Nur altes/neues Ziel komplett, alle anderen nur Transparenz/Größe
		SetMassQueue(OnTargetChangedNameplate)
	end

	function events:RAID_TARGET_UPDATE()
		SetMassQueue(OnUpdateNameplate)
	end
	-- Statt alle Plaketten neu zu berechnen (feuert im Raid sehr oft), nur sofort
	-- abfragen; aktualisiert werden dann nur Plaketten, deren Aggro sich geändert hat.
	function events:UNIT_THREAT_SITUATION_UPDATE()
		TidyPlates:RequestStatePoll()
	end
	function events:UNIT_LEVEL()
		ForEachPlate(OnUpdateLevel)
	end
	function events:PLAYER_CONTROL_LOST()
		ForEachPlate(OnUpdateReaction)
	end
	events.PLAYER_CONTROL_GAINED = events.PLAYER_CONTROL_LOST
	events.UNIT_FACTION = events.PLAYER_CONTROL_LOST

	function events:UNIT_SPELLCAST_START(unitid, spell, ...)
		if unitid == "target" and currentTarget then
			OnUpdateTargetCastbar(currentTarget)
		end
	end
	events.UNIT_SPELLCAST_STOP = events.UNIT_SPELLCAST_START
	events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_START
	events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_START
	events.UNIT_SPELLCAST_DELAYED = events.UNIT_SPELLCAST_START
	events.UNIT_SPELLCAST_CHANNEL_START = events.UNIT_SPELLCAST_START
	events.UNIT_SPELLCAST_NOT_INTERRUPTIBLE = events.UNIT_SPELLCAST_START
	events.UNIT_SPELLCAST_INTERRUPTIBLE = events.UNIT_SPELLCAST_START
	events.UNIT_SPELLCAST_CHANNEL_STOP = events.UNIT_SPELLCAST_START
	events.UNIT_SPELLCAST_FAILED_QUIET = events.UNIT_SPELLCAST_START

	-- Registration of Blizzard Events
	for eventname in pairs(events) do
		PlateHandler:RegisterEvent(eventname)
	end
end

--------------------------------------------------------------------------------------------------------------
-- IX. External Commands: Allows widgets and themes to request updates to the plates.
-- Useful to make a theme respond to externally-captured data (such as the combat log)
--------------------------------------------------------------------------------------------------------------
function TidyPlates:ForceUpdate()
	SetMassQueue(OnResetNameplate)
end
function TidyPlates:Update()
	SetMassQueue(OnUpdateNameplate)
end
function TidyPlates:RequestWidgetUpdate()
	SetMassQueue(OnRequestWidgetUpdate)
end
function TidyPlates:RequestDelegateUpdate()
	SetMassQueue(OnRequestDelegateUpdate)
end
-- Delegate-Update nur für eine einzelne Plakette (im nächsten Frame)
function TidyPlates:RequestDelegateUpdateForPlate(plate)
	if plate then
		delegateQueue[plate] = true
	end
end
function TidyPlates:ActivateTheme(theme)
	if theme and type(theme) == "table" then
		TidyPlates.ActiveThemeTable, activetheme = theme, theme
		SetMassQueue(OnResetNameplate)
	end
end

TidyPlates.StartCastAnimationOnNameplate = StartCastAnimation
TidyPlates.StopCastAnimationOnNameplate = StopCastAnimation
TidyPlates.NameplatesByGUID, TidyPlates.NameplatesAll, TidyPlates.NameplatesByVisible = GUID, Plates, PlatesVisible
TidyPlates.OnNewNameplate = OnNewNameplate
TidyPlates.OnShowNameplate = OnShowNameplate
TidyPlates.OnHideNameplate = OnHideNameplate
TidyPlates.OnUpdateNameplate = OnUpdateNameplate
TidyPlates.OnResetNameplate = OnResetNameplate
TidyPlates.OnEchoNewNameplate = OnEchoNewNameplate
TidyPlates.OnUpdateHealth = OnUpdateHealth
TidyPlates.OnUpdateLevel = OnUpdateLevel
TidyPlates.OnUpdateThreatSituation = OnUpdateThreatSituation
TidyPlates.OnUpdateRaidIcon = OnUpdateRaidIcon
TidyPlates.OnUpdateHealthRange = OnUpdateHealthRange
TidyPlates.OnMouseoverNameplate = OnMouseoverNameplate
TidyPlates.OnRequestWidgetUpdate = OnRequestWidgetUpdate
TidyPlates.OnRequestDelegateUpdate = OnRequestDelegateUpdate