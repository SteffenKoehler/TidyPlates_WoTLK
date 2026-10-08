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
-- Unterbrechungen pro Klasse (Zauber-IDs, Namen werden über GetSpellInfo lokalisiert).
-- Bekannt ist ein Zauber, wenn GetSpellCooldown(Name) etwas liefert (= im Zauberbuch).
local _, PlayerClass = UnitClass("player")
local InterruptIDs = {
	ROGUE = {1766},              -- Tritt
	WARRIOR = {6552, 72},        -- Zuschlagen, Schildhieb
	DEATHKNIGHT = {47528},       -- Gedankenfrost
	MAGE = {2139},               -- Gegenzauber
	SHAMAN = {57994},            -- Windstoß
	PRIEST = {15487},            -- Stille (Schatten)
	DRUID = {16979, 5211},       -- Wilde Attacke (Bär), Hieb
	HUNTER = {34490}             -- Unterdrückender Schuss
}
local InterruptNames
local function GetInterruptNames()
	if not InterruptNames then
		InterruptNames = {}
		for _, id in ipairs(InterruptIDs[PlayerClass] or {}) do
			local name = GetSpellInfo(id)
			if name then
				InterruptNames[#InterruptNames + 1] = name
			end
		end
	end
	return InterruptNames
end

-- true = eine eigene Unterbrechung ist (spätestens bis Zauberende) bereit,
-- false = alle auf Abklingzeit/gerade nicht nutzbar, nil = Klasse hat keine
local function InterruptReady(castRemaining)
	local known, now = false, GetTime()
	for _, name in ipairs(GetInterruptNames()) do
		local start, duration = GetSpellCooldown(name)
		if start then
			known = true
			local usable, noMana = IsUsableSpell(name)
			-- Globale Abklingzeit (<= 1.5 s) zählt nicht
			local cd = (start > 0 and duration > 1.5) and (start + duration - now) or 0
			if (usable or noMana) and cd <= (castRemaining or 0) then
				return true
			end
		end
	end
	if known then
		return false
	end
end

-- Farbe der Zauberleiste: nicht unterbrechbar / Unterbrechung bereit / Abklingzeit
function ThreatPlatesWidgets.PlaterCastColor(unit, castRemaining)
	local pc = TidyPlatesThreat.db.profile.platerCast
	local c
	if unit.spellIsShielded then
		c = pc.colorShield
	elseif pc.kickCooldown and InterruptReady(castRemaining) == false then
		c = pc.colorCooldown
	else
		c = pc.colorReady
	end
	return c.r, c.g, c.b, 1
end

local function UpdateCastState(self, remaining)
	local plate = self.plate
	local unit = plate.unit
	if self.SetShielded then -- Classic: Schild-Rahmen bei nicht unterbrechbaren Zaubern
		self:SetShielded(unit.spellIsShielded)
	end
	local pc = TidyPlatesThreat.db.profile.platerCast
	if not pc.ON then
		return
	end
	self.bar:SetForegroundColor(ThreatPlatesWidgets.PlaterCastColor(unit, remaining))
	local shielded = unit.spellIsShielded and pc.shieldIcon
	if shielded then
		self.shield:Show()
	else
		self.shield:Hide()
	end
	plate.visual.spellicon:SetDesaturated(shielded and true or false)
end

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
	-- Farbe/Schloss 10x pro Sekunde nachführen (Abklingzeit der eigenen Unterbrechung)
	local now = GetTime()
	if not self.nextState or now >= self.nextState then
		self.nextState = now + 0.1
		UpdateCastState(self, remaining)
	end
end

-- Zauberleiste sichtbar: Namen ausblenden. Er liegt an derselben Stelle, und beim Ziel
-- (Ebene 127) würde er sonst über der Zauberleiste gezeichnet. SetAlpha reicht nicht,
-- weil SetTextColor (bei jeder Farbaktualisierung) die Transparenz zurücksetzt.
local function OnCastShow(self)
	self.lastMax, self.lastValue, self.channel, self.nextState = nil, nil, nil, nil
	if self.Place then
		self:Place()
	end
	if not self.keepName then
		self.plate.visual.name:Hide()
	end
end

local function OnCastHide(self)
	local plate = self.plate
	if plate.style and plate.style.name and plate.style.name.show then
		plate.visual.name:Show()
	end
	self.shield:Hide()
	plate.visual.spellicon:SetDesaturated(false)
end

function ThreatPlatesWidgets.AddCastTimer(border, size, plate)
	local text = border:CreateFontString(nil, "OVERLAY")
	text:SetFont(PLATER_FONT, size, "OUTLINE")
	text:SetPoint("RIGHT", border.bar, "RIGHT", -3, 0)
	text:SetJustifyH("RIGHT")
	border.text = text
	border.plate = plate
	-- Schloss am Zaubersymbol für nicht unterbrechbare Zauber
	local shield = border:CreateTexture(nil, "OVERLAY")
	shield:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
	shield:SetWidth(12)
	shield:SetHeight(14)
	shield:SetPoint("CENTER", plate.visual.spellicon, "BOTTOMRIGHT", -1, 2)
	shield:Hide()
	border.shield = shield
	border:SetScript("OnUpdate", CastTimerOnUpdate)
	border:SetScript("OnShow", OnCastShow)
	border:SetScript("OnHide", OnCastHide)
end

-- Ziel-Markierung im NotPlater-Stil: Eck-/Seitengrafiken um den Balken plus Leuchten
-- oben und unten. Grafiken und Maße aus NotPlater (MIT-Lizenz, siehe Media\NotPlater\LICENSE.txt).
local NP_PATH = "Interface\\AddOns\\TidyPlates_ThreatPlates\\Media\\NotPlater\\"
-- coords mit 4 Einträgen = Ecken (oben links, unten links, unten rechts, oben rechts),
-- mit 2 Einträgen = Seiten (links, rechts)
ThreatPlatesWidgets.TargetIndicators = {
	["Silver"] = {path = "PETBATTLEHUD", width = 6, height = 6, autoScale = true, x = 1, y = 1,
		coords = {{336/512, 356/512, 454/512, 474/512}, {336/512, 356/512, 474/512, 495/512},
			{356/512, 377/512, 474/512, 495/512}, {356/512, 377/512, 454/512, 474/512}}},
	["Magneto"] = {path = "RelicIconFrame", width = 8, height = 10, autoScale = true, x = 2, y = 2,
		coords = {{0, .5, 0, .5}, {0, .5, .5, 1}, {.5, 1, .5, 1}, {.5, 1, 0, .5}}},
	["Gray Bold"] = {path = "UI-Icon-QuestBorder", width = 10, height = 10, autoScale = true, x = 2, y = 2, desaturated = true,
		coords = {{0, .5, 0, .5}, {0, .5, .5, 1}, {.5, 1, .5, 1}, {.5, 1, 0, .5}}},
	["Pins"] = {path = "UI-ItemSockets", width = 4, height = 4, x = 2, y = 2, desaturated = true,
		coords = {{145/256, 161/256, 3/256, 19/256}, {145/256, 161/256, 19/256, 3/256},
			{161/256, 145/256, 19/256, 3/256}, {161/256, 145/256, 3/256, 19/256}}},
	["Ornament"] = {path = "PETJOURNAL", width = 18, height = 12, hscale = 1.2, autoScale = true, x = 14, y = 0,
		coords = {{124/512, 161/512, 71/512, 99/512}, {119/512, 156/512, 29/512, 57/512}}},
	["Golden"] = {path = "Artifacts", width = 8, height = 12, hscale = 1.2, autoScale = true, x = 0, y = 0,
		coords = {{137/512, 166/512, 408/512, 466/512}, {167/512, 195/512, 408/512, 466/512}}},
	["Ornament Gray"] = {path = "challenges-besttime-bg", width = 8, height = 12, hscale = 1.2, autoScale = true, x = 0, y = 0, alpha = 0.7,
		coords = {{89/512, 123/512, 0, 1}, {123/512, 89/512, 0, 1}}},
	["Epic"] = {path = "WowUI_Horizontal_Frame", width = 6, height = 12, hscale = 1.2, autoScale = true, x = 3, y = 0, blend = "ADD",
		coords = {{30/256, 40/256, 15/64, 49/64}, {40/256, 30/256, 15/64, 49/64}}},
	["Arrow"] = {path = "arrow_single_right_64", width = 20, height = 20, wscale = 1.5, hscale = 2, autoScale = true, x = 28, y = 0, blend = "ADD",
		coords = {{0, 1, 0, 1}, {1, 0, 0, 1}}},
	["Arrow Thin"] = {path = "arrow_thin_right_64", width = 20, height = 20, wscale = 1.5, hscale = 2, autoScale = true, x = 28, y = 0, blend = "ADD",
		coords = {{0, 1, 0, 1}, {1, 0, 0, 1}}},
	["Double Arrows"] = {path = "arrow_double_right_64", width = 20, height = 20, wscale = 1.5, hscale = 2, autoScale = true, x = 28, y = 0, blend = "ADD",
		coords = {{0, 1, 0, 1}, {1, 0, 0, 1}}}
}

function ThreatPlatesWidgets.CreatePlaterTarget(bar)
	local frame = CreateFrame("Frame", nil, bar)
	frame:SetAllPoints(bar)
	frame:SetFrameLevel(bar:GetFrameLevel() + 3)
	frame.bar = bar
	frame.parts = {}
	for i = 1, 4 do
		frame.parts[i] = frame:CreateTexture(nil, "OVERLAY")
	end
	frame.glowUp = frame:CreateTexture(nil, "BACKGROUND")
	frame.glowUp:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
	frame.glowUp:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 0)
	frame.glowDown = frame:CreateTexture(nil, "BACKGROUND")
	frame.glowDown:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
	frame.glowDown:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	-- Leuchten als Farbverlauf statt NotPlaters Grafik (die wird im 3.3.5-Client als
	-- dunkler Block gezeichnet): blau am Balken, nach außen transparent auslaufend
	for _, glow in ipairs({frame.glowUp, frame.glowDown}) do
		glow:SetTexture(WHITE)
		glow:SetHeight(10)
		glow:SetBlendMode("ADD")
	end
	-- VERTICAL: erste Farbe = unten, zweite = oben
	frame.glowUp:SetGradientAlpha("VERTICAL", 0, 0.52, 1, 0.6, 0, 0.52, 1, 0)
	frame.glowDown:SetGradientAlpha("VERTICAL", 0, 0.52, 1, 0, 0, 0.52, 1, 0.6)
	frame:Hide()
	return frame
