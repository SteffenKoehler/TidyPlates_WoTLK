----------------------
-- CrowdControl Widget für WoW 3.3.5a
-- Angepasst für TidyPlates mit Farbintegration
----------------------

-- Globale CC Farbe
CROWD_CONTROL_COLOR = {r=0.2, g=0.5, b=1.0}

local PolledHideIn
do
	local Framelist = {} -- Key = Frame, Value = Expiration Time
	local Watcherframe = CreateFrame("Frame")
	local WatcherframeActive = false
	local select = select
	local timeToUpdate = 0

	local function CheckFramelist(self)
		local curTime = GetTime()
		if curTime < timeToUpdate then
			return
		end
		local framecount = 0
		timeToUpdate = curTime + 1
		-- Cycle through the watchlist, hiding frames which are timed-out
		for frame, expiration in pairs(Framelist) do
			-- If expired...
			if expiration < curTime then
				frame:Hide()
				Framelist[frame] = nil
			else
				-- Update the frame
				frame:Poll(expiration)
				framecount = framecount + 1
			end
		end
		-- If no more frames to watch, unregister the OnUpdate script
		if framecount == 0 then
			Watcherframe:SetScript("OnUpdate", nil)
			WatcherframeActive = false
		end
	end

	function PolledHideIn(frame, expiration)
		if expiration == 0 then
			frame:Hide()
			Framelist[frame] = nil
		else
			Framelist[frame] = expiration
			frame:Show()

			if not WatcherframeActive then
				Watcherframe:SetScript("OnUpdate", CheckFramelist)
				WatcherframeActive = true
			end
		end
	end
end

local CrowdControlMonitor = CreateFrame("Frame")

-- List of Widget Frames
local WidgetList = {}
-- GUIDs
local CrowdControlledUnits = {}
local CrowdControlExpirationTimes = {}
-- Raid Icon to GUID 		-- ex.  ByRaidIcon["SKULL"] = GUID
local ByRaidIcon = {}
-- Name to GUID
local ByName = {}

-- Komplette CC Spell IDs für 3.3.5a (übernommen aus DebuffWidget)
local CrowdControlSpells = {
	-- Allgemein
	[118] = true,		-- Polymorph
	[3355] = true,		-- Freezing Trap Effect
	[2637] = true,		-- Hibernate
	[339] = true,		-- Entangling Roots
	[122] = true,		-- Frost Nova
	[11366] = true,		-- Pyroblast
	[1776] = true,		-- Gouge
	[6770] = true,		-- Sap
	[2094] = true,		-- Blind
	[8122] = true,		-- Psychic Scream
	[1513] = true,		-- Scare Beast
	[51514] = true,		-- Hex
	[5782] = true,		-- Fear
	[5484] = true,		-- Howl of Terror
	[6358] = true,		-- Seduction
	[710] = true,		-- Banish
	[5116] = true,		-- Concussive Shot
	[24698] = true,		-- Conflagrate
	[15487] = true,		-- Silence
	[10326] = true,		-- Turn Evil
	[19386] = true,		-- Wyvern Sting
	[19503] = true,		-- Scatter Shot
	[49802] = true,		-- Kidney Shot
	[19577] = true,		-- Intimidation
	[1833] = true,		-- Cheap Shot
	[853] = true,		-- Hammer of Justice
	[10308] = true,		-- Hammer of Justice Rank 3
	[2812] = true,		-- Holy Wrath
	[20066] = true,		-- Repentance
	[44572] = true,		-- Deep Freeze
	[5246] = true,		-- Intimidating Shout
	[12798] = true,		-- Recklessness Stun
	[20252] = true,		-- Intercept
	[12809] = true,		-- Concussion Blow
	[46968] = true,		-- Shockwave
	[30283] = true,		-- Shadowfury
}

