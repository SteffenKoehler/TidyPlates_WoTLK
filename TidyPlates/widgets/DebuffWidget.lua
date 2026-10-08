TidyPlatesWidgets.DebuffWidgetBuild = 2

local GetSpellInfo = GetSpellInfo
local PolledHideIn = TidyPlatesWidgets.PolledHideIn
local AuraMonitor = CreateFrame("Frame")

-- TODO: keep an eye on weak tables.
local WidgetList = setmetatable({}, {__mode = "kv"})
local weaktable = TidyPlatesUtility.weaktable
local WidgetGUID = setmetatable({}, weaktable)

local UpdateWidget
local TargetOfGroupMembers = {}
local function GetMaxDebuffs()
    local hub = TidyPlatesHubDamageVariables or TidyPlatesHubTankVariables
    local index = hub and hub.WidgetsDebuffMaxPerLine or 4  -- Default 4 = 6
    local map = {0, 2, 4, 6}
    return map[index] or 6
end

local AURA_TARGET_HOSTILE = 1
local AURA_TARGET_FRIENDLY = 2

local AURA_TYPE_BUFF = 1
local AURA_TYPE_DEBUFF = 6

local AURA_TYPE = {
	["Buff"] = 1,
	["Curse"] = 2,
	["Disease"] = 3,
	["Magic"] = 4,
	["Poison"] = 5,
	["Debuff"] = 6
}

local function GetAuraWidgetByGUID(guid)
	if guid then
		return WidgetGUID[guid]
	end
end

local function IsAuraShown(widget, aura)
	if widget and widget.IsShown then
		for i = 1, 6 do
			if widget.AuraIconFrames[i] and widget.AuraIconFrames[i]:IsShown() then
				return true
			end
		end
	end
end

local RaidIconBit = {
	["STAR"] = 0x00100000,
	["CIRCLE"] = 0x00200000,
	["DIAMOND"] = 0x00400000,
	["TRIANGLE"] = 0x00800000,
	["MOON"] = 0x01000000,
	["SQUARE"] = 0x02000000,
	["CROSS"] = 0x04000000,
	["SKULL"] = 0x08000000
}

local RaidIconIndex = {
	"STAR",
	"CIRCLE",
	"DIAMOND",
	"TRIANGLE",
	"MOON",
	"SQUARE",
	"CROSS",
	"SKULL"
}

-- TODO: keep an eye on weak tables.
local ByRaidIcon = setmetatable({}, weaktable)
local ByName = setmetatable({}, weaktable)

local PlayerDispelCapabilities = {
	["Curse"] = false,
	["Disease"] = false,
	["Magic"] = false,
	["Poison"] = false
}

local function UpdatePlayerDispelTypes()
	PlayerDispelCapabilities["Curse"] = IsSpellKnown(51886) or IsSpellKnown(475) or IsSpellKnown(2782)
	PlayerDispelCapabilities["Poison"] = IsSpellKnown(2782) or IsSpellKnown(32375) or IsSpellKnown(4987) or (IsSpellKnown(527) and IsSpellKnown(33167))
	PlayerDispelCapabilities["Magic"] = (IsSpellKnown(4987) and IsSpellKnown(53551)) or (IsSpellKnown(527) and IsSpellKnown(33167)) or IsSpellKnown(32375)
	PlayerDispelCapabilities["Disease"] = IsSpellKnown(4987) or IsSpellKnown(528)
end

local function CanPlayerDispel(debuffType)
	return PlayerDispelCapabilities[debuffType or ""]
end

-----------------------------------------------------
-- Default Filter
-----------------------------------------------------
local function DefaultFilterFunction(debuff)
	return (debuff.duration < 600)
end

-----------------------------------------------------
-- Update Via Search
-----------------------------------------------------

local function FindWidgetByGUID(guid)
	return WidgetGUID[guid]
end

local function FindWidgetByName(SearchFor)
	for widget in pairs(WidgetList) do
		if widget.unit.name == SearchFor then
			return widget
		end
	end
end

local function FindWidgetByIcon(raidicon)
	for widget in pairs(WidgetList) do
		if widget.unit.isMarked and widget.unit.raidIcon == raidicon then
			return widget
		end
	end
end

local function CallForWidgetUpdate(guid, raidicon, name)
	local widget

	if guid then
		widget = FindWidgetByGUID(guid)
	end

	if not widget and name then
		widget = FindWidgetByName(name)
	end

	if not widget and raidicon then
		widget = FindWidgetByIcon(raidicon)
	end

	if widget then
		UpdateWidget(widget)
	end
end

-----------------------------------------------------
-- Aura Durations
-----------------------------------------------------
-- Sicherstellen dass TidyPlatesData existiert bevor zugegriffen wird
if not TidyPlatesData then
	TidyPlatesData = {}
end
TidyPlatesData.CachedAuraDurations = TidyPlatesData.CachedAuraDurations or {}

local function GetSpellDuration(spellid)
	if spellid then
		return TidyPlatesData.CachedAuraDurations[spellid]
	end
end

local function SetSpellDuration(spellid, duration)
	if spellid then
		TidyPlatesData.CachedAuraDurations[spellid] = duration
	end
end

-----------------------------------------------------
-- Aura Instances
-----------------------------------------------------

-- TODO: keep an eye on weak tables.
local newTable = TidyPlatesUtility.NewTable
local delTable = TidyPlatesUtility.DelTable

