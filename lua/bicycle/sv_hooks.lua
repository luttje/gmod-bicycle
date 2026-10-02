hook.Add("PlayerEnteredVehicle", "bicycle.riderEnter", function(player, vehicle)
  local bike = bicycle.getFromSeat(vehicle)

  if (bike) then
    bike:OnRiderEnter(player)
  end
end)

hook.Add("CanExitVehicle", "bicycle.riderCanLeave", function(vehicle, player)
  local bike = bicycle.getFromSeat(vehicle)

  if (bike and not bike:CanRiderLeave(player)) then
    return false
  end
end)

hook.Add("PlayerLeaveVehicle", "bicycle.riderLeave", function(player, vehicle)
  local bike = bicycle.getFromSeat(vehicle)

  if (bike) then
    bike:OnRiderLeave(player)
  end
end)

-- Caught for each of the rider's commands as it's run, as checking keys once a tick misses presses when a lagging
-- rider's commands arrive bunched up.
hook.Add("KeyPress", "bicycle.riderKeyPress", function(player, key)
  local bike = bicycle.getFromSeat(player:GetVehicle())

  if (bike and bike:GetRider() == player) then
    bike:OnRiderKeyPress(key)
  end
end)

-- Only admins may pick up a bike someone is riding, anyone else could use it to fling the rider around.
hook.Add("PhysgunPickup", "bicycle.physgunRidden", function(player, entity)
  if (entity.IsBicycle and IsValid(entity:GetRider())
        and not bicycle.hasPermission(player, bicycle.PRIVILEGES.physgunRidden)) then
    return false
  end
end)

-- The balance controller would fight the physgun, so it lets go while the bike is held.
hook.Add("OnPhysgunPickup", "bicycle.physgunPickup", function(_, entity)
  if (entity.IsBicycle) then
    entity.isPhysgunHeld = true
  end
end)

hook.Add("PhysgunDrop", "bicycle.physgunDrop", function(_, entity)
  if (entity.IsBicycle) then
    entity.isPhysgunHeld = false
  end
end)