local function CrowdControlAura_Update(targetguid, targetname, sourceguid, sourcename, spellid, spellname)
	local targetUnitId
	if sourceguid == UnitGUID("player") then
		targetUnitId = "target"
	else
		local unitId = TidyPlatesUtility.GroupMembers.UnitId[sourcename]
		if unitId then
			targetUnitId = unitId .. "target"
		end
	end

	-- Register Crowd Control to Target GUID
	CrowdControlledUnits[targetguid] = spellid

	-- Attempt to gather Expiration time from Caster, or use 10 seconds
	if targetUnitId then
		local name, rank, icon, count, dispelType, duration, expires = UnitDebuff(targetUnitId, spellname)
		CrowdControlExpirationTimes[targetguid] = expires
	else
		CrowdControlExpirationTimes[targetguid] = GetTime() + 10
	end

	-- Aktualisiere alle Nameplates sofort
	if TidyPlates then
		TidyPlates:ForceUpdate()
	end
end

local function CrowdControlAura_Remove(targetguid, ...)
	CrowdControlledUnits[targetguid] = nil
	CrowdControlExpirationTimes[targetguid] = 0

	-- Aktualisiere alle Nameplates sofort
	if TidyPlates then
		TidyPlates:ForceUpdate()
	end
end

local CombatLogEvents = {
	-- Refresh Expire Time
	["SPELL_AURA_APPLIED"] = CrowdControlAura_Update,
	["SPELL_AURA_REFRESH"] = CrowdControlAura_Update,
	-- Expires Aura
	["SPELL_AURA_BROKEN"] = CrowdControlAura_Remove,
	["SPELL_AURA_BROKEN_SPELL"] = CrowdControlAura_Remove,
	["SPELL_AURA_REMOVED"] = CrowdControlAura_Remove
}

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

local function CrowdControlEventHandler(frame, event, timestamp, combatevent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId, spellName, ...)
	local CombatLogFunction = CombatLogEvents[combatevent]

	if CombatLogFunction and (bit.band(destFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) > 0) then
		if CrowdControlSpells[spellId] then
			-- Cache Unit Name
			if bit.band(sourceFlags, COMBATLOG_OBJECT_CONTROL_PLAYER) > 0 then
				ByName[destName] = destGUID
			end

			-- Cache Raid Icon Data
			for iconname, bitmask in pairs(RaidIconBit) do
				if bit.band(destFlags, bitmask) > 0 then
					ByRaidIcon[iconname] = destGUID
					break
				end
			end

			-- Update Data Table
			CombatLogFunction(destGUID, destName, sourceGUID, sourceName, spellId, spellName)

			-- Update Widget
			for widget in pairs(WidgetList) do
				widget:UpdateIcon()
			end
		end
	end
end

-- Öffentliche Funktion zur Prüfung ob Einheit unter CC steht
function TidyPlatesWidgets.IsUnitCrowdControlled(unit)
	if not unit then return false end

	local guid = unit.guid
	if not guid then
		if unit.type == "PLAYER" then
			guid = ByName[unit.name]
		elseif unit.isMarked then
			guid = ByRaidIcon[unit.raidIcon]
		end
	end

	if guid then
		local spellid = CrowdControlledUnits[guid]
		local expiration = CrowdControlExpirationTimes[guid]

		if spellid and expiration and expiration > GetTime() then
			return true
		end
	end

	return false
end

local function Enable()
	CrowdControlMonitor:SetScript("OnEvent", CrowdControlEventHandler)
	CrowdControlMonitor:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

local function Disable()
	CrowdControlMonitor:SetScript("OnEvent", nil)
	CrowdControlMonitor:UnregisterAllEvents()
	wipe(CrowdControlledUnits)
	wipe(CrowdControlExpirationTimes)
	wipe(ByName)
	wipe(ByRaidIcon)
end

------------------------------------------------- Widget Frames

-- Polled by PolledHideIn
local function UpdateWidgetTime(frame, expiration)
	local timeleft = ceil(expiration - GetTime())
	frame.TimeLeft:SetText(timeleft)