-- Kein schwacher Table: Die Unterlisten hängen nur hier und würden sonst vom
-- Garbage Collector weggeräumt (Debuffs auf Nicht-Zielen verschwanden).
-- Aufgeräumt wird über CleanAuraLists und UNIT_DIED.
local Aura_List = {} -- Two Dimensional
local Aura_Spellid = {}
local Aura_Expiration = {}
local Aura_Stacks = {}
local Aura_Caster = {}
local Aura_Duration = {}
local Aura_Texture = {}
local Aura_Type = {}
local Aura_Target = {}

local function SetAuraInstance(guid, spellid, expiration, stacks, caster, duration, texture, auratype, auratarget)
	if guid and spellid and caster and texture then
		local aura_id = spellid .. (tostring(caster or "UNKNOWN_CASTER"))
		local aura_instance_id = guid .. aura_id
		Aura_List[guid] = Aura_List[guid] or newTable()
		Aura_List[guid][aura_id] = aura_instance_id
		Aura_Spellid[aura_instance_id] = spellid
		Aura_Expiration[aura_instance_id] = expiration
		Aura_Stacks[aura_instance_id] = stacks
		Aura_Caster[aura_instance_id] = caster
		Aura_Duration[aura_instance_id] = duration
		Aura_Texture[aura_instance_id] = texture
		Aura_Type[aura_instance_id] = auratype
		Aura_Target[aura_instance_id] = auratarget
	end
end

local function GetAuraInstance(guid, aura_id)
	if guid and aura_id then
		local aura_instance_id = guid .. aura_id
		local spellid, expiration, stacks, caster, duration, texture, auratype, auratarget
		spellid = Aura_Spellid[aura_instance_id]
		expiration = Aura_Expiration[aura_instance_id]
		stacks = Aura_Stacks[aura_instance_id]
		caster = Aura_Caster[aura_instance_id]
		duration = Aura_Duration[aura_instance_id]
		texture = Aura_Texture[aura_instance_id]
		auratype = Aura_Type[aura_instance_id]
		auratarget = Aura_Target[aura_instance_id]
		return spellid, expiration, stacks, caster, duration, texture, auratype, auratarget
	end
end

local function WipeAuraList(guid)
	if guid and Aura_List[guid] then
		local unit_aura_list = Aura_List[guid]
		for aura_id, aura_instance_id in pairs(unit_aura_list) do
			Aura_Spellid[aura_instance_id] = nil
			Aura_Expiration[aura_instance_id] = nil
			Aura_Stacks[aura_instance_id] = nil
			Aura_Caster[aura_instance_id] = nil
			Aura_Duration[aura_instance_id] = nil
			Aura_Texture[aura_instance_id] = nil
			Aura_Type[aura_instance_id] = nil
			Aura_Target[aura_instance_id] = nil
			unit_aura_list[aura_id] = nil
		end
	end
end

local function GetAuraList(guid)
	if guid and Aura_List[guid] then
		return Aura_List[guid]
	end
end

local function RemoveAuraInstance(guid, spellid, caster)
	if guid and spellid and Aura_List[guid] then
		local aura_instance_id = tostring(guid) .. tostring(spellid) .. (tostring(caster or "UNKNOWN_CASTER"))
		local aura_id = spellid .. (tostring(caster or "UNKNOWN_CASTER"))
		if Aura_List[guid][aura_id] then
			Aura_Spellid[aura_instance_id] = nil
			Aura_Expiration[aura_instance_id] = nil
			Aura_Stacks[aura_instance_id] = nil
			Aura_Caster[aura_instance_id] = nil
			Aura_Duration[aura_instance_id] = nil
			Aura_Texture[aura_instance_id] = nil
			Aura_Type[aura_instance_id] = nil
			Aura_Target[aura_instance_id] = nil
			Aura_List[guid][aura_id] = nil
		end
	end
end

local function CleanAuraLists()
	local currentTime = GetTime()
	for guid, instance_list in pairs(Aura_List) do
		local auracount = 0 -- verbleibende (nicht abgelaufene) Auren
		for aura_id, aura_instance_id in pairs(instance_list) do
			local expiration = Aura_Expiration[aura_instance_id]
			if not expiration or expiration < currentTime then
				Aura_List[guid][aura_id] = nil
				Aura_Spellid[aura_instance_id] = nil
				Aura_Expiration[aura_instance_id] = nil
				Aura_Stacks[aura_instance_id] = nil
				Aura_Caster[aura_instance_id] = nil
				Aura_Duration[aura_instance_id] = nil
				Aura_Texture[aura_instance_id] = nil
				Aura_Type[aura_instance_id] = nil
				Aura_Target[aura_instance_id] = nil
			else
				auracount = auracount + 1
			end
		end
		-- Vorher genau verkehrt herum: Listen mit laufenden Auren wurden gelöscht,
		-- Listen mit nur abgelaufenen blieben ewig liegen
		if auracount == 0 then
			Aura_List[guid] = nil
			delTable(instance_list)
		end
	end
end

local function RemoveAuraList(guid)
	if guid and Aura_List[guid] then
		WipeAuraList(guid)
		delTable(Aura_List[guid])
		Aura_List[guid] = nil
	end
end

-----------------------------------------------------
-- Aura Updating Via UnitID (Via UnitDebuff API function and UNIT_AURA events)
-----------------------------------------------------

