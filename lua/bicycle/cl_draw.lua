bicycle.draw = bicycle.draw or {}

-- How far slanted shapes lean over, horizontally across their height.
local SLANT = 12
-- Hazard stripes.
local STRIPE_HEIGHT = 8
local STRIPE_WIDTH = 14
local TEXT_SHADOW_OFFSET = 3

local KEY_HEIGHT = 26
local KEY_PADDING = 8
local KEY_CORNER_RADIUS = 4
local KEY_SHADOW_OFFSET = 3

local TAG_HEIGHT = 22

bicycle.draw.SLANT = SLANT
bicycle.draw.STRIPE_HEIGHT = STRIPE_HEIGHT
bicycle.draw.STRIPE_WIDTH = STRIPE_WIDTH
bicycle.draw.KEY_HEIGHT = KEY_HEIGHT
bicycle.draw.KEY_SHADOW_OFFSET = KEY_SHADOW_OFFSET
bicycle.draw.TAG_HEIGHT = TAG_HEIGHT

local COLORS = {
  background = Color(16, 16, 18),
  panel = Color(32, 32, 36),
  panelAlternate = Color(40, 40, 45),
  panelHover = Color(54, 54, 60),
  sidebar = Color(24, 24, 27),
  accent = Color(255, 92, 16),
  highlight = Color(255, 210, 0),
  paper = Color(238, 232, 214),
  ink = Color(18, 18, 18),
  shadow = Color(0, 0, 0, 140),
  text = Color(236, 236, 236),
  muted = Color(140, 140, 146),
  key = Color(250, 250, 250),
  tape = Color(255, 210, 0, 170),
  watermark = Color(255, 255, 255, 8),
}

local FONTS = {
  title = "bicycle.draw.Title",
  chapter = "bicycle.draw.Chapter",
  heading = "bicycle.draw.Heading",
  tab = "bicycle.draw.Tab",
  number = "bicycle.draw.Number",
  watermark = "bicycle.draw.Watermark",
  body = "bicycle.draw.Body",
  small = "bicycle.draw.Small",
  key = "bicycle.draw.Key",
}

bicycle.draw.COLORS = COLORS
bicycle.draw.FONTS = FONTS

local DISPLAY_FONT = "Roboto Bk"

surface.CreateFont(FONTS.title, { font = DISPLAY_FONT, size = 56, weight = 700, italic = true })
surface.CreateFont(FONTS.chapter, { font = DISPLAY_FONT, size = 42, weight = 700, italic = true })
surface.CreateFont(FONTS.heading, { font = DISPLAY_FONT, size = 26, weight = 700, italic = true })
surface.CreateFont(FONTS.tab, { font = DISPLAY_FONT, size = 22, weight = 700, italic = true })
surface.CreateFont(FONTS.number, { font = DISPLAY_FONT, size = 30, weight = 700, italic = true })
surface.CreateFont(FONTS.watermark, { font = DISPLAY_FONT, size = 240, weight = 700, italic = true })
surface.CreateFont(FONTS.body, { font = "Roboto", size = 19, weight = 500, extended = true })
surface.CreateFont(FONTS.small, { font = "Roboto", size = 14, weight = 800, extended = true })
surface.CreateFont(FONTS.key, { font = "Roboto", size = 16, weight = 800, extended = true })

-- Keys as `input.LookupBinding` names them, which are otherwise shown capitalized.
local KEY_NAMES = {
  MOUSE1 = "Left mouse",
  MOUSE2 = "Right mouse",
  MOUSE3 = "Middle mouse",
  MOUSE4 = "Mouse 4",
  MOUSE5 = "Mouse 5",
  MWHEELUP = "Wheel up",
  MWHEELDOWN = "Wheel down",
  CTRL = "Ctrl",
  RCTRL = "Right Ctrl",
  RSHIFT = "Right Shift",
  RALT = "Right Alt",
}

--- @param text string
--- @param font string
--- @return number
function bicycle.draw.getTextWidth(text, font)
  surface.SetFont(font)

  return (surface.GetTextSize(text))
end

--- @param font string
--- @return number
function bicycle.draw.getFontHeight(font)
  surface.SetFont(font)

  return select(2, surface.GetTextSize("Ag"))
end

--- Draws a parallelogram leaning right by `slant` across its height.
function bicycle.draw.slantedBox(x, y, width, height, slant, color)
  surface.SetDrawColor(color)
  draw.NoTexture()
  surface.DrawPoly({
    { x = x + slant,         y = y },
    { x = x + width,         y = y },
    { x = x + width - slant, y = y + height },
    { x = x,                 y = y + height },
  })
