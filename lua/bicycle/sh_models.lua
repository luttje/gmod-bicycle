-- Bike models are registered from the "BicycleRegisterModels" hook, which runs once the gamemode has loaded. Each
-- becomes its own spawnable entity class derived from sent_bicycle, so every registered bike gets a spawn menu entry.
--
-- From another addon, in a shared lua/autorun/ file:
--
--   hook.Add("BicycleRegisterModels", "myaddon.bike", function()
--     bicycle.registerModel("mybike", {
--       name = "My Bike",
--       model = "models/myname/bicycle.mdl",
--       seatOffset = Vector(-8, 0, 1),
--     })
--   end)

local DEFAULT_CATEGORY = "#spawnmenu.category.fun_games"

-- Definition keys that are copied as-is onto the entity class. Left out keys fall back to sent_bicycle's defaults.
local DEFINITION_FIELDS = {
  model = "Model",
  -- Spawn menu icon material, e.g. "entities/mybike.png". Without it the spawn menu uses "entities/<class>.png".
  icon = "IconOverride",
  -- Whether the bike spawns (from the spawn menu) with a random color.
  randomColor = "RandomColor",
  -- Physics mass without a rider.
  mass = "EmptyMass",
  -- Wheel revolutions per crank revolution.
  gearRatio = "GearRatio",
  -- How far the collision hull's wheels are shrunk, so they only act as bump stops.
  wheelHullScale = "WheelHullScale",
  -- Where the rider sits relative to the "seat" attachment.
  seatOffset = "SeatOffset",
  -- Degrees the rider is tilted forward.
  seatPitch = "SeatPitch",
  -- Degrees the rider tucks further forward while sprint-pedalling.
  sprintLeanPitch = "SprintLeanPitch",
  -- Degrees the rider leans back while wheelieing.
  wheelieLeanPitch = "WheelieLeanPitch",
  -- How far the seat moves while wheelieing: forward, left and up.
  wheelieSeatShift = "WheelieSeatShift",
  -- Degrees the rider leans forward while holding the forward lean (for stoppies).
  leanForwardPitch = "LeanForwardPitch",
  -- How far the seat moves while leaning forward: forward, left and up.
  leanForwardSeatShift = "LeanForwardSeatShift",
  -- How far out from the pedal attachments the feet are placed.
  pedalCenterOffset = "PedalCenterOffset",
  -- How far above the pedal's axle the ball of the foot sits.
  footBallHeight = "FootBallHeight",
  -- Where the hands hold relative to the grip attachments: forward, outward (mirrored for each side) and up.
  gripOffset = "GripOffset",
  -- The measurements below are read from the model on spawn, these are only used until then or if that fails.
  wheelRadius = "WheelRadius",
  seatPosition = "SeatPosition",
}

--- @type table<string, string> The entity class field each definition key sets
bicycle.modelDefinitionFields = DEFINITION_FIELDS

--- @type table<string, table> Definitions by id, as passed to `bicycle.registerModel`
bicycle.models = bicycle.models or {}

--- Pastes a bike from a dupe. The default duplicator merges the whole saved entity table onto the new bike, and dupe
--- files come from clients, so that would let them set any field. Only the generic entity data (position, angles,
--- color, material, skin and such) is restored here.
local function pasteBicycle(player, data)
  local className = data.Class

  if (IsValid(player) and not player:IsAdmin()
        and (not scripted_ents.GetMember(className, "Spawnable") or scripted_ents.GetMember(className, "AdminOnly"))) then
    return
  end

  local entity = ents.Create(className)

  if (not IsValid(entity)) then
    return
  end

  duplicator.DoGeneric(entity, data)
  entity:Spawn()
  entity:Activate()
  duplicator.DoGenericPhysics(entity, player, data)

  return entity
end

--- @param id string
--- @return string # The entity class a model is registered as
function bicycle.getModelClass(id)
  return bicycle.ENTITY_CLASS .. "_" .. id
end

--- Registers a bike model as the spawnable entity class "sent_bicycle_<id>". Call it from the
--- "BicycleRegisterModels" hook, on both the server and the client.
--- @param id string Unique, used in the class name
--- @param definition table `model` is required, see `DEFINITION_FIELDS` for the rest. `rearHub` and `frontHub` (both
--- entity-local vectors) are fallback wheel positions, like `wheelRadius`.
--- @return string? # The entity class, nil when the definition is invalid
function bicycle.registerModel(id, definition)
  if (not isstring(id) or not isstring(definition.model)) then
    ErrorNoHaltWithStack("[bicycle] registerModel needs a string id and a definition with a model path.\n")
    return nil
  end

  local className = bicycle.getModelClass(id)
  local entityTable = {
    Type = "anim",
    Base = bicycle.ENTITY_CLASS,
    PrintName = definition.name or id,
    Category = definition.category or DEFAULT_CATEGORY,
    Spawnable = true,
    BicycleModelId = id,
  }

  for key, field in pairs(DEFINITION_FIELDS) do
    entityTable[field] = definition[key]
  end

  if (definition.rearHub and definition.frontHub) then
    entityTable.Wheels = {
      { position = definition.rearHub,  isFront = false },
      { position = definition.frontHub, isFront = true },
    }
    entityTable.Wheelbase = definition.frontHub.x - definition.rearHub.x
  end

  bicycle.models[id] = definition
  scripted_ents.Register(entityTable, className)

  if (SERVER) then
    duplicator.RegisterEntityClass(className, pasteBicycle, "Data")
  end

  return className
end

--- Changes one setting of a registered model live: on its definition, on its entity class for bikes spawned later and
--- on every bike of it that is already spawned.
--- @param id string
--- @param key string A key of `DEFINITION_FIELDS`
--- @param value any
--- @return boolean # False when the model or key is unknown
function bicycle.setModelSetting(id, key, value)
  local definition, field = bicycle.models[id], DEFINITION_FIELDS[key]

  if (not definition or not field) then
    return false
  end

  local className = bicycle.getModelClass(id)
  local stored = scripted_ents.GetStored(className)

  definition[key] = value

  if (stored) then
    stored.t[field] = value
  end

  for _, bike in ipairs(ents.FindByClass(className)) do
    bike[field] = value

    if (bike.OnModelSettingChanged) then
      bike:OnModelSettingChanged(key)
    end
  end

  hook.Run("BicycleModelSettingChanged", id, key, value)

  return true
end

hook.Add("OnGamemodeLoaded", "bicycle.registerModels", function()
  hook.Run("BicycleRegisterModels")
end)

hook.Add("BicycleRegisterModels", "bicycle.defaultModel", function()
  bicycle.registerModel("default", {
    name = "Colourable Mountain Bike",
    model = "models/bicycle/bicycle.mdl",
    icon = "entities/colourable_mountain_bike.png",
    randomColor = true,
    mass = 15,
    gearRatio = 2.8,
    wheelHullScale = 0.7,
    seatOffset = Vector(-7.02, 0, 0),
    seatPitch = 33.55,
    sprintLeanPitch = 25,
    wheelieLeanPitch = 0,
    wheelieSeatShift = Vector(-1.93, 0, 1.58),
    leanForwardPitch = 15,
    leanForwardSeatShift = Vector(3, 0, 1),
    pedalCenterOffset = 3.38,
    footBallHeight = 1,
    gripOffset = Vector(-0.12, -0.58, 1.17),
    wheelRadius = 16.01,
    rearHub = Vector(-22.57, 0, -1.74),
    frontHub = Vector(25.02, 0, -1.74),
    seatPosition = Vector(-12.42, 0.02, 21.16),
  })
end)
