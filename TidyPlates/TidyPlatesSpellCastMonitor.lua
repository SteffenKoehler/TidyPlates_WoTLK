local _
local RaidTargetReference = {
	STAR = 0x00100000,
	CIRCLE = 0x00200000,
	DIAMOND = 0x00400000,
	TRIANGLE = 0x00800000,
	MOON = 0x01000000,
	SQUARE = 0x02000000,
	CROSS = 0x04000000,
	SKULL = 0x08000000
}

-------------------------------------------------------------------------
-- Spell Cast Event Watcher.
-------------------------------------------------------------------------
local CombatCastEventWatcher
local CombatEventHandlers = {}

-- If you don't define a local reference,
-- the Tidy Plates table will get passed to the function.
local StartCastAnimationOnNameplate = TidyPlates.StartCastAnimationOnNameplate
local StopCastAnimationOnNameplate = TidyPlates.StopCastAnimationOnNameplate

-------------------------------------------------------------------------
-- Active casts on non-target nameplates. In 3.3.5a there is no Blizzard castbar
-- for non-targets, so the progress is calculated here.
-------------------------------------------------------------------------
local ActiveCasts = {} -- [plate] = {guid, name, startTime, endTime}
local CastTicker = CreateFrame("Frame")
CastTicker:Hide()

-- Active casts per enemy GUID, independent of the nameplate. This lets a cast be
-- resumed if the nameplate is only identified later or reappears.
local CastsByGUID = {}

local function RememberCast(guid, spell, spellid, icon, notInterruptible, startTime, endTime, channel)
	if not guid then
		return
	end
	local now = GetTime()
	for g, c in pairs(CastsByGUID) do
		if c.endTime <= now then
			CastsByGUID[g] = nil
		end
	end
	local c = CastsByGUID[guid] or {}
	c.spell, c.spellid, c.icon, c.notInterruptible = spell, spellid, icon, notInterruptible
	c.startTime, c.endTime, c.channel = startTime, endTime, channel
	CastsByGUID[guid] = c
end

local function EndCast(plate)
	ActiveCasts[plate] = nil
	local unit = plate.extended.unit
	-- If the nameplate has become the target meanwhile, Blizzard's castbar controls it
	if plate:IsShown() and not unit.isTarget then
		StopCastAnimationOnNameplate(plate)
	end
end

CastTicker:SetScript("OnUpdate", function(self)
	local now = GetTime()
	for plate, cast in pairs(ActiveCasts) do
		local unit = plate.extended.unit
		if not plate:IsShown() or unit.name ~= cast.name then
			-- Nameplate gone or now a different enemy
			ActiveCasts[plate] = nil
		elseif cast.guid and unit.guid and unit.guid ~= cast.guid then
			-- Mapping was corrected (target/mouseover): bar belongs to a different enemy
			EndCast(plate)
		elseif unit.isTarget then
			-- Target: Blizzard's castbar takes over
			ActiveCasts[plate] = nil
		elseif now >= cast.endTime then
			EndCast(plate)
		elseif cast.channel then
			plate.extended.bars.castbar:SetValue(cast.endTime - now) -- channeling runs backwards
		else
			plate.extended.bars.castbar:SetValue(now - cast.startTime)
		end
	end
	if not next(ActiveCasts) then
		self:Hide()
	end
end)

-- Starts a self-driven castbar on a non-target nameplate.
-- startTime/endTime in seconds (GetTime based).
local function StartTimedCast(plate, guid, spell, spellid, icon, notInterruptible, startTime, endTime, channel)
	local unit = plate.extended.unit
	if unit.isTarget or not endTime or endTime <= GetTime() then
		return
	end
	RememberCast(guid, spell, spellid, icon, notInterruptible, startTime, endTime, channel)
	if StartCastAnimationOnNameplate(plate, spell, spellid, icon, notInterruptible, channel, 0, endTime - startTime) then
		local cast = ActiveCasts[plate] or {}
		cast.guid, cast.name = guid, unit.name
		cast.startTime, cast.endTime, cast.channel = startTime, endTime, channel
		ActiveCasts[plate] = cast
		CastTicker:Show()
	end