end

local function UpdateWidgetIcon(frame)
	local unit = frame.Unit
	local guid, spellid, expiration
	if unit.reaction == "HOSTILE" then
		if unit.guid then
			guid = unit.guid
		else
			if unit.type == "PLAYER" then
				guid = ByName[unit.name]
			elseif unit.isMarked then
				guid = ByRaidIcon[unit.raidIcon]
			end
		end

		if guid then
			spellid = CrowdControlledUnits[guid]
			expiration = CrowdControlExpirationTimes[guid]
			if spellid then
				frame:Show()
				local name, rank, icon = GetSpellInfo(spellid)
				frame.Icon:SetTexture(icon)
				if expiration then
					frame.TimeLeft:SetText(ceil(expiration - GetTime()))
					PolledHideIn(frame, expiration)
				end

				return true
			end
		end
	end
	frame:Hide()
end

-- Context Update (mouseover, target change)
local function UpdateWidgetContext(frame, unit)
	-- Context Update
	frame.Unit = unit
	WidgetList[frame] = true

	-- Update widget *now*, depending on context
	if unit.isTarget or unit.isMouseover or unit.isMarked then
		-- Update Widget
		frame:UpdateIcon()
	end
end

local function ClearWidgetContext(frame)
	WidgetList[frame] = nil
end

local borderart = "Interface\\AddOns\\TidyPlatesWidgets\\Aura\\CCBorder"
local backdropart = "Interface\\AddOns\\TidyPlatesWidgets\\Aura\\CCBackdrop"
local testicon = "Interface\\ICONS\\Spell_Shaman_Hex"
local font = "Interface\\Addons\\TidyPlates\\Media\\DefaultFont.ttf"
local function CreateCrowdControlWidget(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetWidth(64)
	frame:SetHeight(64)
	-- Backdrop
	frame.Backdrop = frame:CreateTexture(nil, "ARTWORK")
	frame.Backdrop:SetWidth(256)
	frame.Backdrop:SetHeight(128)
	frame.Backdrop:SetPoint("CENTER", 0, -27)
	frame.Backdrop:SetTexture(backdropart)
	-- Icon
	frame.Icon = frame:CreateTexture(nil, "BACKGROUND")
	frame.Icon:SetWidth(53)
	frame.Icon:SetHeight(33)
	frame.Icon:SetPoint("CENTER")
	frame.Icon:SetTexture(testicon)
	frame.Icon:SetTexCoord(.07, 1 - .07, .23, 1 - .23)
	-- Text
	frame.TimeLeft = frame:CreateFontString(nil, "OVERLAY")
	frame.TimeLeft:SetFont(font, 20, "OUTLINE")
	frame.TimeLeft:SetShadowOffset(1, -1)
	frame.TimeLeft:SetShadowColor(0, 0, 0, 1)
	frame.TimeLeft:SetPoint("CENTER", 0, -12)
	frame.TimeLeft:SetWidth(26)
	frame.TimeLeft:SetHeight(16)
	frame.TimeLeft:SetJustifyH("RIGHT")
	frame.TimeLeft:SetText("20")
	-- Functions
	frame.UpdateContext = UpdateWidgetContext
	frame.UpdateIcon = UpdateWidgetIcon
	frame.Poll = UpdateWidgetTime
	frame._Hide = frame.Hide
	frame.Hide = function()
		ClearWidgetContext(frame)
		frame:_Hide()
	end
	frame:Hide()
	frame:SetScale(.65)
	return frame
end

TidyPlatesWidgets.CreateCrowdControlWidget = CreateCrowdControlWidget
TidyPlatesWidgets.EnableCrowdControlWatcher = Enable
TidyPlatesWidgets.DisableCrowdControlWatcher = Disable

-- Automatisch aktivieren beim Laden
Enable()