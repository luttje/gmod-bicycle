-- How long each landing shows (s), popping in at its start and fading out at its end.
local LIFETIME = 2.5
local POP_IN_TIME = 0.25
local FADE_OUT_TIME = 0.4
-- How much bigger than its size a landing starts out as it pops in.
local POP_IN_SCALE = 0.6
-- How far right a landing slides as it fades out.
local FADE_OUT_SLIDE = 80
-- Older landings make room below newer ones at this rate (1/s), this far apart. Past the maximum, the oldest fade out.
local SLIDE_RATE = 12
local LANDING_SPACING = 24
local MAX_LANDINGS = 3
-- Where the newest landing is centered, as a fraction of the screen height.
local SCREEN_Y_FRACTION = 0.26
-- Combos wrap onto more lines past this fraction of the screen width.
local MAX_WIDTH_FRACTION = 0.6

-- Degrees landings are tilted by, counter-clockwise, like the guide's title.
local ANGLE = 4
local SLANT = 24
local PADDING_X = 28
local PADDING_Y = 6
local SHADOW_OFFSET = 6
-- The hazard stripes under each landing.
local STRIPE_HEIGHT = bicycle.draw.STRIPE_HEIGHT
local STRIPE_WIDTH = bicycle.draw.STRIPE_WIDTH

local TURN_PREFIXES = {
  [2] = "Double",
  [3] = "Triple",
  [4] = "Quadruple",
}

--- @type table[] `{ lines, tag, width, height, createdAt, y }`, newest first
local landings = {}

--- @param trick table
--- @param turns number
--- @return string # Such as "DOUBLE TAILWHIP"
local function getTrickText(trick, turns)
  local name = trick.name

  if (turns > 1) then
    name = (TURN_PREFIXES[turns] or (turns .. "x")) .. " " .. name
  end

  return name:upper()
end

