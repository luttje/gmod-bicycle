-- Admin-only actions are CAMI privileges, so admin mods (ULX, SAM, Helix and others) can grant them to any group.
-- Without an admin mod they fall back to admins only.
bicycle.PRIVILEGES = {
  physgunRidden = {
    Name = "Bicycle - Physgun Ridden Bikes",
    MinAccess = "admin",
    Description = "Pick up bikes someone is riding with the physgun",
  },
  resetTuning = {
    Name = "Bicycle - Reset Tuning",
    MinAccess = "admin",
    Description = "Reset the server's bike tuning with bicycle_reset_tuning",
  },
  editor = {
    Name = "Bicycle - Model Editor",
    MinAccess = "admin",
    Description = "Change bike model settings with bicycle_editor",
  },
}

-- Admin mods may load CAMI after this addon, so privileges are registered once every addon has loaded.
hook.Add("Initialize", "bicycle.registerPrivileges", function()
  if (not CAMI) then
    return
  end

  for _, privilege in pairs(bicycle.PRIVILEGES) do
    CAMI.RegisterPrivilege(privilege)
  end
end)

--- @param player Player
--- @param privilege table One of `bicycle.PRIVILEGES`
--- @return boolean
function bicycle.hasPermission(player, privilege)
  if (CAMI) then
    local hasAccess = nil

    CAMI.PlayerHasAccess(player, privilege.Name, function(result)
      hasAccess = result
    end)

    if (hasAccess ~= nil) then
      return hasAccess
    end
  end

  return player:IsAdmin()
end
