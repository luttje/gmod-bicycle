util.AddNetworkString("bicycle.editModelSetting")

-- An admin changed a model setting in the bike editor: apply it here and pass it on to every client.
net.Receive("bicycle.editModelSetting", function(_, player)
  local id, key = net.ReadString(), net.ReadString()
  local setting = bicycle.editor.settingsByKey[key]

  if (not setting or not bicycle.models[id] or not bicycle.hasPermission(player, bicycle.PRIVILEGES.editor)) then
    return
  end

  local value = bicycle.editor.clampValue(setting, bicycle.editor.readValue(setting))

  bicycle.setModelSetting(id, key, value)

  net.Start("bicycle.editModelSetting")
  net.WriteString(id)
  net.WriteString(key)
  bicycle.editor.writeValue(setting, value)
  net.Broadcast()
end)
