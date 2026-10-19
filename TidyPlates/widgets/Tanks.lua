------------------------------
-- Target Tracker
------------------------------
-- Remembers for known enemies (by GUID) whom they have targeted.
-- Sources: own target, focus, pet, the targets of all party/raid members, own target
-- and mouseover while shown, and melee/ranged auto attacks of enemies on group members
-- in the combat log. An entry stays until a newer observation replaces it, the enemy
-- dies or combat ends (a target swap of the tank no longer makes the old mob "loose").

local TrackedUnitTargets = {} -- [guid] = name of the enemy's last known target
local NewTrackedUnitTargets = {}
local TargetWatcher, CombatWatcher
local TargetsDirty = false

local partyTargets, raidTargets = {}, {}
for i = 1, 4 do partyTargets[i] = "party" .. i .. "target" end
for i = 1, 40 do raidTargets[i] = "raid" .. i .. "target" end

local function TrackUnit(unitid)
	local guid = UnitGUID(unitid)
	if guid and not NewTrackedUnitTargets[guid] then
		NewTrackedUnitTargets[guid] = UnitName(unitid .. "target") or false
	end
end

local function RequestPlateUpdate(guid)
	local plate = TidyPlates.NameplatesByGUID and TidyPlates.NameplatesByGUID[guid]
	if plate and TidyPlates.RequestDelegateUpdateForPlate then
		TidyPlates:RequestDelegateUpdateForPlate(plate)
	end
end

local function RebuildTrackedTargets()
	TargetsDirty = false
	wipe(NewTrackedUnitTargets)

	TrackUnit("target")
	TrackUnit("focus")
	TrackUnit("pettarget")

	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, numRaid do -- all raid members (previously the last one was missing)
			TrackUnit(raidTargets[i])
		end
	else
		for i = 1, GetNumPartyMembers() do -- 5-man groups were previously not evaluated at all
			TrackUnit(partyTargets[i])
		end
	end

	-- Merge into the memory; only update nameplates whose enemy has changed target.
	-- Enemies nobody looks at right now keep their last known target, and so do enemies
	-- without a target for a moment (casting, stunned, enraged, fleeing).
	for guid, targetName in pairs(NewTrackedUnitTargets) do
		if targetName and TrackedUnitTargets[guid] ~= targetName then
			TrackedUnitTargets[guid] = targetName
			RequestPlateUpdate(guid)
		end
	end
end

local function Remember(guid, targetName)
	if TrackedUnitTargets[guid] ~= targetName then
		TrackedUnitTargets[guid] = targetName
		RequestPlateUpdate(guid)
	end
end

local function ForgetAll()
	for guid in pairs(TrackedUnitTargets) do
		TrackedUnitTargets[guid] = nil
		RequestPlateUpdate(guid)
	end
end

-- Combat log: an enemy NPC auto attacking a group member has that member as its
-- target (melee and ranged auto attacks only; spells may hit random or several players)
local AUTO_ATTACKS = {SWING_DAMAGE = true, SWING_MISSED = true, RANGE_DAMAGE = true, RANGE_MISSED = true}
local AFFILIATION_OURS = 0x00000007 -- MINE, PARTY, RAID
local band = bit.band
local function CombatWatcherEvents(self, event, timestamp, subevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags)
	if event == "PLAYER_REGEN_ENABLED" then
		ForgetAll()
		return
	end
	if AUTO_ATTACKS[subevent] then
		if sourceFlags and destFlags and destName
			and band(destFlags, AFFILIATION_OURS) ~= 0
			and band(sourceFlags, AFFILIATION_OURS) == 0
			and band(sourceFlags, COMBATLOG_OBJECT_CONTROL_NPC) ~= 0
			and band(sourceFlags, COMBATLOG_OBJECT_REACTION_FRIENDLY) == 0 then
			Remember(sourceGUID, destName)
		end
	elseif subevent == "UNIT_DIED" and destGUID and TrackedUnitTargets[destGUID] ~= nil then
		TrackedUnitTargets[destGUID] = nil
	end
end