end
TidyPlates.StartTimedCastOnNameplate = StartTimedCast

-- Called by the core as soon as a nameplate gets a GUID: if this enemy is
-- currently casting, the bar is shown with the remaining time.
function TidyPlates.ResumeCastForGUID(plate, guid)
	local c = CastsByGUID[guid]
	if not c then
		return
	end
	if c.endTime <= GetTime() then
		CastsByGUID[guid] = nil
		return
	end
	local active = ActiveCasts[plate]
	if active and active.guid == guid then
		return
	end
	StartTimedCast(plate, guid, c.spell, c.spellid, c.icon, c.notInterruptible, c.startTime, c.endTime, c.channel)
end

-- The target's cast, with exact times from UnitCastingInfo/UnitChannelInfo (the combat
-- log start of the target is skipped): resumed on its plate once it is no longer the target
function TidyPlates.RememberTargetCast(guid, spell, spellid, icon, notInterruptible, startTime, endTime, channel)
	RememberCast(guid, spell, spellid, icon, notInterruptible, startTime, endTime, channel)
end

-- True while a self-driven castbar runs on this plate
function TidyPlates.HasTimedCast(plate)
	return ActiveCasts[plate] ~= nil
end

-- Ends the castbar of the enemy with this GUID (success/interrupt/death)
local function StopCastByGUID(guid)
	if not guid then
		return
	end
	CastsByGUID[guid] = nil
	for plate, cast in pairs(ActiveCasts) do
		if cast.guid == guid then
			EndCast(plate)
		end
	end
end
TidyPlates.StopCastForGUID = StopCastByGUID

local function SearchNameplateByGUID(SearchFor)
	for VisiblePlate in pairs(TidyPlates.NameplatesByVisible) do
		local UnitGUID = VisiblePlate.extended.unit.guid
		if UnitGUID and UnitGUID == SearchFor then
			return VisiblePlate
		end
	end
end

local function SearchNameplateByName(NameString)
	local SearchFor = strsplit("-", NameString)
	for VisiblePlate in pairs(TidyPlates.NameplatesByVisible) do
		if VisiblePlate.extended.unit.name == SearchFor then
			return VisiblePlate
		end
	end
end

local function SearchNameplateByIcon(UnitFlags)
	local UnitIcon
	for iconname, bitmask in pairs(RaidTargetReference) do
		if bit.band(UnitFlags, bitmask) > 0 then
			UnitIcon = iconname
			break
		end
	end

	for VisiblePlate in pairs(TidyPlates.NameplatesByVisible) do
		if VisiblePlate.extended.unit.isMarked and (VisiblePlate.extended.unit.raidIcon == UnitIcon) then -- BY Icon
			return VisiblePlate
		end
	end
end

--------------------------------------
-- OnSpellCast
-- Sends cast event to an available nameplate
--------------------------------------
local function OnSpellCast(...)
	local sourceGUID, sourceName, sourceFlags, spellid, spellname = ...
	local FoundPlate = nil

	-- Gather Spell Info
	-- 3.3.5a: GetSpellInfo returns name, rank, icon, cost, isFunnel, powerType,
	-- castTime (ms), minRange, maxRange. castTime is the base value without haste.
	local spell, _, icon, _, _, _, castTime = GetSpellInfo(spellid)
	if not spell or not castTime or castTime <= 0 then
		return
	end

	if bit.band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0 then
		if bit.band(sourceFlags, COMBATLOG_OBJECT_CONTROL_PLAYER) > 0 then
			--	destination plate, by name
			FoundPlate = SearchNameplateByName(sourceName)
		elseif bit.band(sourceFlags, COMBATLOG_OBJECT_CONTROL_NPC) > 0 then
			--	destination plate, by GUID
			FoundPlate = SearchNameplateByGUID(sourceGUID)
			if not FoundPlate then
				FoundPlate = SearchNameplateByIcon(sourceFlags)
			end
		else
			return
		end
	else
		return
	end

	-- If the unit's nameplate is visible, show the cast bar
	local now = GetTime()
	if FoundPlate then
		local FoundPlateUnit = FoundPlate.extended.unit
		if not FoundPlateUnit.isTarget then
			StartTimedCast(FoundPlate, sourceGUID, spell, spellid, icon, false, now, now + castTime / 1000, false)
		end
	else
		-- Nameplate (not yet) known: remember the cast so it shows up with the
		-- remaining time once the nameplate is identified
		RememberCast(sourceGUID, spell, spellid, icon, false, now, now + castTime / 1000, false)
	end
