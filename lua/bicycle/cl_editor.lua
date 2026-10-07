local FRAME_WIDTH = 440
local FRAME_HEIGHT = 760
local FRAME_MARGIN = 20
local SNIPPET_HEIGHT = 230
local COPIED_LABEL_DURATION = 1.5
-- Dragging a slider changes it every frame, this is how often those changes are sent to the server at most.
local SEND_INTERVAL = 0.05

local SNIPPET_FONT = "DebugFixed"
local SNIPPET_BACKGROUND = Color(20, 20, 20, 235)
local SNIPPET_TEXT_COLOR = Color(220, 220, 220)

local VECTOR_AXES = { "x", "y", "z" }

-- Keys not listed come after these, sorted.
local SNIPPET_KEY_ORDER = {
  "name",
  "category",
  "model",
  "icon",
  "randomColor",
  "mass",
  "gearRatio",
  "wheelHullScale",
  "seatOffset",
  "seatPitch",
  "sprintLeanPitch",
  "wheelieLeanPitch",
  "wheelieSeatShift",
  "leanForwardPitch",
  "leanForwardSeatShift",
  "pedalCenterOffset",
  "footBallHeight",
  "gripOffset",
  "bodygroups",
  "passengerAttachment",
  "passengerSeatOffset",
}
-- Fallbacks for what the server measures from the model on spawn.
local MEASURED_KEYS = { "wheelRadius", "rearHub", "frontHub", "seatPosition" }

-- Each model's settings from when the editor first opened it, for the Reset button.
local originalValuesByModel = {}

local editorFrame

--- @return number|Vector # The value a bike of the model currently uses, including sent_bicycle's defaults
local function getCurrentValue(bike, setting)
  local value = bike[bicycle.modelDefinitionFields[setting.key]]

  return isvector(value) and Vector(value) or value
end

local function formatNumber(number)
  local text = string.format("%.2f", number):gsub("%.?0+$", "")

  return text == "-0" and "0" or text
end

local function formatValue(value)
  if (isvector(value)) then
    return string.format("Vector(%s, %s, %s)", formatNumber(value.x), formatNumber(value.y), formatNumber(value.z))
  elseif (isnumber(value)) then
    return formatNumber(value)
  elseif (isstring(value)) then
    return string.format("%q", value)
  elseif (istable(value)) then
    local keys = table.GetKeys(value)
    table.sort(keys)

    local entries = {}

    for index, key in ipairs(keys) do
      entries[index] = string.format("%s = %s", key, formatValue(value[key]))
    end

    return string.format("{ %s }", table.concat(entries, ", "))
  end

  return tostring(value)
end