local function UpdateAurasByUnitID(unitid)
	-- Limit to enemies, for now
	local unitType
	if UnitIsFriend("player", unitid) then
		unitType = AURA_TARGET_FRIENDLY
	else
		unitType = AURA_TARGET_HOSTILE
	end
	if unitType == AURA_TARGET_FRIENDLY then
		return
	end -- Filter

	-- Check the UnitIDs Debuffs
	local guid = UnitGUID(unitid)
	-- Reset Auras for a guid
	WipeAuraList(guid)
	-- Debuffs
	for index = 1, 32 do
		local name, _, texture, count, dispelType, duration, expirationTime, unitCaster, _, _, spellid =
			UnitDebuff(unitid, index)
		if not name then
			break
		end
		SetSpellDuration(spellid, duration)
		SetAuraInstance(guid, spellid, expirationTime, count, UnitGUID(unitCaster or ""), duration, texture, AURA_TYPE[dispelType or "Debuff"], unitType)
	end

	-- Buffs (Only for friendly units)
	if unitType == AURA_TARGET_FRIENDLY then
		for index = 1, 32 do
			local name, _, texture, count, dispelType, duration, expirationTime, unitCaster, _, _, spellid =
				UnitBuff(unitid, index)
			if not name then
				break
			end
			SetSpellDuration(spellid, duration)
			SetAuraInstance(guid, spellid, expirationTime, count, UnitGUID(unitCaster or ""), duration, texture, AURA_TYPE_BUFF, AURA_TARGET_FRIENDLY)
		end
	end

	local raidicon, name
	if UnitPlayerControlled(unitid) then
		name = UnitName(unitid)
	end
	raidicon = RaidIconIndex[GetRaidTargetIndex(unitid) or ""]
	if raidicon then
		ByRaidIcon[raidicon] = guid
	end

	CallForWidgetUpdate(guid, raidicon, name)
end

local TargetOfGroupMembersDirty = true
local function RebuildTargetOfGroupMembers()
	wipe(TargetOfGroupMembers)
	for name, unitid in pairs(TidyPlatesUtility.GroupMembers.UnitId) do
		local targetOf = unitid .. "target"
		if UnitExists(targetOf) then
			TargetOfGroupMembers[UnitGUID(targetOf)] = targetOf
		end
	end
	TargetOfGroupMembersDirty = false
end

-- Liefert true, wenn die Auren direkt über die API (UnitDebuff) aktualisiert wurden
local function UpdateAuraByLookup(guid)
	if guid == UnitGUID("target") then
		UpdateAurasByUnitID("target")
		return true
	elseif guid == UnitGUID("mouseover") then
		UpdateAurasByUnitID("mouseover")
		return true
	end
	if TargetOfGroupMembersDirty then
		RebuildTargetOfGroupMembers()
	end
	local unit = TargetOfGroupMembers[guid]
	-- unit ist bereits die Unit-ID des Ziels (z.B. "raid5target")
	if unit and UnitGUID(unit) == guid then
		UpdateAurasByUnitID(unit)
		return true
	end
	return false
end

-----------------------------------------------------
-- Aura Updating Via Combat Log
-----------------------------------------------------

local function CombatLog_ApplyAura(...)
	local timestamp, sourceGUID, destGUID, destName, spellid = ...
	local duration = GetSpellDuration(spellid)
	local _, _, texture = GetSpellInfo(spellid)
	SetAuraInstance(destGUID, spellid, GetTime() + (duration or 0), 1, sourceGUID, duration, texture, AURA_TYPE_DEBUFF, AURA_TARGET_HOSTILE)
end

local function CombatLog_RemoveAura(...)
	local timestamp, sourceGUID, destGUID, destName, spellid = ...
	RemoveAuraInstance(destGUID, spellid, sourceGUID)
end

local function CombatLog_UpdateAuraStacks(...)
	local timestamp, sourceGUID, destGUID, destName, spellid, stackCount = ...
	local duration = GetSpellDuration(spellid)
	local _, _, texture = GetSpellInfo(spellid)
	SetAuraInstance(destGUID, spellid, GetTime() + (duration or 0), stackCount, sourceGUID, duration, texture, AURA_TYPE_DEBUFF, AURA_TARGET_HOSTILE)
end

-----------------------------------------------------
-- General Events
-----------------------------------------------------

-- UNIT_TARGET feuert im Raid sehr oft; die Zuordnung wird erst bei Bedarf neu aufgebaut
local function EventUnitTarget()
	TargetOfGroupMembersDirty = true
end

local function EventPlayerTarget()
	if UnitExists("target") then
		UpdateAurasByUnitID("target")
	end
end

local function EventUnitAura(unitid)
	if unitid == "target" then
		UpdateAurasByUnitID("target")
	elseif unitid == "focus" then
		UpdateAurasByUnitID("focus")
	elseif unitid == "mouseover" then
		-- Live-Aktualisierung, solange man über einer Plakette schwebt
		UpdateAurasByUnitID("mouseover")
	end
end

-----------------------------------------------------
-- Function Reference Lists
-----------------------------------------------------
local CombatLogEvents = {
	-- Refresh Expire Time
	["SPELL_AURA_APPLIED"] = CombatLog_ApplyAura,
	["SPELL_AURA_REFRESH"] = CombatLog_ApplyAura,
	-- Add a stack
	["SPELL_AURA_APPLIED_DOSE"] = CombatLog_UpdateAuraStacks,
	-- Remove a stack
	["SPELL_AURA_REMOVED_DOSE"] = CombatLog_UpdateAuraStacks,
	-- Expires Aura
	["SPELL_AURA_BROKEN"] = CombatLog_RemoveAura,
	["SPELL_AURA_BROKEN_SPELL"] = CombatLog_RemoveAura,
	["SPELL_AURA_REMOVED"] = CombatLog_RemoveAura
}

