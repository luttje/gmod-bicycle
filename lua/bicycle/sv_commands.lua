concommand.Add("bicycle_reset_tuning", function(player)
  if (IsValid(player) and not bicycle.hasPermission(player, bicycle.PRIVILEGES.resetTuning)) then
    return
  end

  for _, definition in ipairs(bicycle.tuningDefinitions) do
    RunConsoleCommand(bicycle.tuningConVars[definition.name]:GetName(), tostring(definition.default))
  end

  print("[bicycle] Tuning reset to defaults.")
end)