-- UNIT_TARGET/UNIT_THREAT_SITUATION_UPDATE fire practically every frame in raids:
-- rebuild at most 4x per second. Own target/focus immediately (next frame).
local TARGET_REBUILD_INTERVAL = 0.25
local nextTargetRebuild = 0
local function TargetWatcherOnUpdate(self)
	local now = GetTime()
	if now < nextTargetRebuild then
		return
	end
	nextTargetRebuild = now + TARGET_REBUILD_INTERVAL
	self:SetScript("OnUpdate", nil)
	RebuildTrackedTargets()
end

local function TargetWatcherEvents(self, event)
	if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
		nextTargetRebuild = 0
	end
	if not TargetsDirty then
		TargetsDirty = true
		self:SetScript("OnUpdate", TargetWatcherOnUpdate)
	end
end

---------------
-- Tank Monitor
---------------
local TankNames = {}
local TankWatcher
local PlayerName

-- Without any information (no GUID, never observed, or the enemy has no target for a
-- moment) the plate keeps its last result instead of falling back to "not tanked";
-- unit is cleared when the plate hides.
local function IsTankedByAnotherTank(unit)
	local targetOf
	PlayerName = PlayerName or UnitName("player")
	local guid = unit.guid
	if unit.isTarget then
		targetOf = UnitName("targettarget") -- Nameplate is a target
	elseif unit.isMouseover then
		targetOf = UnitName("mouseovertarget") -- Nameplate is a mouseover
	elseif guid then
		targetOf = TrackedUnitTargets[guid]
	end
	if targetOf and guid and (unit.isTarget or unit.isMouseover) then
		TrackedUnitTargets[guid] = targetOf
	end

	if not targetOf then
		return unit.tankedLast == true
	end
	-- "Other" tank: yourself doesn't count (own aggro is shown by the threat color)
	local tanked = TankNames[targetOf] and targetOf ~= PlayerName and true or false
	unit.tankedLast = tanked
	return tanked
end

-- In 3.3.5a UnitGroupRolesAssigned returns three booleans (isTank, isHealer, isDamage)
-- and not a string as in Cataclysm+. The old comparison with "TANK" was therefore always false.
local function IsTankUnit(unitid)
	local isTank = UnitGroupRolesAssigned(unitid)
	return isTank == true or isTank == 1
end