end

-- Wie NotPlater: Größe aus der Balkenhöhe, Ecken bzw. Seiten außen an den Balken
local CornerPoints = {"TOPLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "TOPRIGHT"}
local CornerSigns = {{-1, 1}, {-1, -1}, {1, -1}, {1, 1}}
function ThreatPlatesWidgets.ConfigurePlaterTarget(frame, name, glow)
	local barHeight = frame.bar:GetHeight()
	if frame.indicator == name and frame.glow == glow and frame.barHeight == barHeight then
		return
	end
	frame.indicator, frame.glow, frame.barHeight = name, glow, barHeight

	local preset = ThreatPlatesWidgets.TargetIndicators[name]
	local parts = frame.parts
	for i = 1, 4 do
		parts[i]:Hide()
	end
	if preset and barHeight > 4 then
		local scale = barHeight / (preset.autoScale and preset.height or 10)
		local w = preset.width * scale * (preset.wscale or 1)
		local h = preset.height * scale * (preset.hscale or 1)
		local x, y = (preset.x or 0) * scale, (preset.y or 0) * scale
		local count = #preset.coords
		for i = 1, count do
			local t = parts[i]
			t:SetTexture(NP_PATH .. preset.path)
			t:SetTexCoord(unpack(preset.coords[i]))
			t:SetBlendMode(preset.blend or "BLEND")
			t:SetDesaturated(preset.desaturated and true or false)
			t:SetAlpha(preset.alpha or 1)
			t:SetWidth(w)
			t:SetHeight(h)
			t:ClearAllPoints()
			if count == 4 then
				local point, sign = CornerPoints[i], CornerSigns[i]
				t:SetPoint(point, frame.bar, point, sign[1] * x, sign[2] * y)
			elseif i == 1 then
				t:SetPoint("LEFT", frame.bar, "LEFT", -x, y)
			else
				t:SetPoint("RIGHT", frame.bar, "RIGHT", x, y)
			end
			t:Show()
		end
	end
	if glow then
		frame.glowUp:Show()
		frame.glowDown:Show()
	else
		frame.glowUp:Hide()
		frame.glowDown:Hide()
	end
end

-----------------------
-- Classic Look Widget
-----------------------
-- Originale Blizzard-Grafiken: Goldrahmen mit Stufen-Feld, Elite-Drache, Mouseover-Aufhellung,
-- Leuchten (fürs Ziel) und Zauberleisten-Rahmen. Ausschnitt und Lage hat der TidyPlates-Kern
-- an der Original-Plakette gemessen (TidyPlates.BlizzardArt); hier werden sie auf die
-- eigenen Balken umgerechnet (Anteile von Balkenbreite/-höhe ab der linken unteren Ecke).
function ThreatPlatesWidgets.ClassicArt()
	local art = TidyPlates.BlizzardArt
	return art and art.health and art
end

local function ClassicTexture(parent, layer, art, blend)
	local t = parent:CreateTexture(nil, layer)
	if art and art.texture then
		t:SetTexture(art.texture)
		t:SetTexCoord(unpack(art.coords))
		t.valid = true
	end
	if blend then
		t:SetBlendMode(blend)
	end
	t:Hide()
	return t
end

-- Nicht messbare Teile (rect = nil) bleiben verborgen bzw. an der Stil-Position
local function PlaceRect(t, bar, rect, width, height)
	t.hasRect = rect and true
	if not rect then
		return
	end
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", rect.left * width, rect.top * height)
	t:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", rect.right * width, rect.bottom * height)
end

local function ShowIf(t, condition)
	if condition and t.valid and t.hasRect then
		t:Show()
	else
		t:Hide()
	end
end

-- Zauberleisten-Rahmen; nicht unterbrechbar = Blizzards Schild-Rahmen
local function SetClassicShielded(self, shielded)
	shielded = shielded and self.shieldBorder.valid
	ShowIf(self.border, self.placed and not shielded)
	ShowIf(self.shieldBorder, self.placed and shielded)
end

-- Dünne Leiste (castBorder aus): 1-px-Rahmen, dunkler Hintergrund, Restzeit unter der Leiste
-- rechts (gegenüber dem Zaubernamen). Wird bei jedem Zauberbeginn gesetzt.
local function PlaceThinCast(self)
	local bar = self.bar
	self.placed = nil
	self.border:Hide()
	self.shieldBorder:Hide()
	self.thin:SetBorderSize(ThreatPlatesWidgets.PixelSize(bar))
	self.thin:Show()
	bar:SetBackgroundColor(0.08, 0.08, 0.08, 0.9)
	self.text:ClearAllPoints()
	self.text:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
end

local function PlaceClassicCast(self)
	local plate = self.plate
	if not TidyPlatesThreat.db.profile.classicLook.castBorder then
		return PlaceThinCast(self)
	end
	self.thin:Hide()
	local art = TidyPlates.BlizzardArt
	if art and not art.cast and TidyPlates.MeasureBlizzardCast then
		TidyPlates.MeasureBlizzardCast(plate)
	end
	local geo = art and art.cast
	if not geo then
		self.placed = nil
		self:SetShielded(false)
		return
	end
	local bar = plate.bars.castbar
	local w, h = bar:GetWidth(), bar:GetHeight()
	if self.w ~= w or self.h ~= h then
		self.w, self.h = w, h
		PlaceRect(self.border, bar, geo.castborder, w, h)
		PlaceRect(self.shieldBorder, bar, geo.castnostop, w, h)
	end
	-- Zaubersymbol an Blizzards Platz (der Kern setzt es bei Stilwechseln zurück)
	if geo.spellicon then
		PlaceRect(plate.visual.spellicon, bar, geo.spellicon, w, h)
	end
	self.placed = true
	self:SetShielded(plate.unit and plate.unit.spellIsShielded)
end

-- Der Kern ruft beim Ausblenden einer Plakette Hide() für jedes Widget auf
local function HideClassicParts(look)
	look.border:Hide()
	look.elite:Hide()
	look.highlight:Hide()
	look.glow:Hide()
	look.targetBorder:Hide()
end

function ThreatPlatesWidgets.CreateClassicLook(plate)
	local art = TidyPlates.BlizzardArt
	local hb = plate.bars.healthbar
	-- Auf der Lebensleiste selbst (über der Füllung, unter Name/Stufe/Text der Plakette)
	local look = {
		border = ClassicTexture(hb, "OVERLAY", art.healthborder),
		elite = ClassicTexture(hb, "OVERLAY", art.eliteicon),
		highlight = ClassicTexture(hb, "OVERLAY", art.highlight, "ADD"),
		glow = ClassicTexture(hb, "BACKGROUND", art.threatglow, "ADD"),
		targetBorder = ClassicTexture(hb, "OVERLAY", art.healthborder, "ADD"),
		Hide = HideClassicParts
	}
	-- Zauberleiste: eigene Ebene über der Leiste, Restzeit/Farbe wie bei Plater
	local cb = plate.bars.castbar
	local cast = CreateFrame("Frame", nil, cb)
	cast:SetAllPoints(cb)
	cast:SetFrameLevel(cb:GetFrameLevel() + 1)
	cast.bar = cb
	cast.keepName = true -- Name steht über dem Balken, nicht an der Zauberleiste
	cast.border = ClassicTexture(cast, "ARTWORK", art.castborder)
	cast.shieldBorder = ClassicTexture(cast, "ARTWORK", art.castnostop)
	cast.SetShielded = SetClassicShielded
	cast.Place = PlaceClassicCast
	cast.thin = ThreatPlatesWidgets.CreatePlaterBorder(cb)
	cast.thin:Hide()
	ThreatPlatesWidgets.AddCastTimer(cast, TidyPlatesThreat.db.profile.settings.spelltext.size or 10, plate)
	look.cast = cast
	-- Stapel-Abstände kennen erst jetzt die Rahmengröße
	if not ThreatPlatesWidgets.classicStackingApplied then
		ThreatPlatesWidgets.classicStackingApplied = true
		TidyPlatesThreat:ApplyStacking()
	end
	return look
end

function ThreatPlatesWidgets.HideClassicLook(look)
	HideClassicParts(look)
	look.cast:SetScript("OnUpdate", nil)
	look.cast:SetScript("OnShow", nil)
	look.cast:SetScript("OnHide", nil)
	look.cast:Hide()
	look.cast.thin:Hide()
end

local function HasBar(barstyle)
	local tex = barstyle and barstyle.texture
	return tex and not tex:find("Empty$")
end

function ThreatPlatesWidgets.UpdateClassicLook(plate, unit, look, cfg)
	local art = TidyPlates.BlizzardArt
	local geo = art.health
	local style = plate.style
	if not HasBar(style.healthbar) then -- Nur-Name, Totem-Symbol
		HideClassicParts(look)
		return
	end
	local bar = plate.bars.healthbar
	local w, h = bar:GetWidth(), bar:GetHeight()
	if look.w ~= w or look.h ~= h then
		look.w, look.h = w, h
		PlaceRect(look.border, bar, geo.healthborder, w, h)
		PlaceRect(look.targetBorder, bar, geo.healthborder, w, h)
		PlaceRect(look.elite, bar, geo.eliteicon, w, h)
		PlaceRect(look.highlight, bar, geo.highlight, w, h)
		PlaceRect(look.glow, bar, geo.threatglow, w, h)
	end
	ShowIf(look.border, true)
	-- Ziel: Goldrahmen (samt Stufen-Feld) in der Zielfarbe einfärben und eine eingefärbte
	-- Kopie additiv darüberlegen. Nur additiv bleibt das Gold sichtbar und alles wirkt gelb;
	-- das Einfärben nimmt zuerst das Rot heraus. (Entsättigen + SetVertexColor färbt in diesem
	-- Client nicht, der Rahmen wird nur grau.)
	if cfg.targetBorder and unit.isTarget then
		local c = cfg.targetColor
		look.border:SetVertexColor(c.r, c.g, c.b)
		look.targetBorder:SetVertexColor(c.r, c.g, c.b, 0.8)
		ShowIf(look.targetBorder, true)
	else
		look.border:SetVertexColor(1, 1, 1)
		look.targetBorder:Hide()
	end
	ShowIf(look.elite, unit.isElite)
	ShowIf(look.highlight, unit.isMouseover and not unit.isTarget)
	if cfg.targetGlow and unit.isTarget then
		local c = cfg.glowColor
		look.glow:SetVertexColor(c.r, c.g, c.b, c.a)
		ShowIf(look.glow, true)
	else
		look.glow:Hide()
	end

	-- Stufe ins Feld des Rahmens, Totenkopf (Boss) an dieselbe Stelle. Der Kern setzt Lage
	-- und Schrift bei Stilwechseln zurück, daher bei jeder Aktualisierung.
	PlaceRect(plate.visual.skullicon, bar, geo.skullicon, w, h)
	local rect = geo.level
	if rect then
		local fx, fy = w / geo.width, h / geo.height
		local point = art.levelPoint or "CENTER"
		local x
		if point:find("LEFT") then
			point, x = "LEFT", rect.left
		elseif point:find("RIGHT") then
			point, x = "RIGHT", rect.right
		else
			point, x = "CENTER", (rect.left + rect.right) / 2
		end
		local level = plate.visual.level
		level:ClearAllPoints()
		level:SetPoint(point, bar, "BOTTOMLEFT", x * w, (rect.top + rect.bottom) / 2 * h)
		level:SetJustifyH(point)
		local font, size, flags = unpack(art.levelFont)
		if font and size then
			-- Kontur, damit die (oft gelbe) Stufe auch auf dem aufgehellten Feld des Ziels lesbar bleibt
			level:SetFont(font, size * math.min(fx, fy) * (cfg.levelSize or 1), "OUTLINE")
		end
	end

	if plate.bars.castbar:IsShown() then
		look.cast:Place()
	end
end

-----------------------
-- Quest Icon Widget
-----------------------
-- 3.3.5 kennt keine Quest-Zuordnung für Plaketten. Annäherung: Mob-Namen aus offenen
-- Tötungszielen im Questlog ("Verteidiger der Grimmhauer getötet: 3/8"). Sammelziele
-- (Gegenstand droppt vom Mob) nennen den Mob nicht und werden daher nicht erkannt.
local QuestMobs = {}
local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"

-- Muster aus dem lokalisierten Text ("%s getötet: %d/%d" bzw. "%s slain: %d/%d")
-- Platzhalter können nummeriert sein ("%1$s getötet: %2$d/%3$d"): erst durch Marken
-- ersetzen, dann alle Sonderzeichen maskieren, dann die Marken einsetzen. Ein unbrauchbares
-- Muster wird verworfen (dann gilt nur der Fallback).
local KilledPattern
do
	local template = QUEST_MONSTERS_KILLED or "%s slain: %d/%d"
	local marked = template:gsub("%%%d*%$?s", "\001"):gsub("%%%d*%$?d", "\002")
	local escaped = marked:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	local pattern = "^" .. escaped:gsub("\001", "(.+)"):gsub("\002", "%%d+") .. "$"
	if pcall(string.match, "", pattern) then
		KilledPattern = pattern
	end
end

local function ObjectiveMob(text)
	local name = KilledPattern and text:match(KilledPattern)
	if not name then
		-- Fallback: alles vor ": n/m", letztes Wort ("getötet") abschneiden
		local prefix = text:match("^(.-):%s*%d+%s*/%s*%d+$")
		name = prefix and prefix:match("^(.+)%s+%S+$")
	end
	return name
end

local function ScanQuestLog()
	local found = {}
	for i = 1, GetNumQuestLogEntries() do
		local _, _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
		if not isHeader and isComplete ~= 1 then
			for j = 1, GetNumQuestLeaderBoards(i) do
				local text, objType, finished = GetQuestLogLeaderBoard(j, i)
				if text and objType == "monster" and not finished then
					local name = ObjectiveMob(text)
					if name then
						found[name] = true
					end
				end
			end
		end
	end
	-- Nur bei Änderung die Plaketten aktualisieren
	local changed = false
	for name in pairs(found) do
		if not QuestMobs[name] then
			changed = true
		end
	end
	for name in pairs(QuestMobs) do
		if not found[name] then
			changed = true
		end
	end
	QuestMobs = found
	if changed then
		TidyPlates:RequestWidgetUpdate()
	end
end

-- QUEST_LOG_UPDATE kommt oft in Serien: höchstens zweimal pro Sekunde auswerten
local questScanner = CreateFrame("Frame")
local scanAt
questScanner:Hide()
questScanner:SetScript("OnUpdate", function(self)
	if GetTime() >= scanAt then
		self:Hide()
		ScanQuestLog()
	end
end)
questScanner:SetScript("OnEvent", function(self)
	if not self:IsShown() then
		scanAt = GetTime() + 0.5
		self:Show()
	end
end)

function ThreatPlatesWidgets.EnableQuestScanner(enabled)
	if enabled and not questScanner.active then
		questScanner.active = true
		questScanner:RegisterEvent("QUEST_LOG_UPDATE")
		questScanner:RegisterEvent("PLAYER_ENTERING_WORLD")
		ScanQuestLog()
	elseif not enabled and questScanner.active then
		questScanner.active = nil
		questScanner:UnregisterAllEvents()
		QuestMobs = {}
	end
end

function ThreatPlatesWidgets.CreateQuestIcon(plate)
	local icon = plate:CreateTexture(nil, "OVERLAY")
	icon:SetTexture(QUEST_ICON)
	icon:Hide()
	return icon
end

-- Links vor dem (zentrierten) Namen
function ThreatPlatesWidgets.UpdateQuestIcon(plate, unit, icon, size)
	local name = plate.visual.name
	if unit.type == "NPC" and unit.reaction ~= "FRIENDLY" and QuestMobs[unit.name] and name:IsShown() then
		icon:SetWidth(size)
		icon:SetHeight(size)
		icon:ClearAllPoints()
		icon:SetPoint("RIGHT", name, "CENTER", -(name:GetStringWidth() or 0) / 2 - 1, 0)
		icon:Show()
	else
		icon:Hide()
	end
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
			w.PlaterTarget = ThreatPlatesWidgets.CreatePlaterTarget(plate.bars.healthbar)
			ThreatPlatesWidgets.AddCastTimer(w.PlaterCastBorder, db.settings.spelltext.size or 10, plate)
			-- Dunkler Hintergrund, damit der Name darunter beim Zaubern nicht durchscheint
			plate.bars.castbar:SetBackgroundColor(0.08, 0.08, 0.08, 0.9)
		end
	elseif w.PlaterHealthBorder then
		w.PlaterHealthBorder:Hide()
		w.PlaterCastBorder:Hide()
		w.PlaterTarget:Hide()
		w.PlaterHealthBorder, w.PlaterCastBorder, w.PlaterTarget = nil, nil, nil
		plate.bars.castbar:SetBackgroundColor(0, 0, 0, 0) -- dunklen Hintergrund wieder entfernen
	end

	-- Classic-Optik (Blizzard-Grafiken); ohne Vermessung der Original-Plakette noch nicht möglich
	if db.classicLook.ON and ThreatPlatesWidgets.ClassicArt() then
		if not w.ClassicLook then
			w.ClassicLook = ThreatPlatesWidgets.CreateClassicLook(plate)
		end
	elseif w.ClassicLook then
		ThreatPlatesWidgets.HideClassicLook(w.ClassicLook)
		w.ClassicLook = nil
	end

	-- Quest-Symbol
	ThreatPlatesWidgets.EnableQuestScanner(db.questIcon.ON)
	if db.questIcon.ON then
		if not w.QuestIcon then
			w.QuestIcon = ThreatPlatesWidgets.CreateQuestIcon(plate)
		end
	elseif w.QuestIcon then
		w.QuestIcon:Hide()
		w.QuestIcon = nil
	end

	-- Auren im Plater-Stil (auch zur Classic-Optik)
	if (db.platerBorder.ON or db.classicLook.ON) and w.WidgetDebuff then
		ThreatPlatesWidgets.StylePlaterAuras(w.WidgetDebuff)
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
		-- Ziel-Markierung (NotPlater-Grafiken + Leuchten)
		local pt = w.PlaterTarget
		local pd = db.platerTarget
		if unit.isTarget and (pd.indicator ~= "NONE" or pd.glow) then
			ThreatPlatesWidgets.ConfigurePlaterTarget(pt, pd.indicator, pd.glow)
			pt:Show()
		else
			pt:Hide()
		end
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
		w.PlaterTarget:Hide()
	end
end

-- Classic-Optik: Ziel-Leuchten/Mouseover hängen am Kontext, Stufe/Rahmen am Stil
local function UpdateClassic(plate, unit)
	if not db.classicLook.ON then
		return
	end
	local w = plate.widgets
	if not w.ClassicLook then
		if not ThreatPlatesWidgets.ClassicArt() then
			return
		end
		OnInitialize(plate)
	end
	ThreatPlatesWidgets.UpdateClassicLook(plate, unit, w.ClassicLook, db.classicLook)
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
	UpdateClassic(plate, unit)
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
	UpdateClassic(plate, unit)
	-- Quest-Symbol (Name kann sich geändert haben)
	if db.questIcon.ON then
		if not w.QuestIcon then
			OnInitialize(plate)
		end
		ThreatPlatesWidgets.UpdateQuestIcon(plate, unit, w.QuestIcon, db.questIcon.size)
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