-- Set Global Table
ThreatPlatesWidgets = ThreatPlatesWidgets or {}
local db
local _

-----------------------
-- Plater Border Widget
-----------------------
-- Scharfer, dünner Rahmen um Lebens-/Zauberleiste (Plater-Optik) statt der
-- mitskalierten Rahmengrafiken. Vier einfarbige Linien außen um den Balken.
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function SetBorderColor(self, r, g, b, a)
	if self.r == r and self.g == g and self.b == b and self.a == a then
		return
	end
	self.r, self.g, self.b, self.a = r, g, b, a
	for i = 1, 4 do
		self[i]:SetVertexColor(r, g, b, a)
	end
end

local function SetBorderSize(self, size)
	if self.size == size then
		return
	end
	self.size = size
	local bar, top, bottom, left, right = self.bar, self[1], self[2], self[3], self[4]
	top:ClearAllPoints()
	top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -size, 0)
	top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", size, 0)
	top:SetHeight(size)
	bottom:ClearAllPoints()
	bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -size, 0)
	bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", size, 0)
	bottom:SetHeight(size)
	left:ClearAllPoints()
	left:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, 0)
	left:SetWidth(size)
	right:ClearAllPoints()
	right:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, 0)
	right:SetWidth(size)
end

function ThreatPlatesWidgets.CreatePlaterBorder(bar)
	local frame = CreateFrame("Frame", nil, bar)
	frame:SetAllPoints(bar)
	frame:SetFrameLevel(bar:GetFrameLevel() + 2)
	frame.bar = bar
	for i = 1, 4 do
		local t = frame:CreateTexture(nil, "OVERLAY")
		t:SetTexture(WHITE)
		frame[i] = t
	end
	frame.SetBorderColor = SetBorderColor
	frame.SetBorderSize = SetBorderSize
	frame:SetBorderColor(0, 0, 0, 1)
	return frame
end

-- Größe eines Bildschirmpixels in Einheiten des Balkens, damit der Rahmen
-- unabhängig von UI-Skalierung und Plakettengröße scharf 1 Pixel breit bleibt.
local screenHeight
function ThreatPlatesWidgets.PixelSize(frame)
	if not screenHeight then
		local res = GetCVar("gxResolution") or ""
		screenHeight = tonumber(res:match("%d+x(%d+)")) or 768
	end
	local scale = frame:GetEffectiveScale()
	if not scale or scale <= 0 then
		return 1
	end
	return (768 / screenHeight) / scale
end

local PLATER_FONT = "Fonts\\ARIALN.TTF"

-- Restzeit rechts in der Zauberleiste (Plater: "2.0"). Kanalisierte Zauber laufen
-- rückwärts; das wird an der Laufrichtung des Balkens erkannt.
local function CastTimerOnUpdate(self)
	local bar = self.bar
	local value = bar:GetValue()
	local minv, maxv = bar:GetMinMaxValues()
	if maxv ~= self.lastMax then -- neuer Zauber
		self.lastMax, self.lastValue, self.channel = maxv, nil, nil
	end
	local last = self.lastValue
	if last and value ~= last then
		self.channel = value < last
	end
	self.lastValue = value
	local remaining = self.channel and (value - minv) or (maxv - value)
	if remaining < 0 then
		remaining = 0
	end
	self.text:SetFormattedText("%.1f", remaining)
end

-- Zauberleiste sichtbar: Namen ausblenden. Er liegt an derselben Stelle, und beim Ziel
-- (Ebene 127) würde er sonst über der Zauberleiste gezeichnet. SetAlpha reicht nicht,
-- weil SetTextColor (bei jeder Farbaktualisierung) die Transparenz zurücksetzt.
local function OnCastShow(self)
	self.lastMax, self.lastValue, self.channel = nil, nil, nil
	self.plate.visual.name:Hide()
end

local function OnCastHide(self)
	local plate = self.plate
	if plate.style and plate.style.name and plate.style.name.show then
		plate.visual.name:Show()
	end
end