local GeneralEvents = {
	["UNIT_TARGET"] = EventUnitTarget,
	["UNIT_AURA"] = EventUnitAura,
	["PLAYER_ENTERING_WORLD"] = CleanAuraLists,
	["PLAYER_REGEN_ENABLED"] = CleanAuraLists,
	["PLAYER_TALENT_UPDATE"] = UpdatePlayerDispelTypes,
	["ACTIVE_TALENT_GROUP_CHANGED"] = UpdatePlayerDispelTypes
}

-- Gebündelte Verarbeitung: Mehrere Debuff-Ereignisse auf denselben Gegner im selben
-- Frame (Raid: 10-30 pro Sekunde) führen nur zu einem Neu-Scan und einem Neuzeichnen.
local RAIDTARGET_MASK = 0x0FF00000
local PendingGUID, PendingIcon, PendingName = {}, {}, {}
local CLEAN_INTERVAL = 30
local nextClean = 0

local function ProcessPending(self)
	self:SetScript("OnUpdate", nil)
	for guid in pairs(PendingGUID) do
		local raidicon, name = PendingIcon[guid], PendingName[guid]
		PendingGUID[guid], PendingIcon[guid], PendingName[guid] = nil, nil, nil

		local widget = FindWidgetByGUID(guid)
			or (name and FindWidgetByName(name))
			or (raidicon and FindWidgetByIcon(raidicon))
		if widget then
			-- Genauere Daten über die API, falls jemand den Gegner im Ziel hat
			-- (aktualisiert das Widget dabei selbst)
			local updatedViaAPI = UpdateAuraByLookup(guid)
			if not (updatedViaAPI and WidgetGUID[guid]) then
				UpdateWidget(widget)
			end
		end
	end
	-- Lange Kämpfe ohne PLAYER_REGEN_ENABLED: abgelaufene Einträge zwischendurch freigeben
	local now = GetTime()
	if now >= nextClean then
		nextClean = now + CLEAN_INTERVAL
		CleanAuraLists()
	end
end

local function QueueGUID(guid, raidicon, name)
	if not guid then
		return
	end
	if not next(PendingGUID) then
		AuraMonitor:SetScript("OnUpdate", ProcessPending)
	end
	PendingGUID[guid] = true
	PendingIcon[guid] = raidicon or PendingIcon[guid]
	PendingName[guid] = name or PendingName[guid]
end

local function GetCombatEventResults(...)
	local timestamp, combatevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellid, spellName, spellSchool, auraType, stackCount = ...
	return timestamp, combatevent, sourceGUID, destGUID, destName, destFlags, destFlags, auraType, spellid, stackCount
end

local function CombatEventHandler(frame, event, ...)
	-- General Events, Passthrough
	if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then
		if GeneralEvents[event] then
			GeneralEvents[event](...)
		end
		return
	end

	-- Früher Filter statt Drossel: Die allermeisten Kampflog-Einträge (Schaden,
	-- Heilung, ...) sind keine Aura-Ereignisse und werden hier sofort verworfen.
	-- Aura-Ereignisse gehen dadurch nie verloren.
	local _, subevent = ...
	local CombatLogUpdateFunction = CombatLogEvents[subevent]
	if not CombatLogUpdateFunction then
		if subevent == "UNIT_DIED" then
			-- Auren toter Gegner sofort freigeben statt bis Kampfende zu horten
			local destGUID = select(6, ...)
			RemoveAuraList(destGUID)
		end
		return
	end

	-- Combat Log Unfiltered
	local timestamp, combatevent, sourceGUID, destGUID, destName, destFlags, destRaidFlag, auraType, spellid, stackCount = GetCombatEventResults(...)

	-- Evaluate only for enemy units, for now
	if (bit.band(destFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) == 0) then -- FILTER: ENEMY UNIT
		-- Evaluate only for debuffs
		if auraType == "DEBUFF" then -- FILTER: DEBUFF
			-- Daten aus dem Kampflog sofort merken (billig). Ein Neu-Scan über die API
			-- und das Neuzeichnen passieren gebündelt einmal pro Gegner und Frame, und
			-- nur, wenn es für den Gegner überhaupt eine Plakette gibt.
			CombatLogUpdateFunction(timestamp, sourceGUID, destGUID, destName, spellid, stackCount)

			local name, raidicon
			-- Cache Unit Name for alternative lookup strategy
			if bit.band(destFlags, COMBATLOG_OBJECT_CONTROL_PLAYER) > 0 then
				local rawName = strsplit("-", destName) -- Strip server name from players
				ByName[rawName] = destGUID
				name = rawName
			end
			-- Cache Raid Icon Data for alternative lookup strategy
			if bit.band(destRaidFlag, RAIDTARGET_MASK) > 0 then
				for iconname, bitmask in pairs(RaidIconBit) do
					if bit.band(destRaidFlag, bitmask) > 0 then
						ByRaidIcon[iconname] = destGUID
						raidicon = iconname
						break
					end
				end
			end

			QueueGUID(destGUID, raidicon, name)
		end
	end
end

-------------------------------------------------------------
-- Widget Object Functions
-------------------------------------------------------------
local function UpdateWidgetTime(frame, expiration)
	local timeleft = ceil(expiration - GetTime())
	if timeleft > 60 then
		frame.TimeLeft:SetText(ceil(timeleft / 60) .. "m")
	else
		frame.TimeLeft:SetText(ceil(timeleft))
	end