end

function CombatEventHandlers.SPELL_CAST_START(...)
	OnSpellCast(...)
end

-- Cast finished or failed: source is the caster
function CombatEventHandlers.SPELL_CAST_SUCCESS(sourceGUID)
	StopCastByGUID(sourceGUID)
end
CombatEventHandlers.SPELL_CAST_FAILED = CombatEventHandlers.SPELL_CAST_SUCCESS

-- Interrupted or died: dest is the caster
function CombatEventHandlers.SPELL_INTERRUPT(sourceGUID, sourceName, sourceFlags, spellid, spellname, destGUID)
	StopCastByGUID(destGUID)
end
CombatEventHandlers.UNIT_DIED = CombatEventHandlers.SPELL_INTERRUPT

--------------------------------------
-- Watch Combat Log Events
--------------------------------------

local function OnCombatEvent(self, event, ...)
	-- Early filter instead of throttle: discard unknown events right away,
	-- relevant ones are never lost
	local _, combatevent = ...
	local handler = CombatEventHandlers[combatevent]
	if not handler then
		return
	end

	local _, _, sourceGUID, sourceName, sourceFlags, destGUID, _, _, spellid, spellname = ...
	if combatevent == "SPELL_CAST_START" then
		if sourceGUID ~= UnitGUID("player") and sourceGUID ~= UnitGUID("target") and spellid then
			handler(sourceGUID, sourceName, sourceFlags, spellid, spellname)
		end
	elseif next(ActiveCasts) or next(CastsByGUID) then
		-- Only evaluate stop events if any cast is being tracked at all
		handler(sourceGUID, sourceName, sourceFlags, spellid, spellname, destGUID)
	end
end

