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

-----------------------------------
-- External control functions
-----------------------------------

local function StartSpellCastWatcher()
	if not CombatCastEventWatcher then
		CombatCastEventWatcher = CreateFrame("Frame")
	end
	CombatCastEventWatcher:SetScript("OnEvent", OnCombatEvent)
	CombatCastEventWatcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

local function StopSpellCastWatcher()
	if CombatCastEventWatcher then
		CombatCastEventWatcher:SetScript("OnEvent", nil)
		CombatCastEventWatcher:UnregisterAllEvents()
		CombatCastEventWatcher = nil
	end
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