function ThreatPlatesWidgets.AddCastTimer(border, size, plate)
	local text = border:CreateFontString(nil, "OVERLAY")
	text:SetFont(PLATER_FONT, size, "OUTLINE")
	text:SetPoint("RIGHT", border.bar, "RIGHT", -3, 0)
	text:SetJustifyH("RIGHT")
	border.text = text
	border.plate = plate
	border:SetScript("OnUpdate", CastTimerOnUpdate)
	border:SetScript("OnShow", OnCastShow)
	border:SetScript("OnHide", OnCastHide)
end

-- Aura-Symbole im Plater-Stil: rechteckig mit 1-px-Rahmen, große Restzeit mittig,
-- Stapel darüber, enger Abstand. Wird einmal pro Debuff-Widget angewendet.
function ThreatPlatesWidgets.StylePlaterAuras(widget)
	if widget.platerStyled then
		return
	end
	widget.platerStyled = true
	local icons = widget.AuraIconFrames
	local perRow = math.ceil(#icons / 2)
	for i, icon in ipairs(icons) do
		icon:SetWidth(24)
		icon:SetHeight(18)
		icon.Icon:SetTexCoord(0.07, 0.93, 0.18, 0.82) -- 4:3 ausschneiden
		icon.Border:Hide()
		icon.Glow:Hide()
		local border = ThreatPlatesWidgets.CreatePlaterBorder(icon)
		border:SetBorderSize(1)

		icon.TimeLeft:ClearAllPoints()
		icon.TimeLeft:SetPoint("CENTER", icon, "CENTER", 0, 0)
		icon.TimeLeft:SetFont(PLATER_FONT, 11, "OUTLINE")
		icon.TimeLeft:SetJustifyH("CENTER")
		icon.TimeLeft:SetWidth(24)

		icon.Stacks:ClearAllPoints()
		icon.Stacks:SetPoint("BOTTOM", icon, "TOP", 0, 1)
		icon.Stacks:SetFont(PLATER_FONT, 9, "OUTLINE")
		icon.Stacks:SetJustifyH("CENTER")
		icon.Stacks:SetWidth(24)

		-- Neu anordnen: zwei Reihen, 2 px Abstand, zweite Reihe mit Platz für Stapelzahlen
		icon:ClearAllPoints()
		if i == 1 then
			icon:SetPoint("LEFT", widget)
		elseif i == perRow + 1 then
			icon:SetPoint("BOTTOMLEFT", icons[1], "TOPLEFT", 0, 12)
		else
			icon:SetPoint("LEFT", icons[i - 1], "RIGHT", 2, 0)
		end
	end
end

TidyPlatesUtility:EnableGroupWatcher()
TidyPlatesWidgets:EnableAuraWatcher()
TidyPlatesWidgets:EnableTankWatch()

local TidyPlatesHubFunctions = TidyPlatesHubFunctions
local DebuffPrefixModes = TidyPlatesHubFunctions.DebuffPrefixModes

local TidyPlatesHubHelpers = TidyPlatesHubHelpers
local PrefixList = TidyPlatesHubHelpers.PrefixList
local PlayerGUID = TidyPlatesHubHelpers.PlayerGUID

local DebuffFilterModes = {}

-- All
DebuffFilterModes.all = function(debuff, list) return true end

-- All mine
DebuffFilterModes.allMine = function(debuff, list) return (debuff.caster == PlayerGUID()) end

-- Whitelist
DebuffFilterModes.whitelist = function(debuff, list)
	for _, name in ipairs(list) do
		if name == debuff.name or tonumber(name) == debuff.spellid then
			return true
		end
	end
end

-- whitelist mine
DebuffFilterModes.whitelistMine = function(debuff, list)
	local found = DebuffFilterModes.whitelist(debuff, list)
	return (found and debuff.caster == PlayerGUID())
end

-- blacklist
DebuffFilterModes.blacklist = function(debuff, list)
	for _, name in ipairs(list) do
		if name == debuff.name or tonumber(name) == debuff.spellid then
			return false
		end
	end
	return true
end

	-- blacklist mine
DebuffFilterModes.blacklistMine = function(debuff, list)
	local found = DebuffFilterModes.blacklist(debuff, list)
	return (found == true and debuff.caster == PlayerGUID())
end

-- prefix
local ParseDebuffString = nil
DebuffFilterModes.prefix = function(debuff, list)
	-- we generate the func only if used
	if ParseDebuffString == nil then
		ParseDebuffString = function(str)
			local func = nil
			local _, _, prefix, suffix = string.find(str, "(%w+)[%s%p]*(.*)")
			if prefix then
				if PrefixList[prefix] then
					str = suffix
					func = DebuffPrefixModes[PrefixList[prefix]]
				else
					str = prefix
					if suffix and suffix ~= "" then
						str = str .. " " .. suffix
					end
					func = DebuffPrefixModes[1]
				end
			end

			return str, func
		end
	end

	for _, deb in ipairs(list) do
		-- no filter?
		if deb == debuff.name or tonumber(deb) == debuff.spellid then
			return true
		end

		local name, func = ParseDebuffString(deb)
		if (name == debuff.name or tonumber(name) == debuff.spellid) and func then
			return func(debuff)
		end
	end
end

--DebuffFilterFunction
local function DebuffFilter(debuff)
	-- Debuffs on Friendly Units
	if debuff.target == 2 then -- AURA_TARGET_FRIENDLY
		return false
	end

	db = TidyPlatesThreat.db.profile
	return DebuffFilterModes[db.debuffWidget.mode](debuff, db.debuffWidget.filter)
end
-- Position/Größe der Widgets. Läuft bei jedem Anzeigen einer Plakette und bei
-- jeder Optionsänderung (ForceUpdate -> OnInitialize), daher nicht pro Update nötig.
local function ApplyLayout(plate)
	local w = plate.widgets
	if w.WidgetDebuff then
		w.WidgetDebuff:SetScale(db.debuffWidget.scale)
		w.WidgetDebuff:SetPoint(db.debuffWidget.anchor, plate, db.debuffWidget.x, db.debuffWidget.y)
	end
	if w.ComboPoints then
		w.ComboPoints:SetPoint("CENTER", plate, (db.comboWidget.x), db.comboWidget.y)
	end
	if w.ThreatLineWidget then
		w.ThreatLineWidget:SetPoint("CENTER", plate, (db.threatWidget.x), db.threatWidget.y)
	end
	if w.SocialArt then
		w.SocialArt:SetHeight(db.socialWidget.scale)
		w.SocialArt:SetWidth(db.socialWidget.scale)
		w.SocialArt:SetPoint("CENTER", plate, db.socialWidget.anchor, db.socialWidget.x, db.socialWidget.y)
	end
	if w.ClassIconWidget then
		w.ClassIconWidget:SetHeight(db.classWidget.scale)
		w.ClassIconWidget:SetWidth(db.classWidget.scale)
		w.ClassIconWidget:SetPoint((db.classWidget.anchor), plate, (db.classWidget.x), (db.classWidget.y))
	end
	if w.TotemIconWidget then
		w.TotemIconWidget:SetHeight(db.totemWidget.scale)
		w.TotemIconWidget:SetWidth(db.totemWidget.scale)
		w.TotemIconWidget:SetPoint(db.totemWidget.anchor, plate, (db.totemWidget.x), (db.totemWidget.y))
	end
	if w.UniqueIconWidget then
		w.UniqueIconWidget:SetHeight(db.uniqueWidget.scale)
		w.UniqueIconWidget:SetWidth(db.uniqueWidget.scale)
		w.UniqueIconWidget:SetPoint(db.uniqueWidget.anchor, plate, (db.uniqueWidget.x), (db.uniqueWidget.y))
	end
end

-- Kampflog-Auswertung der Debuffs nur laufen lassen, wenn das Debuff-Widget an ist
local auraWatcherActive = true -- wird beim Laden oben eingeschaltet
local function SyncAuraWatcher()
	local wanted = db.debuffWidget.ON and true or false
	if wanted ~= auraWatcherActive then
		if wanted then
			TidyPlatesWidgets:EnableAuraWatcher()
		else
			TidyPlatesWidgets:DisableAuraWatcher()
		end
		auraWatcherActive = wanted
	end
end

----------------
-- INITIALIZE --
----------------
local function OnInitialize(plate)
	db = TidyPlatesThreat.db.profile
	SyncAuraWatcher()
	local w = plate.widgets
	-- Debuff Widget
	if db.debuffWidget.ON then
		if not w.WidgetDebuff then
			local widget = TidyPlatesWidgets.CreateAuraWidget(plate)
			widget:SetPoint("CENTER", plate, db.debuffWidget.x, db.debuffWidget.y)
			widget:SetScale(db.debuffWidget.scale)
			widget:SetFrameLevel(plate:GetFrameLevel() + 1)
			widget.Filter = DebuffFilter
			w.WidgetDebuff = widget
		end
	elseif w.WidgetDebuff then
		w.WidgetDebuff:Hide()
		w.WidgetDebuff = nil
	end

	-- Social Widget
	if db.socialWidget.ON then
		if not w.SocialArt then
			local widget = ThreatPlatesWidgets.CreateSocialWidget(plate)
			widget:SetFrameLevel(plate:GetFrameLevel() + 2)
			widget:SetHeight(db.socialWidget.scale)
			widget:SetWidth(db.socialWidget.scale)
			widget:SetPoint("CENTER", plate, db.socialWidget.anchor, db.socialWidget.x, db.socialWidget.y)
			w.SocialArt = widget
		end
	elseif w.SocialArt then
		w.SocialArt:Hide()
		w.SocialArt = nil
	end

	-- Totem Widget
	if db.totemWidget.ON then
		if not w.TotemIconWidget then
			local widget = ThreatPlatesWidgets.CreateTotemIconWidget(plate)
			widget:SetHeight(db.totemWidget.scale)
			widget:SetWidth(db.totemWidget.scale)
			widget:SetFrameLevel(plate:GetFrameLevel() + 1)
			widget:SetPoint(db.totemWidget.anchor, plate, (db.totemWidget.x), (db.totemWidget.y))
			w.TotemIconWidget = widget
		end
	elseif w.TotemIconWidget then
		w.TotemIconWidget:Hide()
		w.TotemIconWidget = nil
	end

	-- Unique Widget
	if db.uniqueWidget.ON then
		if not w.UniqueIconWidget then
			local widget = ThreatPlatesWidgets.CreateUniqueIconWidget(plate)
			widget:SetHeight(db.uniqueWidget.scale)
			widget:SetWidth(db.uniqueWidget.scale)
			widget:SetFrameLevel(plate:GetFrameLevel() + 1)
			widget:SetPoint(db.uniqueWidget.anchor, plate, (db.uniqueWidget.x), (db.uniqueWidget.y))
			w.UniqueIconWidget = widget
		end
	elseif w.UniqueIconWidget then
		w.UniqueIconWidget:Hide()
		w.UniqueIconWidget = nil
	end

	-- Target Widget
	if db.targetWidget.ON then
		if not w.TargetArt then
			local widget = ThreatPlatesWidgets.CreateTargetFrameArt(plate)
			widget:SetPoint("CENTER", plate, "CENTER", 0, 0)
			w.TargetArt = widget
		end
	elseif w.TargetArt then
		w.TargetArt:Hide()
		w.TargetArt = nil
	end

	-- Class Icon Widget
	if db.classWidget.ON then
		if not w.ClassIconWidget then
			local widget = ThreatPlatesWidgets.CreateClassIconWidget(plate)
			widget:SetHeight(db.classWidget.scale)
			widget:SetWidth(db.classWidget.scale)
			widget:SetPoint((db.classWidget.anchor), plate, (db.classWidget.x), (db.classWidget.y))
			w.ClassIconWidget = widget
		end
	elseif w.ClassIconWidget then
		w.ClassIconWidget:Hide()
		w.ClassIconWidget = nil
	end

	-- Elite Overlay Widget
	if db.settings.elitehealthborder.show then
		if not w.EliteOverlay then
			local widget = ThreatPlatesWidgets.CreateEliteFrameArtOverlay(plate)
			widget:SetPoint("CENTER", plate, "CENTER", 0, 0)
			w.EliteOverlay = widget
		end
	elseif w.EliteOverlay then
		w.EliteOverlay:Hide()
		w.EliteOverlay = nil
	end

	-- Threat Graphic Widget
	if db.threat.art.ON and db.threat.ON then
		if not w.ThreatArtWidget then
			local widget = ThreatPlatesWidgets.CreateThreatArtWidget(plate)
			widget:SetPoint("CENTER", plate, "CENTER", 0, 0)
			w.ThreatArtWidget = widget
		end
	elseif w.ThreatArtWidget then
		w.ThreatArtWidget:Hide()
		w.ThreatArtWidget = nil
	end

	-- Threat Line Widget
	if db.threatWidget.ON then
		if not w.ThreatLineWidget then
			local widget = TidyPlatesWidgets.CreateThreatLineWidget(plate)
			widget:SetPoint(db.threatWidget.anchor, plate, db.threatWidget.x, db.threatWidget.y)
			widget:SetFrameLevel(plate:GetFrameLevel() + 3)
			w.ThreatLineWidget = widget
		end
	elseif w.ThreatLineWidget then
		w.ThreatLineWidget:Hide()
		w.ThreatLineWidget = nil
	end

	-- Plater-Rahmen um Lebens- und Zauberleiste
	if db.platerBorder.ON then
		if not w.PlaterHealthBorder then
			w.PlaterHealthBorder = ThreatPlatesWidgets.CreatePlaterBorder(plate.bars.healthbar)
			w.PlaterCastBorder = ThreatPlatesWidgets.CreatePlaterBorder(plate.bars.castbar)
			ThreatPlatesWidgets.AddCastTimer(w.PlaterCastBorder, db.settings.spelltext.size or 10, plate)
			-- Dunkler Hintergrund, damit der Name darunter beim Zaubern nicht durchscheint
			plate.bars.castbar:SetBackgroundColor(0.08, 0.08, 0.08, 0.9)
		end
		if w.WidgetDebuff then
			ThreatPlatesWidgets.StylePlaterAuras(w.WidgetDebuff)
		end
	elseif w.PlaterHealthBorder then
		w.PlaterHealthBorder:Hide()
		w.PlaterCastBorder:Hide()
		w.PlaterHealthBorder, w.PlaterCastBorder = nil, nil
	end

	-- Combo Point Widget
	if db.comboWidget.ON then
		if not w.ComboPoints then
			local widget = ThreatPlatesWidgets.CreateComboPointWidget(plate)
			widget:SetPoint("CENTER", plate, (db.comboWidget.x), db.comboWidget.y)
			w.ComboPoints = widget
		end
	elseif w.ComboPoints then
		w.ComboPoints:Hide()
		w.ComboPoints = nil
	end

	ApplyLayout(plate)
end
-- Plater-Rahmen: nur bei Stilen mit sichtbarem Balken (nicht Nur-Name/Totem-Symbol),
-- Farbe nach Ziel (weiß) / Mouseover (grau) / sonst schwarz
local function HasVisibleBar(barstyle)
	local tex = barstyle and barstyle.texture
	return tex and not tex:find("Empty$")
end

local function UpdatePlaterBorder(plate, unit)
	local w = plate.widgets
	local hb, cb = w.PlaterHealthBorder, w.PlaterCastBorder
	if not hb then
		return
	end
	local style = plate.style
	if HasVisibleBar(style.healthbar) then
		local size = db.platerBorder.size * ThreatPlatesWidgets.PixelSize(plate.bars.healthbar)
		hb:SetBorderSize(size)
		if unit.isTarget then
			hb:SetBorderColor(1, 1, 1, 1)
		elseif unit.isMouseover then
			hb:SetBorderColor(0.6, 0.6, 0.6, 1)
		else
			hb:SetBorderColor(0, 0, 0, 1)
		end
		hb:Show()
		if HasVisibleBar(style.castbar) then
			cb:SetBorderSize(size)
			cb:Show()
			-- Stil-Aktualisierungen blenden den Namen wieder ein; während des Zauberns verstecken
			if plate.bars.castbar:IsShown() then
				plate.visual.name:Hide()
			end
		else
			cb:Hide()
		end
	else
		hb:Hide()
		cb:Hide()
	end
end

--------------------
-- CONTEXT UPDATE --
--------------------
local function OnContextUpdate(plate, unit)
	db = TidyPlatesThreat.db.profile
	local w = plate.widgets
	-- Plater-Rahmen (Ziel/Mouseover ändern sich hier)
	if db.platerBorder.ON then
		if not w.PlaterHealthBorder then
			OnInitialize(plate)
		end
		UpdatePlaterBorder(plate, unit)
	end
	-- Debuff Widget
	if db.debuffWidget.ON then
		if not w.WidgetDebuff then
			OnInitialize(plate)
		end
		w.WidgetDebuff:UpdateContext(unit)
	end

	-- Combo Point Widget
	if db.comboWidget.ON then
		if not w.ComboPoints then
			OnInitialize(plate)
		end
		w.ComboPoints:UpdateContext(unit)
	end

	--Threat Line Widget
	if db.threatWidget.ON and unit.class == "UNKNOWN" then
		if not w.ThreatLineWidget then
			OnInitialize(plate)
		end
		w.ThreatLineWidget:UpdateContext(unit)
	end
end
-------------------
-- NORMAL UPDATE --
-------------------
local function OnUpdate(plate, unit)
	db = TidyPlatesThreat.db.profile
	local w = plate.widgets
	-- Plater-Rahmen (Stil/Größe können sich geändert haben)
	if db.platerBorder.ON then
		if not w.PlaterHealthBorder then
			OnInitialize(plate)
		end
		UpdatePlaterBorder(plate, unit)
	end
	-- Target Art
	if db.targetWidget.ON then
		if not w.TargetArt then
			OnInitialize(plate)
		end
		w.TargetArt:Update(unit)
	end

	-- Elite Overlay
	if db.settings.elitehealthborder.show then
		if not w.EliteOverlay then
			OnInitialize(plate)
		end
		w.EliteOverlay:Update(unit)
	end

	-- Social Widget Textures
	if db.socialWidget.ON then
		if not w.SocialArt then
			OnInitialize(plate)
		end
		w.SocialArt:Update(unit)
	end
	-- Class Icons
	if db.classWidget.ON then
		if not w.ClassIconWidget then
			OnInitialize(plate)
		end
		w.ClassIconWidget:Update(unit)
	end
	-- Totem Icons
	if db.totemWidget.ON then
		if not w.TotemIconWidget then
			OnInitialize(plate)
		end
		w.TotemIconWidget:Update(unit)
	end
	-- Unique Icons
	if db.uniqueWidget.ON then
		if not w.UniqueIconWidget then
			OnInitialize(plate)
		end
		w.UniqueIconWidget:Update(unit)
	end
	-- Threat Widget
	if db.threat.ON and db.threat.art.ON then
		if not w.ThreatArtWidget then
			OnInitialize(plate)
		end
		w.ThreatArtWidget:Update(unit)
	end
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local arg1 = ...
		if arg1 == "TidyPlates_ThreatPlates" then
			TidyPlatesThemeList["Threat Plates"].OnInitialize = OnInitialize
			TidyPlatesThemeList["Threat Plates"].OnUpdate = OnUpdate
			TidyPlatesThemeList["Threat Plates"].OnContextUpdate = OnContextUpdate
		end
	end
end)
f:RegisterEvent("ADDON_LOADED")