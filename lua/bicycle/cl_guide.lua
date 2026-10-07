bicycle.guide = bicycle.guide or {}

local TITLE = "BIKE GUIDE"
local SUBTITLE = "EVERYTHING YOU NEED TO SHRED"

local FRAME_WIDTH = 1040
local FRAME_HEIGHT = 720
local FRAME_MARGIN = 32
local FRAME_BORDER = 2
local HEADER_HEIGHT = 96
local FOOTER_HEIGHT = 60
local SIDEBAR_MIN_WIDTH = 220
local TAB_HEIGHT = 56
local TAB_SPACING = 6
local NAV_BUTTON_WIDTH = 170
local CLOSE_BUTTON_WIDTH = 72
local SCROLLBAR_WIDTH = 8
local CONTENT_PADDING = 24
local CHAPTER_HEADER_HEIGHT = 92
local BLOCK_SPACING = 14
local ROW_PADDING = 8

-- How far slanted shapes lean over, horizontally across their height.
local SLANT = 12
local TITLE_SLANT = 40
-- The hazard stripes under the header.
local STRIPE_HEIGHT = 8
local STRIPE_WIDTH = 14
-- Degrees the title is tilted by, counter-clockwise.
local TITLE_ANGLE = 4
local TEXT_SHADOW_OFFSET = 3

local KEY_HEIGHT = 26
local KEY_PADDING = 8
local KEY_CORNER_RADIUS = 4
local KEY_SHADOW_OFFSET = 3

local CARD_SHADOW_OFFSET = 6
local CARD_TAPE_WIDTH = 76
local CARD_TAPE_HEIGHT = 20
local CARD_TAPE_ANGLE = 6
local CARD_TAPE_OVERHANG = math.ceil((
  CARD_TAPE_WIDTH * math.abs(math.sin(math.rad(CARD_TAPE_ANGLE)))
  + CARD_TAPE_HEIGHT * math.abs(math.cos(math.rad(CARD_TAPE_ANGLE)))
) * 0.5)
local CARD_STRIPE_WIDTH = 6
local TAG_HEIGHT = 22

local DEFAULT_CHAPTER_ORDER = 100

local CLICK_SOUND = "garrysmod/ui_click.wav"
local HOVER_SOUND = "garrysmod/ui_hover.wav"

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
  title = "bicycle.guide.Title",
  chapter = "bicycle.guide.Chapter",
  heading = "bicycle.guide.Heading",
  tab = "bicycle.guide.Tab",
  number = "bicycle.guide.Number",
  watermark = "bicycle.guide.Watermark",
  body = "bicycle.guide.Body",
  small = "bicycle.guide.Small",
  key = "bicycle.guide.Key",
}

bicycle.guide.COLORS = COLORS
bicycle.guide.FONTS = FONTS

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

--- @type table<string, table>
local chaptersById = {}
--- @type table<string, function>
local blockTypes = {}

local guideFrame

--- Registers a chapter, replacing any chapter with the same id.
--- @param chapter table `id` and `content` are required. `content` is a list of blocks, or a function returning one
--- that is called each time the chapter is shown. `title` defaults to the id, and chapters are sorted by `order`.
--- @return table? # The chapter, nil when it's invalid
function bicycle.guide.registerChapter(chapter)
  local hasContent = istable(chapter.content) or isfunction(chapter.content)

  if (not isstring(chapter.id) or chapter.id == "" or not hasContent) then
    ErrorNoHaltWithStack("[bicycle] bicycle.guide.registerChapter needs a chapter with a string id and content.\n")
    return nil
  end

  chapter.title = chapter.title or chapter.id
  chapter.order = chapter.order or DEFAULT_CHAPTER_ORDER
  chaptersById[chapter.id] = chapter

  return chapter
end

