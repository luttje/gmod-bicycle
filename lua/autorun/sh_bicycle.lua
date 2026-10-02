AddCSLuaFile()

if (SERVER) then
  resource.AddWorkshop("3810718443")
end

bicycle = bicycle or {}

bicycle.ENTITY_CLASS = "sent_bicycle"

--- Includes a file from lua/bicycle/, sending it to clients and/or running it depending on its cl_, sh_ or sv_ prefix.
--- @param fileName string
--- @param directory string? Optional subdirectory of lua/bicycle/ to include from
function bicycle.includePrefixed(fileName, directory)
  local prefix = fileName:sub(1, 3)

  directory = directory or ""
  directory = directory:EndsWith("/") and directory or directory .. "/"

  local path = "bicycle/" .. directory .. fileName

  if (prefix ~= "cl_" and prefix ~= "sh_" and prefix ~= "sv_") then
    ErrorNoHaltWithStack("Error on includePrefixed: File not prefixed with cl_, sh_ or sv_! File was: " .. path)
    return
  end

  if (SERVER and prefix ~= "sv_") then
    AddCSLuaFile(path)
  end

  if (prefix == "sh_" or (SERVER and prefix == "sv_") or (CLIENT and prefix == "cl_")) then
    return include(path)
  end
end

bicycle.includePrefixed("sh_config.lua")
bicycle.includePrefixed("sh_permissions.lua")
bicycle.includePrefixed("sh_models.lua")
bicycle.includePrefixed("sh_tricks.lua")
bicycle.includePrefixed("sh_hooks.lua")
bicycle.includePrefixed("sh_editor.lua")

bicycle.includePrefixed("sv_hooks.lua")
bicycle.includePrefixed("sv_commands.lua")
bicycle.includePrefixed("sv_editor.lua")

bicycle.includePrefixed("cl_config.lua")
bicycle.includePrefixed("cl_options.lua")
bicycle.includePrefixed("cl_ik.lua")
bicycle.includePrefixed("cl_hooks.lua")
bicycle.includePrefixed("cl_editor.lua")

--- How many degrees `direction` points above the horizon, negative when below it.
--- @param direction Vector Normalized
--- @return number
function bicycle.getElevation(direction)
  return math.deg(math.asin(math.Clamp(direction.z, -1, 1)))
end

--- Whether `vehicle` is the seat of a bicycle.
--- @param vehicle Entity?
--- @return boolean
function bicycle.isSeat(vehicle)
  return IsValid(vehicle) and vehicle:GetNW2Bool("bicycle_Seat", false)
end

--- Resolves a bicycle seat to the bicycle it is mounted on.
--- @param vehicle Entity?
--- @return Entity?
function bicycle.getFromSeat(vehicle)
  if (not bicycle.isSeat(vehicle)) then
    return nil
  end

  local bike = vehicle:GetParent()

  if (IsValid(bike) and bike.IsBicycle) then
    return bike
  end

  return nil
end