end

-- Ablauf-Schleier (Spiralen/Cooldown-Modelle werden an Plaketten in 3.3.5a nicht gezeichnet)
local SHADE_INTERVAL = 0.033
local function ShadeOnUpdate(frame, elapsed)
	local tick = frame.shadeTick + elapsed
	if tick < SHADE_INTERVAL then
		frame.shadeTick = tick
		return
	end
	frame.shadeTick = 0
	local frac = (GetTime() - frame.shadeStart) / frame.shadeDuration
	if frac <= 0.02 or frac >= 1 then
		frame.Shade:Hide()
		frame.ShadeEdge:Hide()
		frame.Grey:Hide()
	else
		local height = frame:GetHeight() * frac
		frame.Shade:SetHeight(height)
		-- Graue Kopie des Symbols auf den abgelaufenen (oberen) Teil zuschneiden; die
		-- Ausschnitt-Koordinaten des Symbols (Themes schneiden Ränder ab) übernehmen
		local grey = frame.Grey
		local left, top, _, bottom, right = frame.Icon:GetTexCoord()
		grey:SetTexCoord(left, right, top, top + (bottom - top) * frac)
		grey:SetHeight(height)
		grey:Show()
		frame.Shade:Show()
		frame.ShadeEdge:Show()
	end
end

local function UpdateIcon(frame, texture, expiration, stacks, duration)
	if frame and texture and expiration then
		-- Icon
		frame.Icon:SetTexture(texture)

		-- Ablauf-Anzeige, wenn das Theme sie wünscht (widget.showSpiral) und die Dauer
		-- bekannt ist: der abgelaufene Teil wächst von oben nach unten (ausgegraut, leicht
		-- abgedunkelt), goldene Kante an seiner Unterseite
		if frame:GetParent().showSpiral and duration and duration > 0 then
			frame.shadeStart, frame.shadeDuration = expiration - duration, duration
			frame.shadeTick = SHADE_INTERVAL
			frame:SetScript("OnUpdate", ShadeOnUpdate)
			frame.Grey:SetTexture(texture)
			frame.Grey:SetDesaturated(true)
		else
			frame:SetScript("OnUpdate", nil)
			frame.Shade:Hide()
			frame.ShadeEdge:Hide()
			frame.Grey:Hide()
		end

		-- Stacks
		if stacks > 1 then
			frame.Stacks:SetText(stacks)
		else
			frame.Stacks:SetText("")
		end

		-- Expiration
		UpdateWidgetTime(frame, expiration)
		frame:Show()
		PolledHideIn(frame, expiration)
	else
		PolledHideIn(frame, 0)
	end
end

local AuraSlotspellid = {}
local AuraSlotPriority = {}

local function debuffSort(a, b)
	return a.priority < b.priority
end

local DebuffCache = {}
-- Wiederverwendete Aura-Tabellen (vorher bei jedem Neuzeichnen neu angelegt)
local AuraPool = {}

local function UpdateIconGrid(frame, guid)
	local AuraIconFrames = frame.AuraIconFrames
	local AurasOnUnit = GetAuraList(guid)
	local AuraSlotIndex = 1
	local maxDebuffs = GetMaxDebuffs()

	wipe(DebuffCache)
	local debuffCount = 0

	-- Cache displayable debuffs
	if AurasOnUnit then
		frame:Show()
		local now = GetTime()
		for instanceid in pairs(AurasOnUnit) do
			local aura = AuraPool[debuffCount + 1]
			if not aura then
				aura = {}
				AuraPool[debuffCount + 1] = aura
			end
			aura.spellid, aura.expiration, aura.stacks, aura.caster, aura.duration, aura.texture, aura.type, aura.target =
				GetAuraInstance(guid, instanceid)

			if tonumber(aura.spellid) then
				aura.name = GetSpellInfo(tonumber(aura.spellid))
				aura.unit = frame.unit

				-- Call Filter Function
				local show, priority = frame.Filter(aura)
				aura.priority = priority or 10

				-- Get Order/Priority
				if show and aura.expiration and aura.expiration > now then
					debuffCount = debuffCount + 1
					DebuffCache[debuffCount] = aura
				end
			end
		end
	end

	-- Display Auras
	if debuffCount > 0 then
		sort(DebuffCache, debuffSort)
		for index = 1, #DebuffCache do
			local cachedaura = DebuffCache[index]
			if cachedaura.spellid and cachedaura.expiration then
				UpdateIcon(AuraIconFrames[AuraSlotIndex], cachedaura.texture, cachedaura.expiration, cachedaura.stacks, cachedaura.duration)
				AuraSlotIndex = AuraSlotIndex + 1
			end
			if AuraSlotIndex > maxDebuffs then
				break
			end
		end
	end

	-- Clear Extra Slots
	for index = AuraSlotIndex, maxDebuffs do
		UpdateIcon(AuraIconFrames[index])
	end

	wipe(DebuffCache)
end