local function getOrderedKeys(values)
  local keys, isListed = {}, {}

  for _, key in ipairs(SNIPPET_KEY_ORDER) do
    isListed[key] = true

    if (values[key] ~= nil) then
      keys[#keys + 1] = key
    end
  end

  for _, key in ipairs(MEASURED_KEYS) do
    isListed[key] = true
  end

  local otherKeys = {}

  for key in pairs(values) do
    if (not isListed[key]) then
      otherKeys[#otherKeys + 1] = key
    end
  end

  table.sort(otherKeys)
  table.Add(keys, otherKeys)

  return keys
end

--- @return string # The model's `bicycle.registerModel` call with its current settings
local function buildRegistration(bike, id, includeMeasured)
  local values = bicycle.models[id]
  local lines = { string.format("bicycle.registerModel(%q, {", id) }

  for _, key in ipairs(getOrderedKeys(values)) do
    lines[#lines + 1] = string.format("  %s = %s,", key, formatValue(values[key]))
  end

  if (includeMeasured and IsValid(bike)) then
    local measured = {
      wheelRadius = bike.WheelRadius,
      rearHub = bike.Wheels[1].position,
      frontHub = bike.Wheels[2].position,
      seatPosition = bike:GetAttachmentLocalPosition(bike.SeatAttachment),
    }

    lines[#lines + 1] = string.format("  -- Measured on %s.", values.model)

    for _, key in ipairs(MEASURED_KEYS) do
      if (measured[key] ~= nil) then
        lines[#lines + 1] = string.format("  %s = %s,", key, formatValue(measured[key]))
      end
    end
  end

  lines[#lines + 1] = "})"

  return table.concat(lines, "\n")
end

local function sendSetting(id, setting, value)
  net.Start("bicycle.editModelSetting")
  net.WriteString(id)
  net.WriteString(setting.key)
  bicycle.editor.writeValue(setting, value)
  net.SendToServer()
end

net.Receive("bicycle.editModelSetting", function()
  local id, key = net.ReadString(), net.ReadString()
  local setting = bicycle.editor.settingsByKey[key]

  if (setting) then
    bicycle.setModelSetting(id, key, bicycle.editor.readValue(setting))
  end
end)

--- Adds the slider(s) for one setting to `form`.
--- @param onChanged function Called with the setting's new value
--- @return function # Sets the slider(s) to a value, which calls `onChanged` too
local function addSettingSliders(form, setting, value, onChanged)
  if (not setting.axes) then
    local slider = form:NumSlider(setting.label, nil, setting.min, setting.max, setting.decimals)
    slider:SetValue(value)
    slider:SetTooltip(setting.help)
    slider.OnValueChanged = function(_, newValue)
      onChanged(newValue)
    end

    form:ControlHelp(setting.help)

    return function(newValue)
      slider:SetValue(newValue)
    end
  end

  local sliders = {}

  local function getVector()
    return Vector(sliders[1]:GetValue(), sliders[2]:GetValue(), sliders[3]:GetValue())
  end

  for index, axisName in ipairs(setting.axes) do
    local slider = form:NumSlider(
      string.format("%s (%s)", setting.label, axisName),
      nil,
      setting.min,
      setting.max,
      setting.decimals
    )
    slider:SetValue(value[VECTOR_AXES[index]])
    slider:SetTooltip(setting.help)
    slider.OnValueChanged = function()
      onChanged(getVector())
    end

    sliders[index] = slider
  end

  form:ControlHelp(setting.help)

  return function(newValue)
    for index, slider in ipairs(sliders) do
      slider:SetValue(newValue[VECTOR_AXES[index]])
    end
  end
end

local function addSnippetView(parent)
  local view = vgui.Create("RichText", parent)
  view:Dock(FILL)
  view:DockMargin(0, 4, 0, 4)

  function view:PerformLayout()
    self:SetFontInternal(SNIPPET_FONT)
  end

  function view:Paint(width, height)
    draw.RoundedBox(4, 0, 0, width, height, SNIPPET_BACKGROUND)
  end

  return view
end

local function openEditor(bike)
  local id = bike.BicycleModelId
  local definition = id and bicycle.models[id]

  if (not definition) then
    print("[bicycle] This bicycle wasn't registered with bicycle.registerModel, so it has no settings to edit.")
    return
  end

  if (IsValid(editorFrame)) then
    editorFrame:Remove()
  end

  local originalValues = originalValuesByModel[id]

  if (not originalValues) then
    originalValues = {}

    for _, setting in ipairs(bicycle.editor.SETTINGS) do
      originalValues[setting.key] = getCurrentValue(bike, setting)
    end

    originalValuesByModel[id] = originalValues
  end

  local frame = vgui.Create("DFrame")
  frame:SetSize(FRAME_WIDTH, math.min(FRAME_HEIGHT, ScrH() - FRAME_MARGIN * 2))
  frame:SetPos(ScrW() - frame:GetWide() - FRAME_MARGIN, FRAME_MARGIN)
  frame:SetTitle(string.format("Bike editor: %s (%s)", definition.name or id, id))
  frame:SetSizable(true)
  frame:SetMinWidth(FRAME_WIDTH)
  frame:MakePopup()
  -- Keys still reach the game, so you can ride with the editor open.
  frame:SetKeyboardInputEnabled(false)
  frame.bike = bike
  frame.modelId = id

  editorFrame = frame

  local registrationPanel = vgui.Create("DPanel", frame)
  registrationPanel:Dock(BOTTOM)
  registrationPanel:SetTall(SNIPPET_HEIGHT)
  registrationPanel:DockMargin(0, 8, 0, 0)
  registrationPanel:SetPaintBackground(false)

  local includeMeasuredCheckbox = vgui.Create("DCheckBoxLabel", registrationPanel)
  includeMeasuredCheckbox:Dock(TOP)
  includeMeasuredCheckbox:SetText("Include measured fallbacks (wheel radius, hubs, seat position)")
  includeMeasuredCheckbox:SetValue(definition.wheelRadius ~= nil)

  local buttonRow = vgui.Create("DPanel", registrationPanel)
  buttonRow:Dock(BOTTOM)
  buttonRow:SetTall(26)
  buttonRow:SetPaintBackground(false)

  local snippetView = addSnippetView(registrationPanel)

  function frame:RefreshRegistration()
    self.registration = buildRegistration(self.bike, self.modelId, includeMeasuredCheckbox:GetChecked())

    snippetView:SetText("")
    snippetView:InsertColorChange(SNIPPET_TEXT_COLOR.r, SNIPPET_TEXT_COLOR.g, SNIPPET_TEXT_COLOR.b, 255)
    snippetView:AppendText(self.registration)
  end

  function includeMeasuredCheckbox:OnChange()
    frame:RefreshRegistration()
  end

  local resetButton = vgui.Create("DButton", buttonRow)
  resetButton:Dock(RIGHT)
  resetButton:SetWide(120)
  resetButton:DockMargin(4, 0, 0, 0)
  resetButton:SetText("Reset")
  resetButton:SetTooltip("Back to the values from when the editor first opened this model")

  local copyButton = vgui.Create("DButton", buttonRow)
  copyButton:Dock(FILL)
  copyButton:SetText("Copy registration")

  function copyButton:DoClick()
    SetClipboardText(frame.registration)
    print(frame.registration)

    self:SetText("Copied! (also printed to the console)")
    timer.Create("bicycle.editorCopied", COPIED_LABEL_DURATION, 1, function()
      if (IsValid(self)) then
        self:SetText("Copy registration")
      end
    end)
  end

  local scroll = vgui.Create("DScrollPanel", frame)
  scroll:Dock(FILL)
  scroll:GetCanvas():DockPadding(0, 0, 0, 16)

  -- The same background as the spawnmenu's option panels.
  function scroll:Paint(width, height)
    derma.SkinHook("Paint", "CategoryList", self, width, height)
  end

  local intro = scroll:Add("DLabel")
  intro:Dock(TOP)
  intro:DockMargin(4, 4, 4, 8)
  intro:SetDark(true)
  intro:SetWrap(true)
  intro:SetAutoStretchVertical(true)
  intro:SetText(
    "Changes apply live to every bike of this model until the map changes. Paste the registration below into your "
    .. "addon to keep them. Markers show the seat (blue, with the rider's back), hands (orange), feet (green) and "
    .. "passenger seat (pink)."
  )

  local pendingValues = {}
  local nextSendAt = 0
  local setters = {}
  local forms = {}

  for _, setting in ipairs(bicycle.editor.SETTINGS) do
    if (setting.isAvailable and not setting.isAvailable(bike)) then
      continue
    end

    local form = forms[setting.section]

    if (not form) then
      form = scroll:Add("DForm")
      form:Dock(TOP)
      form:DockMargin(0, 0, 0, 8)
      form:SetName(setting.section)
      forms[setting.section] = form
    end

    setters[setting.key] = addSettingSliders(form, setting, getCurrentValue(bike, setting), function(value)
      pendingValues[setting.key] = value
    end)
  end

  function resetButton:DoClick()
    for key, setValue in pairs(setters) do
      setValue(originalValues[key])
    end
  end

  local baseThink = frame.Think

  function frame:Think()
    baseThink(self)

    if (not next(pendingValues) or nextSendAt > RealTime()) then
      return
    end

    nextSendAt = RealTime() + SEND_INTERVAL

    for key, value in pairs(pendingValues) do
      sendSetting(self.modelId, bicycle.editor.settingsByKey[key], value)
    end

    pendingValues = {}
  end

  frame:RefreshRegistration()
end

concommand.Add("bicycle_editor", function()
  if (not bicycle.hasPermission(LocalPlayer(), bicycle.PRIVILEGES.editor)) then
    print("[bicycle] You don't have access to the bike editor.")
    return
  end

  local bike = bicycle.findLocalBicycle()

  if (not bike) then
    print("[bicycle] Ride or look at a bicycle first.")
    return
  end

  openEditor(bike)
end)

hook.Add("BicycleModelSettingChanged", "bicycle.editor", function(id)
  if (IsValid(editorFrame) and editorFrame.modelId == id) then
    editorFrame:RefreshRegistration()
  end
end)

hook.Add("OnTextEntryGetFocus", "bicycle.editor", function(panel)
  if (IsValid(editorFrame) and panel:HasParent(editorFrame)) then
    editorFrame:SetKeyboardInputEnabled(true)
  end
end)

hook.Add("OnTextEntryLoseFocus", "bicycle.editor", function(panel)
  if (IsValid(editorFrame) and panel:HasParent(editorFrame)) then
    editorFrame:SetKeyboardInputEnabled(false)
  end
end)

hook.Add("PostDrawTranslucentRenderables", "bicycle.editorOverlay", function(_, isDrawingSkybox)
  if (isDrawingSkybox or not IsValid(editorFrame) or not IsValid(editorFrame.bike)) then
    return
  end

  editorFrame.bike:DrawEditorOverlay()
end)