end

--- Draws hazard stripes, which overhang `x` and `x + width` unless clipped.
function bicycle.draw.stripes(x, y, width, height, color)
  for stripeX = x - height, x + width, STRIPE_WIDTH * 2 do
    bicycle.draw.slantedBox(stripeX, y, STRIPE_WIDTH + height, height, height, color)
  end
end

--- @return number width
--- @return number height
function bicycle.draw.shadowedText(text, font, x, y, color, shadowColor, alignX, alignY)
  draw.SimpleText(text, font, x + TEXT_SHADOW_OFFSET, y + TEXT_SHADOW_OFFSET, shadowColor, alignX, alignY)

  return draw.SimpleText(text, font, x, y, color, alignX, alignY)
end

--- @return number # How wide `bicycle.draw.tag` draws `text`
function bicycle.draw.getTagWidth(text)
  return bicycle.draw.getTextWidth(text:upper(), FONTS.small) + SLANT * 2 + KEY_PADDING * 2
end

--- Draws a slanted tag with uppercase text, right-aligned to `right`.
function bicycle.draw.tag(text, right, centerY, color, textColor)
  text = text:upper()

  local width = bicycle.draw.getTagWidth(text)
  local x = right - width

  bicycle.draw.slantedBox(x, centerY - TAG_HEIGHT * 0.5, width, TAG_HEIGHT, SLANT * 0.5, color)
  draw.SimpleText(text, FONTS.small, x + width * 0.5, centerY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

--- @param key string A key's name, or a bind such as "+forward"
--- @return string # The name of the key bound to `key` if it's a bind, otherwise `key` itself
function bicycle.draw.getKeyName(key)
  if (not key:StartsWith("+")) then
    return key
  end

  local boundKey = input.LookupBinding(key, true)

  if (not boundKey) then
    return key:sub(2) .. " (unbound)"
  end

  boundKey = boundKey:upper()

  return KEY_NAMES[boundKey] or (boundKey:sub(1, 1) .. boundKey:sub(2):lower())
end

--- @param text string Such as "Double-tap [+back]"
--- @return table[] # `{ text, isKey }` for each key and each piece of text between them
function bicycle.draw.parseKeys(text)
  local tokens = {}
  local position = 1

  while (position <= #text) do
    local keyStart, keyEnd, key = text:find("%[(.-)%]", position)

    if (not keyStart) then
      tokens[#tokens + 1] = { text = text:sub(position) }
      break
    end

    if (keyStart > position) then
      tokens[#tokens + 1] = { text = text:sub(position, keyStart - 1) }
    end

    tokens[#tokens + 1] = { text = bicycle.draw.getKeyName(key), isKey = true }
    position = keyEnd + 1
  end

  return tokens
end

--- @param token table
--- @return number
local function getTokenWidth(token)
  surface.SetFont(token.isKey and FONTS.key or FONTS.body)

  local textWidth = surface.GetTextSize(token.text)

  return token.isKey and textWidth + KEY_PADDING * 2 + KEY_SHADOW_OFFSET or textWidth
end

--- @param tokens table[] From `bicycle.draw.parseKeys`
--- @return number
function bicycle.draw.getKeysWidth(tokens)
  local width = 0

  for _, token in ipairs(tokens) do
    width = width + getTokenWidth(token)
  end

  return width
end

--- Draws keys as keycaps in a row, with the text between them in `textColor`.
--- @param tokens table[] From `bicycle.draw.parseKeys`
--- @param x number
--- @param y number The top of the keycaps
--- @param textColor Color
function bicycle.draw.keys(tokens, x, y, textColor)
  for _, token in ipairs(tokens) do
    local width = getTokenWidth(token)

    if (token.isKey) then
      local capWidth = width - KEY_SHADOW_OFFSET

      local shadowX, shadowY = x + KEY_SHADOW_OFFSET, y + KEY_SHADOW_OFFSET

      draw.RoundedBox(KEY_CORNER_RADIUS, shadowX, shadowY, capWidth, KEY_HEIGHT, COLORS.accent)
      draw.RoundedBox(KEY_CORNER_RADIUS, x, y, capWidth, KEY_HEIGHT, COLORS.key)
      draw.SimpleText(
        token.text, FONTS.key, x + capWidth * 0.5, y + KEY_HEIGHT * 0.5, COLORS.ink,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER
      )
    else
      draw.SimpleText(token.text, FONTS.body, x, y + KEY_HEIGHT * 0.5, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    x = x + width
  end
end