function UpdateWidget(frame)
	-- Check for ID
	local unit = frame.unit
	local guid = unit.guid

	if not guid then
		-- Attempt to ID widget via Name or Raid Icon
		if unit.type == "PLAYER" then
			guid = ByName[unit.name]
		elseif unit.isMarked then
			guid = ByRaidIcon[unit.raidIcon]
		end

		if guid then
			unit.guid = guid -- Feed data back into unit table		-- Testing
		else
			frame:Hide()
			return
		end
	end

	UpdateIconGrid(frame, guid)
	-- Delegate Update (für debuff-abhängige Skalierung/Transparenz) nur für die
	-- betroffene Plakette statt für alle
	local extended = frame:GetParent()
	if extended and extended.parentPlate and TidyPlates.RequestDelegateUpdateForPlate then
		TidyPlates:RequestDelegateUpdateForPlate(extended.parentPlate)
	else
		TidyPlates:RequestDelegateUpdate()
	end
end

local function UpdateWidgetTarget(frame)
	UpdateIconGrid(frame, UnitGUID("target"))
end

-- Context Update (mouseover, target change)
local function UpdateWidgetContext(frame, unit)
	local guid = unit.guid
	frame.unit = unit
	frame.guidcache = guid

	WidgetList[frame] = true
	if guid then
		WidgetGUID[guid] = frame
	end

	if unit.isTarget then
		UpdateAurasByUnitID("target")
	elseif unit.isMouseover then
		UpdateAurasByUnitID("mouseover")
	end

	local raidicon, name
	if unit.isMarked then
		raidicon = unit.raidIcon
		if guid and raidicon then
			ByRaidIcon[raidicon] = guid
		end
	end
	if unit.type == "PLAYER" and unit.reaction == "HOSTILE" then
		name = unit.name
	end

	CallForWidgetUpdate(guid, raidicon, name)
end

local function ClearWidgetContext(frame)
	if frame.guidcache then
		WidgetGUID[frame.guidcache] = nil
		frame.unit = nil
	end
	WidgetList[frame] = nil
end

-------------------------------------------------------------
-- Widget Frames
-------------------------------------------------------------
local AuraBorderArt = "Interface\\AddOns\\TidyPlatesWidgets\\Aura\\AuraFrame" -- FINISH ART
local AuraGlowArt = "Interface\\AddOns\\TidyPlatesWidgets\\Aura\\AuraGlow"
local AuraHighlightArt = "Interface\\AddOns\\TidyPlatesWidgets\\Aura\\CCBorder" -- AuraBorderArt, AuraHighlightArt
local AuraTestArt = ""
local AuraFont = "Interface\\Addons\\TidyPlates\\Media\\DefaultFont.ttf"

local function Enable()
	AuraMonitor:SetScript("OnEvent", CombatEventHandler)
	AuraMonitor:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	for event in pairs(GeneralEvents) do
		AuraMonitor:RegisterEvent(event)
	end

	TidyPlatesUtility:EnableGroupWatcher()

	if not TidyPlatesData.CachedAuraDurations then
		TidyPlatesData.CachedAuraDurations = {}
	end
end

local function Disable()
	AuraMonitor:SetScript("OnEvent", nil)
	AuraMonitor:SetScript("OnUpdate", nil)
	AuraMonitor:UnregisterAllEvents()
	wipe(PendingGUID)
	--TidyPlatesUtility:DisableGroupWatcher()
end