--- @return table[] # Every registered chapter, sorted by order and then by title
function bicycle.guide.getChapters()
  local chapters = {}

  for _, chapter in pairs(chaptersById) do
    chapters[#chapters + 1] = chapter
  end

  table.sort(chapters, function(a, b)
    if (a.order ~= b.order) then
      return a.order < b.order
    end

    return a.title < b.title
  end)

  return chapters
end

--- Registers how blocks with `type = name` are built, replacing any block type with the same name.
--- @param name string
--- @param build fun(parent: Panel, block: table) Adds the block's panels to `parent`, docked to the top
function bicycle.guide.registerBlockType(name, build)
  blockTypes[name] = build
end

--- @param parent Panel
--- @param block table|string A plain string is a text block
function bicycle.guide.buildBlock(parent, block)
  if (isstring(block)) then
    block = { type = "text", text = block }
  end

  local build = blockTypes[block.type]

  if (not build) then
    ErrorNoHaltWithStack("[bicycle] Unknown guide block type: " .. tostring(block.type) .. "\n")
    return
  end

  build(parent, block)
end

--- @param key string A key's name, or a bind such as "+forward"
--- @return string # The name of the key bound to `key` if it's a bind, otherwise `key` itself
function bicycle.guide.getKeyName(key)
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
function bicycle.guide.parseKeys(text)
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

    tokens[#tokens + 1] = { text = bicycle.guide.getKeyName(key), isKey = true }
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

--- @param tokens table[] From `bicycle.guide.parseKeys`
--- @return number
function bicycle.guide.getKeysWidth(tokens)
  local width = 0

  for _, token in ipairs(tokens) do
    width = width + getTokenWidth(token)
  end

  return width
end

--- Draws keys as keycaps in a row, with the text between them in `textColor`.
--- @param tokens table[] From `bicycle.guide.parseKeys`
--- @param x number
--- @param y number The top of the keycaps
--- @param textColor Color
function bicycle.guide.drawKeys(tokens, x, y, textColor)
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

--- Draws a parallelogram leaning right by `slant` across its height.
local function drawSlantedBox(x, y, width, height, slant, color)
  surface.SetDrawColor(color)
  draw.NoTexture()
  surface.DrawPoly({
    { x = x + slant,         y = y },
    { x = x + width,         y = y },
    { x = x + width - slant, y = y + height },
    { x = x,                 y = y + height },
  })
end

local function drawStripes(x, y, width, height, color)
  for stripeX = x - height, x + width, STRIPE_WIDTH * 2 do
    drawSlantedBox(stripeX, y, STRIPE_WIDTH + height, height, height, color)
  end
end

local function drawShadowedText(text, font, x, y, color, shadowColor, alignX, alignY)
  draw.SimpleText(text, font, x + TEXT_SHADOW_OFFSET, y + TEXT_SHADOW_OFFSET, shadowColor, alignX, alignY)

  return draw.SimpleText(text, font, x, y, color, alignX, alignY)
end

--- Draws shadowed text centered on `x`, `y` in `panel`, tilted counter-clockwise by `angle`.
local function drawTiltedText(panel, text, font, x, y, color, shadowColor, angle)
  local screenX, screenY = panel:LocalToScreen(x, y)
  local pivot = Vector(screenX, screenY, 0)
  local matrix = Matrix()

  matrix:Translate(pivot)
  matrix:Rotate(Angle(0, -angle, 0))
  matrix:Translate(-pivot)

  render.PushFilterMag(TEXFILTER.ANISOTROPIC)
  render.PushFilterMin(TEXFILTER.ANISOTROPIC)
  cam.PushModelMatrix(matrix, true)
  drawShadowedText(text, font, x, y, color, shadowColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
  cam.PopModelMatrix()
  render.PopFilterMin()
  render.PopFilterMag()
end

--- @return number
local function getTextWidth(text, font)
  surface.SetFont(font)

  return (surface.GetTextSize(text))
end

--- @return number
local function getFontHeight(font)
  surface.SetFont(font)

  return select(2, surface.GetTextSize("Ag"))
end

--- Keeps `panel` as tall as its children docked to the top, such as wrapped labels that stretch to fit their text.
--- @param panel Panel
--- @param minimumHeight number?
local function fitToContents(panel, minimumHeight)
  function panel:PerformLayout()
    local _, paddingTop, _, paddingBottom = self:GetDockPadding()
    local height = paddingTop + paddingBottom

    for _, child in ipairs(self:GetChildren()) do
      if (child:GetDock() == TOP and child:IsVisible()) then
        local _, marginTop, _, marginBottom = child:GetDockMargin()

        height = height + marginTop + child:GetTall() + marginBottom
      end
    end

    self:SetTall(math.max(height, minimumHeight or 0))
  end
end

--- @return DLabel # Docked to the top, wrapping and as tall as its text
local function createLabel(parent, text, font, color)
  local label = vgui.Create("DLabel", parent)
  label:Dock(TOP)
  label:SetFont(font or FONTS.body)
  label:SetTextColor(color or COLORS.text)
  label:SetText(text)
  label:SetWrap(true)
  label:SetAutoStretchVertical(true)

  return label
end

--- @param tokens table[] From `bicycle.guide.parseKeys`
--- @return Panel # Draws the keys at its top left, as wide and tall as they are
local function createKeysPanel(parent, tokens, textColor)
  local panel = vgui.Create("Panel", parent)
  panel:SetSize(bicycle.guide.getKeysWidth(tokens), KEY_HEIGHT + KEY_SHADOW_OFFSET)
  panel:SetMouseInputEnabled(false)

  function panel:Paint()
    bicycle.guide.drawKeys(tokens, 0, 0, textColor)
  end

  return panel
end

--- @return number # How wide `drawTag` draws `text`
local function getTagWidth(text)
  return getTextWidth(text:upper(), FONTS.small) + SLANT * 2 + KEY_PADDING * 2
end

--- Draws a slanted tag with uppercase text, right-aligned to `right`.
local function drawTag(text, right, centerY, color, textColor)
  text = text:upper()

  local width = getTagWidth(text)
  local x = right - width

  drawSlantedBox(x, centerY - TAG_HEIGHT * 0.5, width, TAG_HEIGHT, SLANT * 0.5, color)
  draw.SimpleText(text, FONTS.small, x + width * 0.5, centerY, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function styleScrollBar(scroll)
  local bar = scroll:GetVBar()
  bar:SetWide(SCROLLBAR_WIDTH)
  bar:SetHideButtons(true)

  function bar:Paint(width, height)
    surface.SetDrawColor(COLORS.panel)
    surface.DrawRect(0, 0, width, height)
  end

  function bar.btnGrip:Paint(width, height)
    surface.SetDrawColor(self:IsHovered() and COLORS.highlight or COLORS.accent)
    surface.DrawRect(0, 0, width, height)
  end
end

-- `{ type = "text", text }`, a paragraph.
bicycle.guide.registerBlockType("text", function(parent, block)
  createLabel(parent, block.text):DockMargin(0, 0, 0, BLOCK_SPACING)
end)

-- `{ type = "heading", text }`, starting a part of a chapter.
bicycle.guide.registerBlockType("heading", function(parent, block)
  local text = block.text:upper()
  local panel = vgui.Create("Panel", parent)
  panel:Dock(TOP)
  panel:DockMargin(0, BLOCK_SPACING, 0, BLOCK_SPACING)
  panel:SetTall(getFontHeight(FONTS.heading) + SLANT)

  function panel:Paint(width, height)
    local textWidth = drawShadowedText(text, FONTS.heading, 0, 0, COLORS.highlight, COLORS.ink)

    drawSlantedBox(0, height - SLANT * 0.5, textWidth + SLANT * 3, SLANT * 0.5, SLANT * 0.25, COLORS.accent)
  end
end)

-- `{ type = "controls", rows = { { keys, action }, ... } }`, a table of keys and what they do.
bicycle.guide.registerBlockType("controls", function(parent, block)
  local container = vgui.Create("Panel", parent)
  container:Dock(TOP)
  container:DockMargin(0, 0, 0, BLOCK_SPACING)
  fitToContents(container)

  local rows = {}
  local keysWidth = 0

  for index, row in ipairs(block.rows) do
    local tokens = bicycle.guide.parseKeys(row[1])

    rows[index] = { tokens = tokens, action = row[2] }
    keysWidth = math.max(keysWidth, bicycle.guide.getKeysWidth(tokens))
  end

  local labelOffset = math.max(0, math.floor((KEY_HEIGHT - getFontHeight(FONTS.body)) * 0.5))

  for index, row in ipairs(rows) do
    local rowPanel = vgui.Create("Panel", container)
    rowPanel:Dock(TOP)
    rowPanel:DockPadding(CONTENT_PADDING * 0.5, ROW_PADDING, CONTENT_PADDING * 0.5, ROW_PADDING)
    fitToContents(rowPanel, KEY_HEIGHT + KEY_SHADOW_OFFSET + ROW_PADDING * 2)

    local rowColor = index % 2 == 1 and COLORS.panel or COLORS.panelAlternate

    function rowPanel:Paint(width, height)
      surface.SetDrawColor(rowColor)
      surface.DrawRect(0, 0, width, height)
    end

    local keysPanel = createKeysPanel(rowPanel, row.tokens, COLORS.text)
    keysPanel:Dock(LEFT)
    keysPanel:SetWide(keysWidth)
    keysPanel:DockMargin(0, 0, CONTENT_PADDING, 0)

    createLabel(rowPanel, row.action):DockMargin(0, labelOffset, 0, 0)
  end
end)

-- `{ type = "tip", text }`, a hint set apart from the text around it.
bicycle.guide.registerBlockType("tip", function(parent, block)
  local tagWidth = getTagWidth("Tip")
  local panel = vgui.Create("Panel", parent)
  panel:Dock(TOP)
  panel:DockMargin(0, 0, 0, BLOCK_SPACING)
  panel:DockPadding(tagWidth + CONTENT_PADDING, ROW_PADDING * 1.5, CONTENT_PADDING * 0.5, ROW_PADDING * 1.5)
  fitToContents(panel)

  function panel:Paint(width, height)
    surface.SetDrawColor(COLORS.panel)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(COLORS.highlight)
    surface.DrawRect(0, 0, CARD_STRIPE_WIDTH * 0.5, height)

    drawTag("Tip", tagWidth + CONTENT_PADDING * 0.5, ROW_PADDING * 1.5 + TAG_HEIGHT * 0.5, COLORS.highlight, COLORS.ink)
  end

  createLabel(panel, block.text)
end)

-- `{ type = "card", title, tag?, keys?, text? }`, a note taped into the binder, such as a trick.
bicycle.guide.registerBlockType("card", function(parent, block)
  local card = vgui.Create("Panel", parent)
  card:Dock(TOP)
  card:DockMargin(0, 0, 0, BLOCK_SPACING)
  card:DockPadding(
    CARD_STRIPE_WIDTH + CONTENT_PADDING * 0.75,
    CARD_TAPE_OVERHANG + CONTENT_PADDING * 0.75,
    CARD_SHADOW_OFFSET + CONTENT_PADDING * 0.75,
    CARD_SHADOW_OFFSET + CONTENT_PADDING * 0.75
  )
  fitToContents(card)

  function card:Paint(width, height)
    local paperHeight = height - CARD_TAPE_OVERHANG - CARD_SHADOW_OFFSET
    local paperWidth = width - CARD_SHADOW_OFFSET

    surface.SetDrawColor(COLORS.shadow)
    surface.DrawRect(CARD_SHADOW_OFFSET, CARD_TAPE_OVERHANG + CARD_SHADOW_OFFSET, paperWidth, paperHeight)
    surface.SetDrawColor(COLORS.paper)
    surface.DrawRect(0, CARD_TAPE_OVERHANG, paperWidth, paperHeight)
    surface.SetDrawColor(COLORS.accent)
    surface.DrawRect(0, CARD_TAPE_OVERHANG, CARD_STRIPE_WIDTH, paperHeight)

    surface.SetDrawColor(COLORS.tape)
    draw.NoTexture()
    surface.DrawTexturedRectRotated(
      paperWidth - CARD_TAPE_WIDTH, CARD_TAPE_OVERHANG,
      CARD_TAPE_WIDTH, CARD_TAPE_HEIGHT, CARD_TAPE_ANGLE
    )
  end

  local titleRow = vgui.Create("Panel", card)
  titleRow:Dock(TOP)
  titleRow:SetTall(getFontHeight(FONTS.heading))

  function titleRow:Paint(width, height)
    draw.SimpleText(block.title:upper(), FONTS.heading, 0, height * 0.5, COLORS.ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    if (block.tag) then
      drawTag(block.tag, width, height * 0.5, COLORS.ink, COLORS.highlight)
    end
  end

  if (block.keys) then
    local keysPanel = createKeysPanel(card, bicycle.guide.parseKeys(block.keys), COLORS.ink)
    keysPanel:Dock(TOP)
    keysPanel:DockMargin(0, ROW_PADDING, 0, 0)
  end

  if (block.text) then
    createLabel(card, block.text, FONTS.body, COLORS.ink):DockMargin(0, ROW_PADDING, 0, 0)
  end
end)

--- Paints a button as a slanted tag, filled in while hovered or `isActive`.
local function paintSlantedButton(button, width, height, text, isActive)
  local isEnabled = button:IsEnabled()
  local isLit = isEnabled and (isActive or button:IsHovered())
  local textColor = isLit and COLORS.ink or (isEnabled and COLORS.text or COLORS.muted)

  drawSlantedBox(0, 0, width, height, SLANT, isLit and COLORS.accent or COLORS.panel)
  draw.SimpleText(text, FONTS.tab, width * 0.5, height * 0.5, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function createSlantedButton(parent, text, onClick)
  local button = vgui.Create("DButton", parent)
  button:SetText("")

  function button:Paint(width, height)
    paintSlantedButton(self, width, height, text)
  end

  function button:OnCursorEntered()
    if (self:IsEnabled()) then
      surface.PlaySound(HOVER_SOUND)
    end
  end

  function button:DoClick()
    surface.PlaySound(CLICK_SOUND)
    onClick()
  end

  return button
end

local function createHeader(frame)
  local header = vgui.Create("Panel", frame)
  header:Dock(TOP)
  header:SetTall(HEADER_HEIGHT)

  function header:Paint(width, height)
    local bandHeight = height - STRIPE_HEIGHT
    local titleWidth = getTextWidth(TITLE, FONTS.title)
    local titleBlockWidth = titleWidth + CONTENT_PADDING * 2 + TITLE_SLANT * 2

    surface.SetDrawColor(COLORS.panel)
    surface.DrawRect(0, 0, width, bandHeight)
    drawSlantedBox(-TITLE_SLANT, 0, titleBlockWidth, bandHeight, TITLE_SLANT, COLORS.accent)
    drawTiltedText(
      self, TITLE, FONTS.title, CONTENT_PADDING + titleWidth * 0.5, bandHeight * 0.5, COLORS.text, COLORS.ink,
      TITLE_ANGLE
    )

    local subtitleX = titleBlockWidth - TITLE_SLANT + CONTENT_PADDING

    -- Left out on small screens, where it would run into the close button.
    if (subtitleX + getTextWidth(SUBTITLE, FONTS.tab) < width - CLOSE_BUTTON_WIDTH - CONTENT_PADDING * 2) then
      draw.SimpleText(
        SUBTITLE, FONTS.tab, subtitleX, bandHeight * 0.5, COLORS.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
      )
    end

    surface.SetDrawColor(COLORS.ink)
    surface.DrawRect(0, bandHeight, width, STRIPE_HEIGHT)
    drawStripes(0, bandHeight, width, STRIPE_HEIGHT, COLORS.highlight)
  end

  local closeButton = createSlantedButton(header, "X", function()
    frame:Close()
  end)
  closeButton:Dock(RIGHT)
  closeButton:SetWide(CLOSE_BUTTON_WIDTH)
  closeButton:DockMargin(0, CONTENT_PADDING, CONTENT_PADDING, CONTENT_PADDING + STRIPE_HEIGHT)
end

local function createFooter(frame, chapterCount)
  local footer = vgui.Create("Panel", frame)
  footer:Dock(BOTTOM)
  footer:SetTall(FOOTER_HEIGHT)
  footer:DockPadding(CONTENT_PADDING, ROW_PADDING * 1.5, CONTENT_PADDING, ROW_PADDING * 1.5)

  function footer:Paint(width, height)
    surface.SetDrawColor(COLORS.panel)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(COLORS.accent)
    surface.DrawRect(0, 0, width, FRAME_BORDER)

    local page = string.format("CHAPTER %02d / %02d", frame.chapterIndex or 0, chapterCount)

    draw.SimpleText(page, FONTS.tab, width * 0.5, height * 0.5, COLORS.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
  end

  local previousButton = createSlantedButton(footer, "< PREVIOUS", function()
    frame:ShowChapter(frame.chapterIndex - 1)
  end)
  previousButton:Dock(LEFT)
  previousButton:SetWide(NAV_BUTTON_WIDTH)

  local nextButton = createSlantedButton(footer, "NEXT >", function()
    frame:ShowChapter(frame.chapterIndex + 1)
  end)
  nextButton:Dock(RIGHT)
  nextButton:SetWide(NAV_BUTTON_WIDTH)

  return previousButton, nextButton
end

local function createSidebar(frame, chapters)
  local titleX = CONTENT_PADDING * 3
  local widestTitle = 0

  for _, chapter in ipairs(chapters) do
    widestTitle = math.max(widestTitle, getTextWidth(chapter.title:upper(), FONTS.tab))
  end

  local tabMarginRight = CONTENT_PADDING * 0.5
  local sidebar = vgui.Create("DScrollPanel", frame)
  sidebar:Dock(LEFT)
  -- Wide enough for the longest title, past the tab's slanted end and the scrollbar.
  sidebar:SetWide(math.max(
    SIDEBAR_MIN_WIDTH,
    titleX + widestTitle + SLANT + CONTENT_PADDING * 0.5 + tabMarginRight + SCROLLBAR_WIDTH
  ))
  sidebar:GetCanvas():DockPadding(0, CONTENT_PADDING, 0, CONTENT_PADDING)
  styleScrollBar(sidebar)

  function sidebar:Paint(width, height)
    surface.SetDrawColor(COLORS.sidebar)
    surface.DrawRect(0, 0, width, height)
  end

  for index, chapter in ipairs(chapters) do
    local tab = sidebar:Add("DButton")
    tab:Dock(TOP)
    tab:DockMargin(0, 0, tabMarginRight, TAB_SPACING)
    tab:SetTall(TAB_HEIGHT)
    tab:SetText("")
    tab:SetTooltip(chapter.title)

    function tab:Paint(width, height)
      local isSelected = frame.chapterIndex == index
      local textColor = isSelected and COLORS.ink or COLORS.text

      if (isSelected or self:IsHovered()) then
        drawSlantedBox(-SLANT, 0, width + SLANT, height, SLANT, isSelected and COLORS.accent or COLORS.panelHover)
      end

      draw.SimpleText(
        string.format("%02d", index), FONTS.number, CONTENT_PADDING, height * 0.5,
        isSelected and COLORS.text or COLORS.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
      )
      draw.SimpleText(
        chapter.title:upper(), FONTS.tab, titleX, height * 0.5, textColor,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER
      )
    end

    function tab:OnCursorEntered()
      surface.PlaySound(HOVER_SOUND)
    end

    function tab:DoClick()
      if (frame.chapterIndex ~= index) then
        surface.PlaySound(CLICK_SOUND)
        frame:ShowChapter(index)
      end
    end
  end
end

local function createChapterHeader(parent, index, chapter)
  local header = vgui.Create("Panel", parent)
  header:Dock(TOP)
  header:DockMargin(0, 0, 0, BLOCK_SPACING)
  header:SetTall(CHAPTER_HEADER_HEIGHT)

  local tag = string.format("Chapter %02d", index)
  local title = chapter.title:upper()

  function header:Paint(width, height)
    drawTag(tag, getTagWidth(tag), TAG_HEIGHT * 0.5, COLORS.highlight, COLORS.ink)
    drawShadowedText(title, FONTS.chapter, 0, TAG_HEIGHT + ROW_PADDING, COLORS.text, COLORS.accent)
    drawStripes(0, height - STRIPE_HEIGHT, width, STRIPE_HEIGHT, COLORS.panel)
  end
end

--- Opens the guide binder, replacing any already open.
--- @param chapterId string? The chapter to open at, the first one by default
function bicycle.guide.open(chapterId)
  if (IsValid(guideFrame)) then
    guideFrame:Remove()
  end

  local chapters = bicycle.guide.getChapters()

  local frame = vgui.Create("DFrame")
  frame:SetSize(
    math.min(FRAME_WIDTH, ScrW() - FRAME_MARGIN * 2),
    math.min(FRAME_HEIGHT, ScrH() - FRAME_MARGIN * 2)
  )
  frame:Center()
  frame:SetTitle("")
  frame:ShowCloseButton(false)
  frame:SetDraggable(false)
  frame:DockPadding(FRAME_BORDER, FRAME_BORDER, FRAME_BORDER, FRAME_BORDER)
  frame:MakePopup()

  guideFrame = frame

  function frame:Paint(width, height)
    surface.SetDrawColor(COLORS.background)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(COLORS.accent)
    surface.DrawOutlinedRect(0, 0, width, height, FRAME_BORDER)
  end

  createHeader(frame)
  local previousButton, nextButton = createFooter(frame, #chapters)
  createSidebar(frame, chapters)

  local content = vgui.Create("DScrollPanel", frame)
  content:Dock(FILL)
  content:GetCanvas():DockPadding(CONTENT_PADDING, CONTENT_PADDING, CONTENT_PADDING, CONTENT_PADDING)
  styleScrollBar(content)

  -- The chapter's number, sprayed faintly behind it.
  function content:Paint(width, height)
    draw.SimpleText(
      string.format("%02d", frame.chapterIndex or 0), FONTS.watermark, width - CONTENT_PADDING, height,
      COLORS.watermark, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM
    )
  end

  function frame:ShowChapter(index)
    local chapter = chapters[index]

    if (not chapter) then
      return
    end

    self.chapterIndex = index
    previousButton:SetEnabled(index > 1)
    nextButton:SetEnabled(index < #chapters)

    content:Clear()
    content:GetVBar():SetScroll(0)
    createChapterHeader(content, index, chapter)

    local blocks = isfunction(chapter.content) and chapter.content() or chapter.content

    for _, block in ipairs(blocks) do
      bicycle.guide.buildBlock(content, block)
    end
  end

  local startIndex = 1

  for index, chapter in ipairs(chapters) do
    if (chapter.id == chapterId) then
      startIndex = index
    end
  end

  frame:ShowChapter(startIndex)

  return frame
end

concommand.Add("bicycle_guide", function(_, _, arguments)
  bicycle.guide.open(arguments[1])
end, function(command)
  local completions = {}

  for _, chapter in ipairs(bicycle.guide.getChapters()) do
    completions[#completions + 1] = command .. " " .. chapter.id
  end

  return completions
end, "Opens the bike guide, optionally at a chapter by its id")
