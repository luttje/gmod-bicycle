bicycle.editor = bicycle.editor or {}

-- `axes` marks a vector setting with a slider per axis. The slider range is also what the server accepts.
bicycle.editor.SETTINGS = {
  {
    key = "seatOffset",
    section = "Seat",
    label = "Seat offset",
    axes = { "forward", "left", "up" },
    min = -30,
    max = 30,
    decimals = 2,
    help = "Where the rider sits relative to the \"seat\" attachment.",
  },
  {
    key = "seatPitch",
    section = "Seat",
    label = "Seat pitch",
    min = -45,
    max = 90,
    decimals = 1,
    help = "How far the rider leans forward (deg).",
  },
  {
    key = "sprintLeanPitch",
    section = "Seat",
    label = "Sprint lean pitch",
    min = 0,
    max = 60,
    decimals = 1,
    help = "How much further forward the rider tucks while sprint-pedalling (deg).",
  },
  {
    key = "wheelieLeanPitch",
    section = "Seat",
    label = "Wheelie lean pitch",
    min = 0,
    max = 60,
    decimals = 1,
    help = "How far back the rider leans while wheelieing (deg).",
  },
  {
    key = "wheelieSeatShift",
    section = "Seat",
    label = "Wheelie seat shift",
    axes = { "forward", "left", "up" },
    min = -15,
    max = 15,
    decimals = 2,
    help = "How far the rider moves while wheelieing, relative to their normal seat.",
  },
  {
    key = "gripOffset",
    section = "Hands and feet",
    label = "Grip offset",
    axes = { "forward", "outward", "up" },
    min = -10,
    max = 10,
    decimals = 2,
    help = "Where the hands hold relative to the grip attachments, mirrored for each side.",
  },
  {
    key = "pedalCenterOffset",
    section = "Hands and feet",
    label = "Pedal center offset",
    min = -5,
    max = 10,
    decimals = 2,
    help = "How far out from the pedal attachments the feet are placed.",
  },
  {
    key = "footBallHeight",
    section = "Hands and feet",
    label = "Foot ball height",
    min = -5,
    max = 5,
    decimals = 2,
    help = "How far above the pedal's axle the ball of the foot sits.",
  },
  {
    key = "mass",
    section = "Physics",
    label = "Mass",
    min = 1,
    max = 200,
    decimals = 1,
    help = "Physics mass without a rider.",
  },
  {
    key = "gearRatio",
    section = "Physics",
    label = "Gear ratio",
    min = 0.5,
    max = 6,
    decimals = 2,
    help = "Wheel revolutions per crank revolution.",
  },
  {
    key = "wheelHullScale",
    section = "Physics",
    label = "Wheel hull scale",
    min = 0.1,
    max = 1,
    decimals = 2,
    help = "How far the collision hull's wheels are shrunk. Only bikes spawned after the change use it.",
  },
}

bicycle.editor.settingsByKey = {}

for _, setting in ipairs(bicycle.editor.SETTINGS) do
  bicycle.editor.settingsByKey[setting.key] = setting
end

local function clampNumber(setting, value)
  -- NaN fails every comparison, so math.Clamp would let it through.
  if (value ~= value) then
    return setting.min
  end

  return math.Clamp(value, setting.min, setting.max)
end

--- Keeps a value inside the setting's slider range.
--- @return number|Vector
function bicycle.editor.clampValue(setting, value)
  if (setting.axes) then
    return Vector(clampNumber(setting, value.x), clampNumber(setting, value.y), clampNumber(setting, value.z))
  end

  return clampNumber(setting, value)
end

-- Floats rather than net.WriteVector, which rounds to 1/32 of a unit and would show up in the copied registration.
function bicycle.editor.writeValue(setting, value)
  if (setting.axes) then
    net.WriteFloat(value.x)
    net.WriteFloat(value.y)
    net.WriteFloat(value.z)
  else
    net.WriteFloat(value)
  end
end

--- @return number|Vector
function bicycle.editor.readValue(setting)
  if (setting.axes) then
    return Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
  end

  return net.ReadFloat()
end