--------------------------------------
-- Casts of units the client knows by a unit token
-- The combat log only gives the start (base cast time, no channels, no stop on stuns,
-- silences or jukes). For enemies that someone in the group targets (or focus,
-- target of target, arena, boss) UnitCastingInfo/UnitChannelInfo give the exact
-- times, channels and the interruptible flag, and show when a cast ended early.
-- No events fire for these compound tokens, so they are polled.
--------------------------------------
local CAST_POLL_INTERVAL = 0.2
-- A cast the combat log just reported may not be visible through the API yet
local CAST_START_GRACE = 0.3
local CastPollUnits = {"focus", "focustarget", "targettarget", "pettarget", "boss1", "boss2", "boss3", "boss4"}
for i = 1, 5 do
	CastPollUnits[#CastPollUnits + 1] = "arena" .. i
end
local PartyTargetUnits, RaidTargetUnits = {}, {}
for i = 1, 4 do
	PartyTargetUnits[i] = "party" .. i .. "target"
end
for i = 1, 40 do
	RaidTargetUnits[i] = "raid" .. i .. "target"
end
local PolledGUIDs = {}
local CastPoller = CreateFrame("Frame")
CastPoller:Hide()

local function PollUnitCast(uid, now, targetGUID)
	if not UnitExists(uid) or UnitIsFriend("player", uid) then
		return
	end
	local guid = UnitGUID(uid)
	-- The target's castbar is Blizzard's; each enemy once per poll
	if not guid or guid == targetGUID or PolledGUIDs[guid] then
		return
	end
	PolledGUIDs[guid] = true
	local spell, _, _, icon, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(uid)
	local channel = false
	if not spell then
		spell, _, _, icon, startMS, endMS, _, notInterruptible = UnitChannelInfo(uid)
		channel = spell and true or false
	end
	local c = CastsByGUID[guid]
	if spell and startMS and endMS and endMS > startMS then
		notInterruptible = notInterruptible and true or false
		local startTime, endTime = startMS / 1000, endMS / 1000
		local plate = TidyPlates.NameplatesByGUID[guid]
		local same = c and c.spell == spell and math.abs(c.endTime - endTime) < 0.05
			and (c.notInterruptible and true or false) == notInterruptible
		if same then
			-- Known cast: only make sure it is shown (plate identified meanwhile)
			if plate and not ActiveCasts[plate] then
				TidyPlates.ResumeCastForGUID(plate, guid)
			end
		elseif plate and plate:IsShown() and not plate.extended.unit.isTarget then
			-- New cast, channel, pushback or corrected duration: (re)start with exact times
			StartTimedCast(plate, guid, spell, c and c.spellid, icon, notInterruptible, startTime, endTime, channel)
		else
			RememberCast(guid, spell, c and c.spellid, icon, notInterruptible, startTime, endTime, channel)
		end
	elseif c and c.startTime < now - CAST_START_GRACE and c.endTime > now + 0.1 then
		-- Not casting any more although the cast should still run: stunned, silenced,
		-- interrupted without a combat log event, or a player juked
		StopCastByGUID(guid)
	end
end

CastPoller:SetScript("OnUpdate", function(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed < CAST_POLL_INTERVAL then
		return
	end
	self.elapsed = 0
	local now = GetTime()
	local targetGUID = UnitGUID("target")
	for i = 1, #CastPollUnits do
		PollUnitCast(CastPollUnits[i], now, targetGUID)
	end
	local numRaid = GetNumRaidMembers()
	if numRaid > 0 then
		for i = 1, numRaid do
			PollUnitCast(RaidTargetUnits[i], now, targetGUID)
		end
	else
		for i = 1, GetNumPartyMembers() do
			PollUnitCast(PartyTargetUnits[i], now, targetGUID)
		end
	end
	wipe(PolledGUIDs)
end)

-----------------------------------
-- External control functions
-----------------------------------

local function StartSpellCastWatcher()
	if not CombatCastEventWatcher then
		CombatCastEventWatcher = CreateFrame("Frame")
	end
	CombatCastEventWatcher:SetScript("OnEvent", OnCombatEvent)
	CombatCastEventWatcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	CastPoller:Show()
end

local function StopSpellCastWatcher()
	if CombatCastEventWatcher then
		CombatCastEventWatcher:SetScript("OnEvent", nil)
		CombatCastEventWatcher:UnregisterAllEvents()
		CombatCastEventWatcher = nil
	end
	CastPoller:Hide()
end

TidyPlates.StartSpellCastWatcher = StartSpellCastWatcher
TidyPlates.StopSpellCastWatcher = StopSpellCastWatcher

-- The spell ID number of Fireball is 133
-- To test spell cast: /run TestTidyPlatesCastBar("Boognish", 133, true)
function TidyPlates.TestCastBar(SearchFor, SpellID, Shielded, ForceChanneled)
	local FoundPlate
	local spell, _, icon = GetSpellInfo(SpellID)
	local channel

	-- Search for the nameplate, by name (you could also search by GUID)
	for VisiblePlate in pairs(TidyPlates.NameplatesByVisible) do
		if VisiblePlate.extended.unit.name == SearchFor or VisiblePlate.extended.unit.guid == SearchFor then
			FoundPlate = VisiblePlate
			break
		end
	end

	-- If found, display the cast bar
	if FoundPlate then
		print("Testing Spell Cast on", SearchFor, "(no cast animation)")
		StartCastAnimationOnNameplate(FoundPlate, spell, spell, icon, Shielded, ForceChanneled)
	end
end