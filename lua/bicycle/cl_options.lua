local function isChangedFromDefault(definition)
  local conVar = bicycle.tuningConVars[definition.name]

  if (isnumber(definition.default)) then
    return conVar:GetFloat() ~= definition.default
  end

  return conVar:GetString() ~= definition.default
end

-- Prints every tuning value, so a tuning session can be pasted back as-is. The tuning convars are replicated, so this
-- runs on the client and costs the server nothing.
concommand.Add("bicycle_dump_tuning", function()
  print("===== BIKE TUNING =====")

  for _, definition in ipairs(bicycle.tuningDefinitions) do
    local conVar = bicycle.tuningConVars[definition.name]
    local changedMarker = isChangedFromDefault(definition) and "   (changed)" or ""

    print(string.format("%s %s%s", conVar:GetName(), conVar:GetString(), changedMarker))
  end
end)

local function addSettingControl(form, definition)
  local conVarName = "bicycle_" .. definition.name
  local control

  if (definition.type == "bool") then
    control = form:CheckBox(definition.label, conVarName)
  elseif (definition.type == "string") then
    control = form:ComboBox(definition.label, conVarName)

    for _, choice in ipairs(definition.choices or {}) do
      control:AddChoice(choice, choice)
    end
  else
    control = form:NumSlider(definition.label, conVarName, definition.min, definition.max, definition.decimals or 0)
  end

  control:SetTooltip(string.format("%s\n%s (default %s)", definition.description, conVarName, definition.default))
end

local function addSections(form, sections)
  for _, section in ipairs(sections) do
    local sectionForm = vgui.Create("DForm")
    sectionForm:SetName(section.name)
    form:AddItem(sectionForm)

    for _, definition in ipairs(section.settings) do
      addSettingControl(sectionForm, definition)
    end
  end
end

local function buildClientPanel(form)
  form:Help("Your own camera, rider and debug settings. They are saved between sessions.")
  form:Button("Reset to defaults", "bicycle_reset_client")
  addSections(form, bicycle.clientSettingSections)

  form:Help("Ride or look at a bike first:")
  form:Button("Open the bike editor (admins)", "bicycle_editor")
  form:Button("Print the bike's bones to the console", "bicycle_print_bones")

  form:DockPadding(0, 0, 0, 16)
end

local function buildServerPanel(form)
  form:Help(
    "How every bike rides. Only the server host can change these (in singleplayer, that's you), and they reset to "
    .. "the defaults every session."
  )
  form:Button("Reset to defaults", "bicycle_reset_tuning")
  form:Button("Print all values to the console", "bicycle_dump_tuning")
  addSections(form, bicycle.tuningSections)

  form:DockPadding(0, 0, 0, 16)
end

hook.Add("PopulateToolMenu", "bicycle.options", function()
  spawnmenu.AddToolMenuOption("Options", "Bicycle", "bicycle_client", "Client", "", "", buildClientPanel)
  spawnmenu.AddToolMenuOption("Options", "Bicycle", "bicycle_server", "Server", "", "", buildServerPanel)
end)
