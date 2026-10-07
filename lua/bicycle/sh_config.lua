-- Tuning is server authoritative and replicated, so every value can be changed live while skating. The server saves
-- it, so a server's tuning survives restarts.
local TUNING_FLAGS = { FCVAR_ARCHIVE, FCVAR_REPLICATED }

bicycle.DEFAULT_RIDER_SEQUENCE = "drive_airboat"

-- Each setting becomes a "bicycle_<name>" convar. `min`, `max` and `decimals` are for its slider, `type` is "bool" or
-- "string" for settings that aren't numbers.
bicycle.tuningSections = {
  {
    name = "Speed and pedalling",
    settings = {
      {
        name = "top_speed",
        label = "Top speed",
        default = 380,
        min = 0,
        max = 1500,
        description = "Top pedalling speed (u/s). 380 u/s ~ 26 km/h",
      },
      {
        name = "sprint_speed",
        label = "Sprint speed",
        default = 540,
        min = 0,
        max = 2000,
        description = "Top speed while sprinting (u/s). 540 u/s ~ 37 km/h",
      },
      {
        name = "pedal_accel",
        label = "Pedal acceleration",
        default = 220,
        min = 0,
        max = 1000,
        description = "Pedalling acceleration (u/s^2)",
      },
      {
        name = "sprint_accel",
        label = "Sprint acceleration",
        default = 1.35,
        min = 1,
        max = 3,
        decimals = 2,
        description = "Pedalling acceleration multiplier while sprinting",
      },
      {
        name = "brake_accel",
        label = "Brake deceleration",
        default = 750,
        min = 0,
        max = 2000,
        description = "Brake deceleration with both wheels down (u/s^2)",
      },
      {
        name = "reverse_speed",
        label = "Reverse speed",
        default = 50,
        min = 0,
        max = 200,
        description = "Walking-backwards speed when holding S at a standstill (u/s)",
      },
      {
        name = "rolling",
        label = "Rolling resistance",
        default = 10,
        min = 0,
        max = 100,
        description = "Rolling resistance while coasting (u/s^2)",
      },
      {
        name = "drag",
        label = "Air drag",
        default = 0.0002,
        min = 0,
        max = 0.002,
        decimals = 4,
        description = "Air drag while coasting (per u/s^2)",
      },
    },
  },
  {
    name = "Tyres and suspension",
    settings = {
      {
        name = "spring",
        label = "Tyre spring",
        default = 400,
        min = 0,
        max = 2000,
        description = "Tyre spring stiffness (mass-normalised)",
      },
      { name = "damper", label = "Tyre damping", default = 20, min = 0, max = 100, description = "Tyre damping" },
      {
        name = "grip",
        label = "Sideways grip",
        default = 30,
        min = 0,
        max = 100,
        description = "How fast sideways slip is removed (1/s)",
      },
      {
        name = "mu",
        label = "Tyre friction",
        default = 1.3,
        min = 0,
        max = 3,
        decimals = 2,
        description = "Tyre friction coefficient (caps cornering and braking)",
      },
    },
  },
  {
    name = "Lean and steering",
    settings = {
      { name = "lean_max",  label = "Max lean",  default = 45,  min = 0, max = 80,  description = "Max lean angle (deg)" },
      {
        name = "lean_p",
        label = "Lean gain",
        default = 6,
        min = 0,
        max = 20,
        decimals = 1,
        description = "Lean controller gain (deg/s per deg of error)",
      },
      { name = "lean_rate", label = "Lean rate", default = 160, min = 0, max = 500, description = "Max lean rate (deg/s)" },
      {
        name = "lean_response",
        label = "Lean response",
        default = 25,
        min = 0,
        max = 100,
        description = "How hard the lean controller corrects (1/s)",
      },
      {
        name = "lean_slack",
        label = "Lean slack",
        default = 300,
        min = 0,
        max = 1000,
        description = "Cornering allowed before the bike has leaned in (u/s^2)",
      },
      {
        name = "yaw_response",
        label = "Yaw response",
        default = 30,
        min = 0,
        max = 100,
        description = "How fast the heading follows the handlebar (1/s)",
      },
      {
        name = "air_control",
        label = "Air control",
        default = 0.3,
        min = 0,
        max = 1,
        decimals = 2,
        description = "Lean control strength in the air (0-1)",
      },
      {
        name = "air_pitch_control",
        label = "Air pitch control",
        default = 1,
        min = 0,
        max = 1,
        decimals = 2,
        description = "How strongly bikes keep their nose along their path in the air (0-1), 0 leaves it to physics",
      },
      {
        name = "advanced_air_control",
        label = "Advanced air control",
        type = "bool",
        default = 1,
        description = "Spin (A / D) and tip (W / S) the bike in the air, vert airs and spine transfers",
      },
      {
        name = "air_turn_speed",
        label = "Air turn speed",
        default = 180,
        min = 0,
        max = 1000,
        description = "How fast A / D spin the bike round in the air (deg/s), 0 turns it off",
      },
      {
        name = "air_pitch_speed",
        label = "Air pitch speed",
        default = 170,
        min = 0,
        max = 1000,
        description = "How fast W / S tip the nose down / up in the air (deg/s), 0 turns it off",
      },
      {
        name = "steer_max",
        label = "Max steer (slow)",
        default = 45,
        min = 0,
        max = 60,
        description = "Max handlebar angle at low speed (deg)",
      },
      {
        name = "steer_max_fast",
        label = "Max steer (fast)",
        default = 8,
        min = 0,
        max = 60,
        description = "Max handlebar angle at high speed (deg)",
      },
      {
        name = "steer_slow_speed",
        label = "Slow steer below",
        default = 80,
        min = 0,
        max = 1000,
        description = "Below this speed the full slow max steer is allowed (u/s)",
      },
      {
        name = "steer_fast_speed",
        label = "Fast steer above",
        default = 420,
        min = 0,
        max = 2000,
        description = "Above this speed steering is narrowed to the fast max steer (u/s)",
      },
      {
        name = "steer_rate",
        label = "Steer rate",
        default = 3.5,
        min = 0,
        max = 10,
        decimals = 1,
        description = "Steering input speed (full locks per second)",
      },
    },
  },
  {
    name = "Tricks and crashes",
    settings = {
      { name = "hop", label = "Bunny hop", default = 180, min = 0, max = 500, description = "Bunny hop upward velocity (u/s)" },
      {
        name = "hop_cooldown",
        label = "Hop cooldown",
        default = 0.45,
        min = 0,
        max = 2,
        decimals = 2,
        description = "Seconds between bunny hops",
      },
      {
        name = "wheelie_angle",
        label = "Wheelie angle",
        default = 25,
        min = 0,
        max = 60,
        description = "Wheelie target angle (deg)",
      },
      {
        name = "stoppie_angle",
        label = "Stoppie angle",
        default = 60,
        min = 0,
        max = 80,
        description = "Stoppie target angle, nose down (deg)",
      },
      {
        name = "tricks",
        label = "Allow tricks",
        type = "bool",
        default = 1,
        description = "Let riders tailwhip and barspin",
      },
      {
        name = "tailwhip_speed",
        label = "Tailwhip speed",
        default = 900,
        min = 0,
        max = 2000,
        description = "How fast the frame spins during a tailwhip (deg/s)",
      },
      {
        name = "barspin_speed",
        label = "Barspin speed",
        default = 1080,
        min = 0,
        max = 2000,
        description = "How fast the handlebar spins during a barspin (deg/s)",
      },
      {
        name = "flip_speed",
        label = "Flip speed",
        default = 600,
        min = 0,
        max = 2000,
        description = "How fast the bike turns over during a backflip or front flip (deg/s)",
      },
      {
        name = "trick_land_tolerance",
        label = "Trick landing tolerance",
        default = 45,
        min = 0,
        max = 180,
        description = "Landing a tailwhip or barspin further off straight than this throws you off (deg)",
      },
      {
        name = "crash_speed",
        label = "Crash speed",
        default = 420,
        min = 0,
        max = 1500,
        description = "Frontal impact speed that throws you off (u/s)",
      },
      {
        name = "crash_lean",
        label = "Crash lean",
        default = 75,
        min = 0,
        max = 90,
        description = "Lean angle that counts as a crash (deg)",
      },
      {
        name = "crash_pitch",
        label = "Crash pitch",
        default = 70,
        min = 0,
        max = 90,
        description = "Nose up or down angle against the ground that counts as a crash (deg)",
      },
    },
  },
  {
    name = "Water",
    settings = {
      {
        name = "water_level",
        label = "Throw off at water level",
        default = 3,
        min = 0,
        max = 3,
        description = "Water this deep throws the rider off: 1 touching, 2 half under, 3 fully under, 0 never",
      },
      {
        name = "water_drag",
        label = "Water drag",
        default = 1.5,
        min = 0,
        max = 10,
        decimals = 2,
        description = "How hard water slows the bike once the wheels are fully under (1/s)",
      },
    },
  },
  {
    name = "Sounds",
    settings = {
      {
        name = "sounds",
        label = "Enable sounds",
        type = "bool",
        default = 1,
        description = "Play the bike's sounds: bell, chain, freewheel, skids, wind, hops, impacts and crashes",
      },
      {
        name = "bell",
        label = "Allow the bell",
        type = "bool",
        default = 1,
        description = "Let riders ring the bell with the reload key",
      },
      {
        name = "bell_cooldown",
        label = "Bell cooldown",
        default = 0.15,
        min = 0,
        max = 10,
        decimals = 2,
        description = "Seconds before a rider can ring the bell again",
      },
    },
  },
  {
    name = "Mass, parking and the rider",
    settings = {
      {
        name = "mass_ridden",
        label = "Ridden mass",
        default = 85,
        min = 1,
        max = 300,
        description = "Physics mass while ridden (bike + rider)",
      },
      {
        name = "park_upright",
        label = "Parked bikes stay upright",
        type = "bool",
        default = 1,
        description = "Riderless bikes stay upright instead of falling over",
      },
      {
        name = "park_upright_lean",
        label = "Parked upright up to",
        default = 50,
        min = 0,
        max = 90,
        description = "Riderless bikes leaning further than this fall over anyway (deg)",
      },
      {
        name = "dismount_anywhere",
        label = "Always let riders get off",
        type = "bool",
        default = 0,
        description = "Riders with no room to stand beside the bike get off above it instead of staying on, "
            .. "which could put them past a player clip the bike rode through",
      },
      {
        name = "ragmod_crash",
        label = "Ragdoll crashing riders (RagMod)",
        type = "bool",
        default = 1,
        description = "When RagMod is installed and enabled, riders flying over the handlebars become a RagMod ragdoll",
      },
      {
        name = "rider_seq",
        label = "Rider sequence",
        type = "string",
        default = bicycle.DEFAULT_RIDER_SEQUENCE,
        choices = { "drive_airboat", "drive_jeep", "sit_rollercoaster" },
        description = "Player sequence while riding",
      },
    },
  },
}

--- @type table[] Every setting of `bicycle.tuningSections`, in order
bicycle.tuningDefinitions = {}
bicycle.tuningConVars = bicycle.tuningConVars or {}

for _, section in ipairs(bicycle.tuningSections) do
  for _, definition in ipairs(section.settings) do
    bicycle.tuningDefinitions[#bicycle.tuningDefinitions + 1] = definition
    bicycle.tuningConVars[definition.name] = CreateConVar(
      "bicycle_" .. definition.name,
      tostring(definition.default),
      TUNING_FLAGS,
      definition.description
    )
  end
end

--- @param name string A name from `bicycle.tuningSections`
--- @return number
function bicycle.getTuning(name)
  return bicycle.tuningConVars[name]:GetFloat()
end

--- @param name string A name from `bicycle.tuningSections`
--- @return boolean
function bicycle.getTuningBool(name)
  return bicycle.tuningConVars[name]:GetBool()
end

--- @param name string A name from `bicycle.tuningSections`
--- @return string
function bicycle.getTuningString(name)
  return bicycle.tuningConVars[name]:GetString()
end