-- Create an Aura Icon
local function CreateAuraIconFrame(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetWidth(26)
	frame:SetHeight(14)
	-- Icon
	frame.Icon = frame:CreateTexture(nil, "BACKGROUND")
	frame.Icon:SetAllPoints(frame)
	frame.Icon:SetTexCoord(.07, 1 - .07, .23, 1 - .23) -- obj:SetTexCoord(left,right,top,bottom)
	-- Border
	frame.Border = frame:CreateTexture(nil, "ARTWORK")
	frame.Border:SetWidth(32)
	frame.Border:SetHeight(32)
	frame.Border:SetPoint("CENTER", 1, -2)
	frame.Border:SetTexture(AuraBorderArt)
	-- Glow
	frame.Glow = frame:CreateTexture(nil, "ARTWORK")
	frame.Glow:SetAllPoints(frame.Border)
	frame.Glow:SetTexture(AuraGlowArt)
	-- Ablauf-Anzeige (nur aktiv, wenn das Theme sie einschaltet): abgelaufener Teil
	-- ausgegraut (entsättigte Kopie des Symbols) und leicht abgedunkelt, goldene Kante
	local grey = frame:CreateTexture(nil, "BORDER")
	grey:SetDesaturated(true)
	grey:SetPoint("TOPLEFT", frame, "TOPLEFT")
	grey:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
	grey:Hide()
	frame.Grey = grey
	local shade = frame:CreateTexture(nil, "OVERLAY")
	shade:SetTexture(0, 0, 0, 0.35)
	shade:SetPoint("TOPLEFT", frame, "TOPLEFT")
	shade:SetPoint("TOPRIGHT", frame, "TOPRIGHT")
	shade:Hide()
	frame.Shade = shade
	local edge = frame:CreateTexture(nil, "OVERLAY")
	edge:SetTexture(1, 0.82, 0.2, 1)
	edge:SetHeight(1)
	edge:SetPoint("TOPLEFT", shade, "BOTTOMLEFT")
	edge:SetPoint("TOPRIGHT", shade, "BOTTOMRIGHT")
	edge:Hide()
	frame.ShadeEdge = edge
	-- Texte auf eigener Ebene über dem Schleier
	local textFrame = CreateFrame("Frame", nil, frame)
	textFrame:SetAllPoints(frame)
	textFrame:SetFrameLevel(frame:GetFrameLevel() + 2)
	frame.TextFrame = textFrame
	--  Time Text
	frame.TimeLeft = textFrame:CreateFontString(nil, "OVERLAY")
	frame.TimeLeft:SetFont(AuraFont, 9, "OUTLINE")
	frame.TimeLeft:SetShadowOffset(1, -1)
	frame.TimeLeft:SetShadowColor(0, 0, 0, 1)
	frame.TimeLeft:SetPoint("RIGHT", 0, 8)
	frame.TimeLeft:SetWidth(26)
	frame.TimeLeft:SetHeight(16)
	frame.TimeLeft:SetJustifyH("RIGHT")
	--  Stacks
	frame.Stacks = textFrame:CreateFontString(nil, "OVERLAY")
	frame.Stacks:SetFont(AuraFont, 10, "OUTLINE")
	frame.Stacks:SetShadowOffset(1, -1)
	frame.Stacks:SetShadowColor(0, 0, 0, 1)
	frame.Stacks:SetPoint("RIGHT", 0, -6)
	frame.Stacks:SetWidth(26)
	frame.Stacks:SetHeight(16)
	frame.Stacks:SetJustifyH("RIGHT")
	-- Information about the currently displayed aura
	frame.AuraInfo = {Name = "", Icon = "", Stacks = 0, Expiration = 0, Type = ""}
	--frame.Poll = UpdateWidgetTime
	frame.Poll = parent.PollFunction
	frame:Hide()
	return frame
end

-- Create the Main Widget Body and Icon Array
local function CreateAuraWidget(parent)
	-- Create Base frame
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetWidth(128)
	frame:SetHeight(32)
	frame:Show()
	-- Create Icon Array
	frame.PollFunction = UpdateWidgetTime
	frame.AuraIconFrames = {}
	local AuraIconFrames = frame.AuraIconFrames

	local maxDebuffs = GetMaxDebuffs()
	for index = 1, maxDebuffs do
		AuraIconFrames[index] = CreateAuraIconFrame(frame)
	end
	local FirstRowCount = min(maxDebuffs / 2)
	-- Set Anchors
	AuraIconFrames[1]:SetPoint("LEFT", frame)
	for index = 2, FirstRowCount do
		AuraIconFrames[index]:SetPoint("LEFT", AuraIconFrames[index - 1], "RIGHT", 5, 0)
	end
	AuraIconFrames[FirstRowCount + 1]:SetPoint("BOTTOMLEFT", AuraIconFrames[1], "TOPLEFT", 0, 8)
	for index = (FirstRowCount + 2), GetMaxDebuffs() do
		AuraIconFrames[index]:SetPoint("LEFT", AuraIconFrames[index - 1], "RIGHT", 5, 0)
	end
	-- Functions
	frame._Hide = frame.Hide
	frame.Hide = function()
		ClearWidgetContext(frame)
		frame:_Hide()
	end
	frame:SetScript("OnHide", function()
		for index = 1, #AuraIconFrames do
			PolledHideIn(AuraIconFrames[index], 0)
		end
	end)
	frame.Filter = DefaultFilterFunction
	frame.UpdateContext = UpdateWidgetContext
	frame.Update = UpdateWidgetContext
	frame.UpdateTarget = UpdateWidgetTarget
	return frame
end

-----------------------------------------------------
-- External
-----------------------------------------------------
TidyPlatesWidgets.GetAuraWidgetByGUID = GetAuraWidgetByGUID
TidyPlatesWidgets.IsAuraShown = IsAuraShown
TidyPlatesWidgets.CanPlayerDispel = CanPlayerDispel

TidyPlatesWidgets.CreateAuraWidget = CreateAuraWidget
TidyPlatesWidgets.EnableAuraWatcher = Enable
TidyPlatesWidgets.DisableAuraWatcher = Disable

do
	local CCSpells = {
		-- general
		[GetSpellInfo(118)] = true, -- Polymorph
		[GetSpellInfo(3355)] = true, -- Freezing Trap Effect
		[GetSpellInfo(6770)] = true, -- Sap
		[GetSpellInfo(6358)] = true, -- Seduction (succubus)
		[GetSpellInfo(60210)] = true, -- Freezing Arrow
		[GetSpellInfo(45524)] = true, -- Chains of Ice
		[GetSpellInfo(33786)] = true, -- Cyclone
		[GetSpellInfo(53308)] = true, -- Entangling Roots
		[GetSpellInfo(2637)] = true, -- Hibernate
		[GetSpellInfo(20066)] = true, -- Repentance
		[GetSpellInfo(9484)] = true, -- Shackle Undead
		[GetSpellInfo(51722)] = true, -- Dismantle
		[GetSpellInfo(710)] = true, -- Banish
		[GetSpellInfo(12809)] = true, -- Concussion Blow
		[GetSpellInfo(676)] = true, -- Disarm
		-- Death Knight
		[GetSpellInfo(47476)] = true, -- Strangulate
		[GetSpellInfo(49203)] = true, -- Hungering Cold
		[GetSpellInfo(47481)] = true, -- Gnaw
		[GetSpellInfo(49560)] = true, -- Death Grip
		-- Druid
		[GetSpellInfo(339)] = true, -- Entangling Roots
		[GetSpellInfo(8983)] = true, -- Bash
		[GetSpellInfo(16979)] = true, -- Feral Charge - Bear
		[GetSpellInfo(45334)] = true, -- Feral Charge Effect
		[GetSpellInfo(22570)] = true, -- Maim
		[GetSpellInfo(49803)] = true, -- Pounce
		-- Hunter
		[GetSpellInfo(5116)] = true, -- Concussive Shot
		[GetSpellInfo(19503)] = true, -- Scatter Shot
		[GetSpellInfo(19386)] = true, -- Wyvern Sting
		[GetSpellInfo(53548)] = true, -- Pin (Crab)
		[GetSpellInfo(4167)] = true, -- Web (Spider)
		[GetSpellInfo(55509)] = true, -- Venom Web Spray (Silithid)
		[GetSpellInfo(24394)] = true, -- Intimidation
		[GetSpellInfo(19577)] = true, -- Intimidation (stun)
		[GetSpellInfo(53568)] = true, -- Sonic Blast (Bat)
		[GetSpellInfo(53543)] = true, -- Snatch (Bird of Prey)
		[GetSpellInfo(50541)] = true, -- Clench (Scorpid)
		[GetSpellInfo(55492)] = true, -- Froststorm Breath (Chimaera)
		[GetSpellInfo(26090)] = true, -- Pummel (Gorilla)
		[GetSpellInfo(53575)] = true, -- Tendon Rip (Hyena)
		[GetSpellInfo(53589)] = true, -- Nether Shock (Nether Ray)
		[GetSpellInfo(53562)] = true, -- Ravage (Ravager)
		[GetSpellInfo(1513)] = true, -- Scare Beast
		[GetSpellInfo(64803)] = true, -- Entrapment
		-- Mage
		[GetSpellInfo(31661)] = true, -- Dragon's Breath
		[GetSpellInfo(44572)] = true, -- Deep Freeze
		[GetSpellInfo(122)] = true, -- Frost Nova
		[GetSpellInfo(33395)] = true, -- Freeze (Frost Water Elemental)
		[GetSpellInfo(55021)] = true, -- Silenced - Improved Counterspell
		-- Paladin
		[GetSpellInfo(853)] = true, -- Hammer of Justice
		[GetSpellInfo(10326)] = true, -- Turn Evil
		[GetSpellInfo(2812)] = true, -- Holy Wrath
		[GetSpellInfo(31935)] = true, -- Avengers Shield
		-- Priest
		[GetSpellInfo(8122)] = true, -- Psychic Scream
		[GetSpellInfo(605)] = true, -- Dominate Mind (Mind Control)
		[GetSpellInfo(15487)] = true, -- Silence
		[GetSpellInfo(64044)] = true, -- Psychic Horror
		-- Rogue
		[GetSpellInfo(408)] = true, -- Kidney Shot
		[GetSpellInfo(2094)] = true, -- Blind
		[GetSpellInfo(1833)] = true, -- Cheap Shot
		[GetSpellInfo(1776)] = true, -- Gouge
		[GetSpellInfo(1330)] = true, -- Garrote - Silence
		-- Shaman
		[GetSpellInfo(51514)] = true, -- Hex
		[GetSpellInfo(8056)] = true, -- Frost Shock
		[GetSpellInfo(64695)] = true, -- Earthgrab (Earthbind Totem with Storm, Earth and Fire talent)
		[GetSpellInfo(3600)] = true, -- Earthbind (Earthbind Totem)
		[GetSpellInfo(39796)] = true, -- Stoneclaw Stun (Stoneclaw Totem)
		[GetSpellInfo(8034)] = true, -- Frostbrand Weapon
		-- Warlock
		[GetSpellInfo(6215)] = true, -- Fear
		[GetSpellInfo(5484)] = true, -- Howl of Terror
		[GetSpellInfo(30283)] = true, -- Shadowfury
		[GetSpellInfo(22703)] = true, -- Infernal Awakening
		[GetSpellInfo(6789)] = true, -- Death Coil
		[GetSpellInfo(24259)] = true, -- Spell Lock
		-- Warrior
		[GetSpellInfo(5246)] = true, -- Initmidating Shout
		[GetSpellInfo(46968)] = true, -- Shockwave
		[GetSpellInfo(6552)] = true, -- Pummel
		[GetSpellInfo(58357)] = true, -- Heroic Throw silence
		[GetSpellInfo(7922)] = true, -- Charge
		[GetSpellInfo(47995)] = true, -- Intercept (Stun)
		[GetSpellInfo(12323)] = true, -- Piercing Howl
		-- Racials
		[GetSpellInfo(20549)] = true, -- War Stomp (Tauren)
		[GetSpellInfo(28730)] = true, -- Arcane Torrent (Bloodelf)
		[GetSpellInfo(47779)] = true, -- Arcane Torrent (Bloodelf)
		[GetSpellInfo(50613)] = true, -- Arcane Torrent (Bloodelf)
		-- Engineering
		[GetSpellInfo(67890)] = true -- Cobalt Frag Bomb
	}
	TidyPlatesWidgets.CCSpells = CCSpells
end

-----------------------------------------------------
-- Debuff Library
-----------------------------------------------------

function DynamicHashTableSize(entries)
	if (entries == 0) then
		return 36
	else
		return math.pow(2, math.ceil(math.log(entries) / math.log(2))) * 40 + 36
	end
end

local TableMemory

TableMemory = function(pTable, level)
	level = level or 1
	local sum = 0
	local entries = 0
	local indent = " "
	for s = 1, level do
		indent = indent .. " "
	end

	for i, v in pairs(pTable) do
		if type(v) == "table" then
			local mem = TableMemory(v, level + 1)
			sum = sum + mem
			entries = entries + 1
		else
			entries = entries + 1
		end
	end
	return DynamicHashTableSize(entries) + sum, entries
end