-- Tank stances/forms: self-assembled raids have neither Dungeon Finder roles
-- nor necessarily main tank assignments. The client sees these auras on all
-- group members (names are localized via GetSpellInfo).
local TankAuraIDs = {
	25780, -- Righteous Fury (Paladin)
	71,    -- Defensive Stance (Warrior)
	5487,  -- Bear Form (Druid)
	9634,  -- Dire Bear Form (Druid)
	48263  -- Frost Presence (Death Knight)
}
local TankAuraNames
local function HasTankAura(unitid)
	if not TankAuraNames then
		TankAuraNames = {}
		for _, id in ipairs(TankAuraIDs) do
			local name = GetSpellInfo(id)
			if name then
				TankAuraNames[#TankAuraNames + 1] = name
			end
		end
	end
	for i = 1, #TankAuraNames do
		if UnitAura(unitid, TankAuraNames[i]) then
			return true
		end
	end
	return false
end

-- Cache the aura check result per unit; only units whose auras have changed
-- are rechecked (previously: all 25 members on every change)
local AuraTankCache, AuraDirtyUnits = {}, {}
local function UnitHasTankAura(unitid)
	local v = AuraTankCache[unitid]
	if v == nil or AuraDirtyUnits[unitid] then
		v = HasTankAura(unitid)
		AuraTankCache[unitid] = v
		AuraDirtyUnits[unitid] = nil
	end
	return v
end

local OldTankNames = {}
local function TankWatcherEvents()
	OldTankNames, TankNames = TankNames, OldTankNames
	wipe(TankNames)

	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for index = 1, numRaid do
			local raidid = "raid" .. index
			local name = UnitName(raidid)
			if name and (GetPartyAssignment("MAINTANK", raidid) or GetPartyAssignment("MAINASSIST", raidid)
				or IsTankUnit(raidid) or UnitHasTankAura(raidid)) then
				TankNames[name] = true
			end
		end
	else
		-- 5-man group: roles from the Dungeon Finder
		for index = 1, GetNumPartyMembers() do
			local partyid = "party" .. index
			local name = UnitName(partyid)
			if name and (IsTankUnit(partyid) or UnitHasTankAura(partyid)) then
				TankNames[name] = true
			end
		end
		-- Own pet counts as a tank outside of raids (Hunter/Warlock)
		if HasPetUI("player") and UnitName("pet") then
			TankNames[UnitName("pet")] = true
		end
	end

	-- Only update nameplates if the tank list has actually changed
	local changed = false
	for name in pairs(TankNames) do
		if not OldTankNames[name] then
			changed = true
			break
		end
	end
	if not changed then
		for name in pairs(OldTankNames) do
			if not TankNames[name] then
				changed = true
				break
			end
		end
	end
	if changed and TidyPlates.RequestDelegateUpdate then
		TidyPlates:RequestDelegateUpdate()
	end
end

-- Auras change constantly in raids: rebuild the tank list at most 2x per second,
-- and only if something has changed on a group member
local TANK_AURA_INTERVAL = 0.5
local auraDirty, nextAuraCheck = false, 0
local function TankWatcherOnUpdate(self)
	if auraDirty and GetTime() >= nextAuraCheck then
		auraDirty = false
		nextAuraCheck = GetTime() + TANK_AURA_INTERVAL
		TankWatcherEvents()
	end
end

local function TankWatcherOnEvent(self, event, unitid)
	if event == "UNIT_AURA" then
		if unitid and (unitid:find("^raid%d") or unitid:find("^party%d")) then
			AuraDirtyUnits[unitid] = true
			auraDirty = true
		end
		return
	end
	-- Group/roles changed: unit IDs may now refer to different players
	wipe(AuraTankCache)
	TankWatcherEvents()
end

local function EnableTankWatch()
	if not TargetWatcher then
		TargetWatcher = CreateFrame("Frame")
	end
	TargetWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	TargetWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	TargetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	TargetWatcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
	TargetWatcher:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
	TargetWatcher:RegisterEvent("UNIT_TARGET")
	TargetWatcher:SetScript("OnEvent", TargetWatcherEvents)
	RebuildTrackedTargets()

	if not CombatWatcher then
		CombatWatcher = CreateFrame("Frame")
	end
	CombatWatcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	CombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
	CombatWatcher:SetScript("OnEvent", CombatWatcherEvents)

	if not TankWatcher then
		TankWatcher = CreateFrame("Frame")
	end
	TankWatcher:RegisterEvent("RAID_ROSTER_UPDATE")
	TankWatcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
	TankWatcher:RegisterEvent("PARTY_CONVERTED_TO_RAID")
	TankWatcher:RegisterEvent("PLAYER_ROLES_ASSIGNED")
	TankWatcher:RegisterEvent("UNIT_PET")
	TankWatcher:RegisterEvent("UNIT_AURA")
	TankWatcher:SetScript("OnEvent", TankWatcherOnEvent)
	TankWatcher:SetScript("OnUpdate", TankWatcherOnUpdate)
	TankWatcherEvents()
end

local function DisableTankWatch()
	if TargetWatcher then
		TargetWatcher:SetScript("OnEvent", nil)
		TargetWatcher:SetScript("OnUpdate", nil)
		TargetWatcher:UnregisterAllEvents()
		TargetWatcher = nil
		TargetsDirty = false
	end

	if CombatWatcher then
		CombatWatcher:SetScript("OnEvent", nil)
		CombatWatcher:UnregisterAllEvents()
		CombatWatcher = nil
	end
	wipe(TrackedUnitTargets)

	if TankWatcher then
		TankWatcher:SetScript("OnEvent", nil)
		TankWatcher:SetScript("OnUpdate", nil)
		TankWatcher:UnregisterAllEvents()
		TankWatcher = nil
	end
end

TidyPlatesWidgets.EnableTankWatch = EnableTankWatch
TidyPlatesWidgets.DisableTankWatch = DisableTankWatch
TidyPlatesWidgets.IsTankedByAnotherTank = IsTankedByAnotherTank
