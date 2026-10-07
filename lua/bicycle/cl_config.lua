-- Each setting becomes an archived "bicycle_<name>" client convar.
bicycle.clientSettingSections = {
  {
    name = "Camera",
    settings = {
      {
        name = "cam_third_person",
        label = "Third person",
        type = "bool",
        default = 0,
        description = "Ride in third person instead of first person",
      },
      {
        name = "cam_roll",
        label = "Camera roll",
        default = 0.35,
        min = 0,
        max = 1,
        decimals = 2,
        description = "How much of the bike's lean the camera follows (0-1)",
      },
      {
        name = "cam_level",
        label = "Keep camera level",
        type = "bool",
        default = 1,
        description = "Keep the horizon level: the camera only turns with the bike, never pitches or rolls with it",
      },
      {
        name = "cam_smooth",
        label = "Camera smoothing",
        default = 0.15,
        min = 0,
        max = 1,
        decimals = 2,
        description = "Seconds the camera lags behind the bike turning and leaning, 0 is off. Mouse look stays instant",
      },
      {
        name = "cam_dist",
        label = "Camera distance",
        default = 120,
        min = 20,
        max = 400,
        description = "Third-person camera distance",
      },
      {
        name = "cam_height",
        label = "Camera height",
        default = 30,
        min = 0,
        max = 100,
        description = "Third-person camera pivot height",
      },
      {
        name = "cam_fov_boost",
        label = "Sprint FOV boost",
        default = 8,
        min = 0,
        max = 30,
        description = "Extra FOV at sprint speed",
      },
      {
        name = "cam_mount_blend",
        label = "Mount camera blend",
        default = 0.8,
        min = 0,
        max = 3,
        decimals = 2,
        description = "Seconds the camera takes to move from your on-foot view to the riding view, 0 is off",
      },
      {
        name = "cam_body",
        label = "Show your body in first person",
        type = "bool",
        default = 1,
        description = "Draw your own playermodel in first person, without its head, so you see your hands and feet",
      },
    },
  },
  {
    name = "Rider",
    settings = {
      {
        name = "rider_ik",
        label = "Hands and feet follow the bike",
        type = "bool",
        default = 1,
        description = "Put the rider's hands on the grips and feet on the pedals",
      },
      -- The line from the ankle to the ball of the foot points down even with the sole flat, so this is more than it
      -- seems.
      {
        name = "rider_foot_pitch",
        label = "Foot pitch",
        default = 60,
        min = 0,
        max = 90,
        description = "How far the feet point down on the pedals (deg)",
      },
      {
        name = "rider_ankling",
        label = "Ankling",
        default = 10,
        min = 0,
        max = 60,
        description = "How much the heel drops at the front of the pedal stroke and lifts at the back (deg)",
      },
      {
        name = "rider_knee_out",
        label = "Knees outward",
        default = 0.2,
        min = 0,
        max = 1,
        decimals = 2,
        description = "How far the knees point outward (0 = straight ahead)",
      },
      {
        name = "rider_elbow_out",
        label = "Elbows outward",
        default = 0.7,
        min = 0,
        max = 2,
        decimals = 2,
        description = "How far the elbows point outward rather than down",
      },
    },
  },
  {
    name = "HUD",
    settings = {
      {
        name = "hud_speed_unit",
        label = "Speedometer",
        type = "string",
        default = "km/h",
        choices = { "km/h", "mph", "units", "off" },
        description = "Unit the speedometer shows while riding, or off to hide it",
      },
    },
  },
  {
    name = "Sound",
    settings = {
      {
        name = "sound_volume",
        label = "Riding sounds volume",
        default = 1,
        min = 0,
        max = 1,
        decimals = 2,
        description = "Volume of every bike's chain, freewheel ticking and tyre skid (0-1)",
      },
      {
        name = "sound_wind",
        label = "Wind volume",
        default = 1,
        min = 0,
        max = 1,
        decimals = 2,
        description = "Volume of the wind you hear while riding fast (0-1), 0 is off",
      },
    },
  },
  {
    name = "Debug",
    settings = {
      {
        name = "debug",
        label = "Debug overlay and HUD (needs developer 1)",
        type = "bool",
        default = 1,
        description = "Draw wheel/lean debug overlay and HUD (needs developer 1)",
      },
    },
  },
}

bicycle.clientConVars = bicycle.clientConVars or {}

for _, section in ipairs(bicycle.clientSettingSections) do
  for _, definition in ipairs(section.settings) do
    bicycle.clientConVars[definition.name] = CreateClientConVar(
      "bicycle_" .. definition.name,
      tostring(definition.default),
      true,
      false,
      definition.description
    )
  end
end

concommand.Add("bicycle_reset_client", function()
  for _, conVar in pairs(bicycle.clientConVars) do
    conVar:Revert()
  end

  print("[bicycle] Client settings reset to defaults.")
end)

--- @param name string A name from `bicycle.clientSettingSections`
--- @return number
function bicycle.getClientSetting(name)
  return bicycle.clientConVars[name]:GetFloat()
end

--- @param name string A name from `bicycle.clientSettingSections`
--- @return boolean
function bicycle.getClientSettingBool(name)
  return bicycle.clientConVars[name]:GetBool()
end

--- @param name string A name from `bicycle.clientSettingSections`
--- @return string
function bicycle.getClientSettingString(name)
  return bicycle.clientConVars[name]:GetString()
end

local developerConVar = GetConVar("developer")

--- The debug overlay and HUD panel only show with both `developer` and `bicycle_debug` on.
function bicycle.isDebugEnabled()
  return developerConVar:GetBool() and bicycle.getClientSettingBool("debug")
end

bicycle.debugColors = {
  marker = Color(255, 255, 255, 40),
  targetLean = Color(255, 160, 40),
  actualLean = Color(80, 200, 255),
  grounded = Color(80, 255, 120),
  airborne = Color(255, 90, 90),
  wheelTrace = Color(255, 230, 0),
  velocity = Color(255, 255, 255),
  attachment = Color(255, 80, 255),
  steeringAxis = Color(255, 255, 120),
  editorSeat = Color(80, 200, 255),
  editorGrip = Color(255, 160, 40),
  editorFoot = Color(80, 255, 120),
  editorPassenger = Color(255, 120, 200),
}