--- Joins `texts` with " + ", starting a new line where one would grow wider than `maxWidth`.
--- @param texts string[]
--- @param font string
--- @param maxWidth number
--- @return string[] lines
--- @return number width The widest line's
local function wrapTexts(texts, font, maxWidth)
  surface.SetFont(font)

  local lines = {}
  local line

  for _, text in ipairs(texts) do
    local joined = line and (line .. " + " .. text) or text

    if (line and surface.GetTextSize(joined) > maxWidth) then
      lines[#lines + 1] = line .. " +"
      line = text
    else
      line = joined
    end
  end

  lines[#lines + 1] = line

  local width = 0

  for _, wrappedLine in ipairs(lines) do
    width = math.max(width, (surface.GetTextSize(wrappedLine)))
  end

  return lines, width
end

--- @param texts string[] Each trick landed at once
local function addLanding(texts)
  local font = bicycle.draw.FONTS.chapter
  local lines, textWidth = wrapTexts(texts, font, ScrW() * MAX_WIDTH_FRACTION)
  local bandHeight = #lines * bicycle.draw.getFontHeight(font) + PADDING_Y * 2
  local now = RealTime()

  table.insert(landings, 1, {
    lines = lines,
    tag = #texts > 1 and string.format("%d-trick combo", #texts) or "Landed",
    width = textWidth + PADDING_X * 2 + SLANT * 2,
    bandHeight = bandHeight,
    height = bicycle.draw.TAG_HEIGHT * 0.5 + bandHeight + STRIPE_HEIGHT + SHADOW_OFFSET,
    createdAt = now,
  })

  for index = MAX_LANDINGS + 1, #landings do
    landings[index].createdAt = math.min(landings[index].createdAt, now - (LIFETIME - FADE_OUT_TIME))
  end
end

net.Receive("bicycle.TricksLanded", function()
  local turnsById = {}

  for _ = 1, net.ReadUInt(8) do
    local trick = bicycle.trick.read()
    local turns = net.ReadUInt(8)

    if (trick) then
      turnsById[trick.id] = turns
    end
  end

  if (not bicycle.getClientSettingBool("hud_tricks")) then
    return
  end

  local texts = {}

  -- In the order they're listed in the guide.
  for _, trick in ipairs(bicycle.trick.getAll()) do
    if (turnsById[trick.id]) then
      texts[#texts + 1] = getTrickText(trick, turnsById[trick.id])
    end
  end

  if (#texts > 0) then
    addLanding(texts)
  end
end)

--- Draws a slanted band with the landing's tricks, a tag on its top edge and hazard stripes along its bottom.
--- @param landing table
--- @param centerX number
--- @param centerY number
local function drawLanding(landing, centerX, centerY)
  local colors, fonts = bicycle.draw.COLORS, bicycle.draw.FONTS
  local width, bandHeight = landing.width, landing.bandHeight
  local bodyHeight = bandHeight + STRIPE_HEIGHT
  local x, y = centerX - width * 0.5, centerY - bodyHeight * 0.5
  -- The band is the top of the body, leaning along with it.
  local bandSlant = SLANT * bandHeight / bodyHeight
  local bandX = x + SLANT - bandSlant

  bicycle.draw.slantedBox(x + SHADOW_OFFSET, y + SHADOW_OFFSET, width, bodyHeight, SLANT, colors.shadow)
  bicycle.draw.slantedBox(x, y, width, bodyHeight, SLANT, colors.ink)
  bicycle.draw.slantedBox(bandX, y, width - (SLANT - bandSlant), bandHeight, bandSlant, colors.accent)

  local stripesY = y + bandHeight

  for stripeX = x + SLANT, x + width - SLANT - STRIPE_WIDTH - STRIPE_HEIGHT, STRIPE_WIDTH * 2 do
    bicycle.draw.slantedBox(
      stripeX, stripesY, STRIPE_WIDTH + STRIPE_HEIGHT, STRIPE_HEIGHT, STRIPE_HEIGHT, colors.highlight
    )
  end

  local lineHeight = bicycle.draw.getFontHeight(fonts.chapter)

  for index, line in ipairs(landing.lines) do
    bicycle.draw.shadowedText(
      line, fonts.chapter, centerX, y + PADDING_Y + (index - 1) * lineHeight, colors.text, colors.ink,
      TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP
    )
  end

  bicycle.draw.tag(
    landing.tag, x + SLANT + PADDING_X * 0.5 + bicycle.draw.getTagWidth(landing.tag), y,
    colors.highlight, colors.ink
  )
end

hook.Add("HUDPaint", "bicycle.landedTricks", function()
  if (#landings == 0) then
    return
  end

  -- Gamemodes with their own HUD can hide the landed tricks like any other HUD element.
  if (not bicycle.getClientSettingBool("hud_tricks") or hook.Run("HUDShouldDraw", "BicycleTricks") == false) then
    landings = {}
    return
  end

  local now = RealTime()

  for index = #landings, 1, -1 do
    if (now - landings[index].createdAt > LIFETIME) then
      table.remove(landings, index)
    end
  end

  local centerX = ScrW() * 0.5
  local targetY = ScrH() * SCREEN_Y_FRACTION
  local smoothing = math.min(1, FrameTime() * SLIDE_RATE)

  for index, landing in ipairs(landings) do
    if (index > 1) then
      targetY = targetY + landings[index - 1].height * 0.5 + LANDING_SPACING + landing.height * 0.5
    end

    landing.y = landing.y and Lerp(smoothing, landing.y, targetY) or targetY
  end

  render.PushFilterMag(TEXFILTER.ANISOTROPIC)
  render.PushFilterMin(TEXFILTER.ANISOTROPIC)

  -- Oldest first, so newer landings are drawn over them.
  for index = #landings, 1, -1 do
    local landing = landings[index]
    local age = now - landing.createdAt
    local popFraction = math.Clamp(age / POP_IN_TIME, 0, 1)
    local fadeFraction = math.Clamp((age - (LIFETIME - FADE_OUT_TIME)) / FADE_OUT_TIME, 0, 1)
    -- Overshoots a little, so it lands with a punch.
    local scale = 1 + POP_IN_SCALE * (1 - math.ease.OutBack(popFraction))
    local landingX = centerX + FADE_OUT_SLIDE * math.ease.InCubic(fadeFraction)
    local pivot = Vector(landingX, landing.y, 0)
    local matrix = Matrix()

    -- Drawn where it shows on screen and turned around that, as 2D drawing is clipped to the screen before the matrix
    -- applies.
    matrix:Translate(pivot)
    matrix:Rotate(Angle(0, -ANGLE, 0))
    matrix:Scale(Vector(scale, scale, 1))
    matrix:Translate(-pivot)

    surface.SetAlphaMultiplier(math.min(1, popFraction * 2) * (1 - fadeFraction))
    cam.PushModelMatrix(matrix, true)
    drawLanding(landing, landingX, landing.y)
    cam.PopModelMatrix()
  end

  surface.SetAlphaMultiplier(1)
  render.PopFilterMin()
  render.PopFilterMag()
end)
