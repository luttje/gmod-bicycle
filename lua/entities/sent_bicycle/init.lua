AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")

include("shared.lua")
include("sv_ride.lua")
include("sv_tricks.lua")

local SPAWN_HEIGHT = 24

local RIDER_SEAT_MODEL = "models/nova/airboat_seat.mdl"
local PASSENGER_SEAT_MODEL = "models/nova/jeep_seat.mdl"

-- Random spawn colors pick any hue, but stay saturated and bright enough to not look muddy.
local RANDOM_COLOR_SATURATION = 0.7
local RANDOM_COLOR_VALUE = 0.9

-- Leaning further than this counts as fallen over, so getting on stands the bike back up first.
local FALLEN_OVER_LEAN = 35

-- Stops the same key press that got a player on or off the bike from immediately undoing it.
local USE_COOLDOWN_AFTER_ENTERING = 0.5
local USE_COOLDOWN_AFTER_LEAVING = 0.6

-- Where a rider may stand after getting off, relative to the bike's heading, tried in order.
local DISMOUNT_OFFSETS = {
  { forward = 0,   right = -34, up = 24 },
  { forward = 0,   right = 34,  up = 24 },
  { forward = -60, right = 0,   up = 24 },
  { forward = 0,   right = 0,   up = 44 },
}
-- Crashing throws the rider over the bike rather than to the side of it.
local CRASH_DISMOUNT_OFFSETS = {
  { forward = 0, right = 0,   up = 36 },
  { forward = 0, right = -34, up = 24 },
  { forward = 0, right = 34,  up = 24 },
}
-- The fallback when no offset fits: straight up from the bike, as far as there is room.
local FALLBACK_DISMOUNT_HEIGHT = 40
-- Right after leaving, the engine may still move the rider, which stays near the bike. Anything further away was
-- moved there by something else, such as an admin teleport, which must be left alone.
local MAX_DISMOUNT_CORRECTION_DISTANCE = 128
local CRASH_EJECT_VELOCITY_SCALE = 0.8
local CRASH_EJECT_UPWARD_SPEED = 160
-- How long a crashed rider's RagMod ragdoll passes through the bike they were put down overlapping.
local RAGMOD_BIKE_NO_COLLIDE_TIME = 0.2

local IMPACT_SOUND_MIN_SPEED = 150
local IMPACT_SOUND_INTERVAL = 0.2
-- Impacts closer to head-on than this (dot product with the heading) count as frontal.
local FRONTAL_IMPACT_DOT = 0.6
-- Any other impact this many times bicycle_crash_speed throws the rider off, frontal or not.
local ANY_IMPACT_CRASH_SCALE = 2
-- Surfaces at most this steep (deg from the bike's up) are ground the tyres land on, as in the wheel traces. Hitting
-- them is a landing, judged by bicycle_land_crash_speed instead.
local MAX_LANDING_GROUND_ANGLE = 60
local MIN_LANDING_GROUND_UP = math.cos(math.rad(MAX_LANDING_GROUND_ANGLE))

-- Sprint-pedalling and leaning forward tuck the rider forward and wheelieing leans them back, blending in and out at
-- this rate.
local SEAT_POSE_RESPONSE = 4
local SPRINT_LEAN_MIN_SPEED = 40
-- Below this change (fraction of the full pose) the seat isn't moved, so a settled pose doesn't network every tick.
local SEAT_POSE_EPSILON = 0.002
-- Model settings that move the seat.
local SEAT_POSE_KEYS = {
  seatOffset = true,
  seatPitch = true,
  sprintLeanPitch = true,
  wheelieLeanPitch = true,
  wheelieSeatShift = true,
  leanForwardPitch = true,
  leanForwardSeatShift = true,
}

function ENT:SpawnFunction(player, trace, className)
  if (not trace.Hit) then
    return
  end

  local entity = ents.Create(className)
  entity:SetPos(trace.HitPos + trace.HitNormal * SPAWN_HEIGHT)
  entity:SetAngles(Angle(0, player:EyeAngles().y, 0))

  if (entity.RandomColor) then
    entity:SetColor(HSVToColor(math.random(0, 359), RANDOM_COLOR_SATURATION, RANDOM_COLOR_VALUE))
  end

  entity:Spawn()
  entity:Activate()

  return entity
end

function ENT:Initialize()
  if (not self.Model) then
    ErrorNoHalt(string.format(
      "[bicycle] %s has no model, spawn one of the classes registered with bicycle.registerModel instead.\n",
      self:GetClass()
    ))
    self:Remove()
    return
  end

  self:SetModel(self.Model)
  self:MeasureGeometry()
  self:BuildPhysics()
  self:NetworkGeometry()
  self:SetUseType(SIMPLE_USE)

  local physics = self:GetPhysicsObject()

  if (IsValid(physics)) then
    physics:SetMaterial("metal")
    physics:SetMass(self.EmptyMass)
    physics:SetDamping(0, 0.5)
    physics:EnableDrag(false)
    self.inertiaPerMass = physics:GetInertia() / self.EmptyMass
    physics:Wake()
  end

  self.steerFraction = 0
  self.wasJumpHeld = false
  self.wasBellHeld = false
  self.tapPressedAt = {}
  self.pendingDoubleTaps = {}
  self.nextHopAt = 0
  self.nextBellAt = 0
  self.nextImpactSoundAt = 0
  self.sprintLeanFraction = 0
  self.wheelieLeanFraction = 0
  self.forwardLeanFraction = 0
  self.isWheelieing = false
  self.isStoppieing = false
  self.restingOffWheelsTime = 0
  self.trickStates = {}
  self.airKeysHeldSinceTakeoff = { steerDirection = 0, isPedalHeld = false, isBrakeHeld = false }
  self.takeoffSlope = 0
  self.isAirSpinControlled = false
  self.isAirTurning = false

  self:StartMotionController()
  self:ApplyBodyGroups()
  self:CreateSeat()
  self:CreatePassengerSeat()
end

function ENT:ApplyBodyGroups()
  if (not self.BodyGroups) then
    return
  end

  for name, submodel in pairs(self.BodyGroups) do
    local index = self:FindBodygroupByName(name)

    if (index >= 0) then
      self:SetBodygroup(index, submodel)
    else
      ErrorNoHalt(string.format("[bicycle] %s has no bodygroup named %q.\n", self:GetModel(), name))
    end
  end
end

--- @return Vector? # Entity-local, nil when the model has no such bone
function ENT:GetBoneLocalPosition(boneName)
  local bone = self:LookupBone(boneName)
  local position = bone and self:GetBonePosition(bone)

  return position and self:WorldToLocal(position)
end

--- Reads the wheel hubs from the wheel bones and the saddle from the seat attachment.
function ENT:MeasureGeometry()
  local rearHub = self:GetBoneLocalPosition(self.RearWheelBone)
  local frontHub = self:GetBoneLocalPosition(self.FrontWheelBone)

  -- A model facing the wrong way, or bones read before they were set up, would leave the front wheel behind the rear.
  if (rearHub and frontHub and frontHub.x > rearHub.x) then
    self:ApplyGeometry(rearHub, frontHub, self.WheelRadius)
  else
    ErrorNoHalt(string.format(
      "[bicycle] Couldn't read the wheel hubs from %s (rear %s, front %s), using the built-in measurements.\n",
      self:GetModel(),
      tostring(rearHub),
      tostring(frontHub)
    ))
  end

  self.SeatPosition = self:GetAttachmentLocalPosition(self.SeatAttachment) or self.SeatPosition
end

function ENT:NetworkGeometry()
  self:SetWheelRadius(self.WheelRadius)
  self:SetRearHub(self.Wheels[1].position)
  self:SetFrontHub(self.Wheels[2].position)
end

-- The duplicator restores the saved network vars after spawning, and dupe files come from clients, so the measured
-- geometry is networked again over whatever they held.
function ENT:OnDuplicated()
  self:NetworkGeometry()
  self:SetCrashed(false)
end

local function getConvexBounds(convex)
  local mins = Vector(math.huge, math.huge, math.huge)
  local maxs = -mins

  for _, vertex in ipairs(convex) do
    local position = vertex.pos

    mins.x, mins.y, mins.z = math.min(mins.x, position.x), math.min(mins.y, position.y), math.min(mins.z, position.z)
    maxs.x, maxs.y, maxs.z = math.max(maxs.x, position.x), math.max(maxs.y, position.y), math.max(maxs.z, position.z)
  end

  return mins, maxs
end

--- @param wheelCenter? Vector When given, the convex is shrunk around it within the wheel plane
local function getVertexPositions(convex, wheelCenter, wheelScale)
  local positions = {}

  for index, vertex in ipairs(convex) do
    local position = vertex.pos

    if (wheelCenter) then
      position = Vector(
        wheelCenter.x + (position.x - wheelCenter.x) * wheelScale,
        position.y,
        wheelCenter.z + (position.z - wheelCenter.z) * wheelScale
      )
    end

    positions[index] = position
  end

  return positions
end

--- Rebuilds the model's own collision hull with the wheels shrunk, so the tyres are handled by the wheel traces and
--- the hull only works as a bump stop. The unshrunk wheel discs give the wheel radius.
function ENT:BuildPhysics()
  self:PhysicsInit(SOLID_VPHYSICS)

  local physics = self:GetPhysicsObject()
  local convexes = IsValid(physics) and physics:GetMeshConvexes()

  if (not convexes or #convexes == 0) then
    return
  end

  local convexBounds = {}
  local lowestPoint = math.huge

  for index, convex in ipairs(convexes) do
    local mins, maxs = getConvexBounds(convex)

    convexBounds[index] = { mins = mins, maxs = maxs }
    lowestPoint = math.min(lowestPoint, mins.z)
  end

  -- The tyres are the lowest part of the bike, so the hubs sit about a wheel radius above the lowest point.
  local approximateWheelRadius = self.Wheels[1].position.z - lowestPoint
  local rebuiltConvexes = {}
  local wheelRadiusSum, wheelCount = 0, 0

  for index, convex in ipairs(convexes) do
    local bounds = convexBounds[index]
    local height = bounds.maxs.z - bounds.mins.z
    -- Only the wheels reach the bottom of the model while being taller than a wheel radius.
    local isWheel = bounds.mins.z < lowestPoint + 1 and height > approximateWheelRadius
    local wheelCenter = isWheel and (bounds.mins + bounds.maxs) * 0.5 or nil

    if (isWheel) then
      wheelRadiusSum, wheelCount = wheelRadiusSum + height * 0.5, wheelCount + 1
    end

    rebuiltConvexes[index] = getVertexPositions(convex, wheelCenter, self.WheelHullScale)
  end

  if (wheelCount > 0) then
    self.WheelRadius = wheelRadiusSum / wheelCount
  end

  if (not self:PhysicsInitMultiConvex(rebuiltConvexes)) then
    self:PhysicsInit(SOLID_VPHYSICS)
    return
  end

  self:SetSolid(SOLID_VPHYSICS)
  self:SetMoveType(MOVETYPE_VPHYSICS)
  self:EnableCustomCollisions(true)
end

--- Creates an invisible seat parented to the bike. It has no collisions and no motion of its own, so it weighs nothing
--- and costs the bike's physics nothing.
--- @param model string
--- @param localPosition Vector
--- @param localAngles Angle
--- @return Entity?
local function createSeat(bike, model, localPosition, localAngles)
  local seat = ents.Create("prop_vehicle_prisoner_pod")

  if (not IsValid(seat)) then
    return nil
  end

  seat:SetModel(model)
  seat:SetKeyValue("vehiclescript", "scripts/vehicles/prisoner_pod.txt")
  seat:SetKeyValue("limitview", "0")
  seat:SetPos(bike:LocalToWorld(localPosition))
  seat:SetAngles(bike:LocalToWorldAngles(localAngles))
  seat:Spawn()
  seat:Activate()
  seat:SetMoveType(MOVETYPE_NONE)
  seat:SetParent(bike)
  seat:SetNotSolid(true)
  seat:SetNoDraw(true)
  seat:DrawShadow(false)

  local seatPhysics = seat:GetPhysicsObject()

  if (IsValid(seatPhysics)) then
    seatPhysics:EnableMotion(false)
    seatPhysics:EnableCollisions(false)
  end

  seat.PhysgunDisabled = true
  seat.DoNotDuplicate = true

  bike:DeleteOnRemove(seat)

  return seat
end

function ENT:CreateSeat()
  local seat = createSeat(self, RIDER_SEAT_MODEL, self:GetSeatOffset(), self:GetSeatLocalAngles())

  if (not IsValid(seat)) then
    return
  end

  seat:SetNW2Bool("bicycle_Seat", true)
  self:SetSeat(seat)
end

--- Only for models with a passenger attachment. The passenger just sits there: they don't ride, pose or add weight.
function ENT:CreatePassengerSeat()
  if (not self.PassengerAttachment) then
    return
  end

  local offset = self:GetPassengerSeatOffset()

  if (not offset) then
    ErrorNoHalt(string.format(
      "[bicycle] %s has no %q attachment for the passenger seat.\n",
      self:GetModel(),
      self.PassengerAttachment
    ))
    return
  end

  local seat = createSeat(self, PASSENGER_SEAT_MODEL, offset, self.SeatAngles)

  if (not IsValid(seat)) then
    return
  end

  seat:SetNW2Bool("bicycle_PassengerSeat", true)
  self.passengerSeat = seat
end

--- Whether `player` using the bike takes the passenger seat: when someone already rides it, or else when they aim
--- closer to the passenger seat than to the saddle.
--- @param player Player
--- @return boolean
function ENT:IsChoosingPassengerSeat(player)
  local seat = self.passengerSeat

  if (not IsValid(seat) or IsValid(seat:GetDriver())) then
    return false
  end

  if (IsValid(self:GetRider())) then
    return true
  end

  local aimPosition = player:GetEyeTrace().HitPos

  return aimPosition:DistToSqr(seat:GetPos()) < aimPosition:DistToSqr(self:LocalToWorld(self:GetSeatOffset()))
end

function ENT:Use(activator)
  if (not IsValid(activator) or not activator:IsPlayer() or activator:InVehicle()) then
    return
  end

  -- Getting on a bike someone holds with the physgun would let them fling the rider around.
  if (self.isPhysgunHeld or (activator._BicycleNextUseAt or 0) > CurTime()) then
    return
  end

  if (self.PassengerAttachment and not IsValid(self.passengerSeat)) then
    self:CreatePassengerSeat()
  end

  if (self:IsChoosingPassengerSeat(activator)) then
    -- The third argument tells gamemodes the player gets on as the passenger.
    if (hook.Run("BicycleCanMount", activator, self, true) ~= false) then
      activator:EnterVehicle(self.passengerSeat)
    end

    return
  end

  if (IsValid(self:GetRider())) then
    return
  end

  -- Lets gamemodes keep players off bikes, such as ones they don't own. Checked before a fallen bike is stood up.
  if (hook.Run("BicycleCanMount", activator, self) == false) then
    return
  end

  -- The rider would be thrown straight back off.
  if (self:IsTooDeepToRide()) then
    return
  end

  if (not IsValid(self:GetSeat())) then
    self:CreateSeat()
  end

  if (self:GetCrashed() or math.abs(self:GetLean()) > FALLEN_OVER_LEAN) then
    self:StandUp()
  end

  activator:EnterVehicle(self:GetSeat())
end

--- Stands a fallen bike back up on its wheels.
function ENT:StandUp()
  local position = self:GetPos()
  local filter = self:GetWheelTraceFilter()
  -- The bike is only raised as far as there is room above it, so it can't be put through a thin floor or overhang.
  local ceilingTrace = util.TraceLine({
    start = position,
    endpos = position + vector_up * SPAWN_HEIGHT,
    filter = filter,
    mask = MASK_SOLID,
  })
  local groundTrace = util.TraceLine({
    start = ceilingTrace.HitPos,
    endpos = position - vector_up * 60,
    filter = filter,
    mask = MASK_SOLID,
  })
  local standingPosition = (groundTrace.Hit and groundTrace.HitPos or position) + vector_up * SPAWN_HEIGHT
  standingPosition.z = math.Clamp(standingPosition.z, position.z, ceilingTrace.HitPos.z)

  self:SetAngles(Angle(0, self:GetAngles().y, 0))
  self:SetPos(standingPosition)

  local physics = self:GetPhysicsObject()

  if (IsValid(physics)) then
    physics:SetVelocity(vector_origin)
    physics:AddAngleVelocity(-physics:GetAngleVelocity())
    physics:Wake()
  end

  self:SetCrashed(false)
end

--- The rider's weight is added to the bike itself, so riding feels heavier without simulating a second body.
--- @param isRidden boolean
function ENT:UpdateMass(isRidden)
  local physics = self:GetPhysicsObject()

  if (not IsValid(physics)) then
    return
  end

  local mass = isRidden and bicycle.getTuning("mass_ridden") or self.EmptyMass
  physics:SetMass(mass)

  if (self.inertiaPerMass) then
    physics:SetInertia(self.inertiaPerMass * mass)
  end

  physics:Wake()
end

--- Picks up a model setting changed live.
--- @param key string
function ENT:OnModelSettingChanged(key)
  if (key == "mass") then
    self:UpdateMass(IsValid(self:GetRider()))
  elseif (SEAT_POSE_KEYS[key] and IsValid(self:GetSeat())) then
    self:GetSeat():SetLocalPos(self:GetSeatOffset())
    self:GetSeat():SetLocalAngles(self:GetSeatLocalAngles())
  elseif (key == "passengerSeatOffset" and IsValid(self.passengerSeat)) then
    self.passengerSeat:SetLocalPos(self:GetPassengerSeatOffset())
  end
end

function ENT:OnRiderEnter(player)
  self:SetRider(player)
  self:SetCrashed(false)
  self:UpdateMass(true)

  -- The Use or Jump press that got the rider on shouldn't also hop.
  self.wasJumpHeld = true
  player._BicycleNextUseAt = CurTime() + USE_COOLDOWN_AFTER_ENTERING

  -- Riders start out looking ahead.
  player:SetEyeAngles(self.SeatForwardEyeAngles)

  hook.Run("BicycleRiderMounted", player, self)
end

function ENT:OnPassengerEnter(player)
  self:SetPassenger(player)
  player._BicycleNextUseAt = CurTime() + USE_COOLDOWN_AFTER_ENTERING
  player:SetEyeAngles(self.SeatForwardEyeAngles)

  hook.Run("BicyclePassengerMounted", player, self)
end

--- Finds the first offset where the player fits and which can be reached from the bike without passing through a wall.
--- @param player Player
--- @param offsets table[] Relative to the bike's heading, see `DISMOUNT_OFFSETS`
--- @return Vector? # Nil when none of the offsets fits
function ENT:FindDismountPosition(player, offsets)
  local mins, maxs = player:GetHull()
  local origin = self:GetPos()
  local forward, right = self:GetForward(), self:GetRight()
  local filter = self:GetWheelTraceFilter()
  filter[#filter + 1] = player

  forward.z, right.z = 0, 0
  forward:Normalize()
  right:Normalize()

  for _, offset in ipairs(offsets) do
    local target = origin + forward * offset.forward + right * offset.right
    local raisedTarget = target + vector_up * offset.up
    local lineOfSight = util.TraceLine({
      start = origin + vector_up * 10,
      endpos = raisedTarget,
      filter = filter,
      mask = MASK_PLAYERSOLID,
    })

    if (lineOfSight.Hit) then
      continue
    end

    local groundTrace = util.TraceHull({
      start = raisedTarget,
      endpos = target - vector_up * 48,
      mins = mins,
      maxs = maxs,
      filter = filter,
      mask = MASK_PLAYERSOLID,
    })

    if (groundTrace.Hit and not groundTrace.StartSolid) then
      return groundTrace.HitPos
    end
  end

  return nil
end

--- For riders that have to get off even though no dismount offset fits, such as after a crash: straight up from the
--- bike as far as the player fits, or else where they sat.
--- @param player Player
--- @return Vector
function ENT:FindFallbackDismountPosition(player)
  local mins, maxs = player:GetHull()
  local origin = self:GetPos()
  local filter = self:GetWheelTraceFilter()
  filter[#filter + 1] = player

  local trace = util.TraceHull({
    start = origin,
    endpos = origin + vector_up * FALLBACK_DISMOUNT_HEIGHT,
    mins = mins,
    maxs = maxs,
    filter = filter,
    mask = MASK_PLAYERSOLID,
  })

  if (not trace.StartSolid) then
    return trace.HitPos
  end

  local seat = self:GetSeat()

  return IsValid(seat) and seat:GetPos() or origin
end

--- Called when the rider asks to get off. With dismount_anywhere off they stay on when there is nowhere to stand, as
--- the fallback position could be past a player clip the bike rode through.
--- @param player Player
--- @return boolean
function ENT:CanRiderLeave(player)
  local position = self:FindDismountPosition(player, DISMOUNT_OFFSETS)

  if (not position) then
    -- Not being able to exit the bicycle can confuse players, so servers can opt into the fallback instead.
    if (not bicycle.getTuningBool("dismount_anywhere")) then
      return false
    end

    position = self:FindFallbackDismountPosition(player)
  end

  self.plannedDismount = { position = position, at = CurTime() }

  return true
end

--- Where a rider getting off now should stand.
--- @param player Player
--- @param isCrashing boolean
--- @return Vector
function ENT:GetDismountPosition(player, isCrashing)
  local plannedDismount = self.plannedDismount
  self.plannedDismount = nil

  -- Only when planned for this exit: another hook may have kept the rider on after it was planned.
  if (not isCrashing and plannedDismount and plannedDismount.at == CurTime()) then
    return plannedDismount.position
  end

  return self:FindDismountPosition(player, isCrashing and CRASH_DISMOUNT_OFFSETS or DISMOUNT_OFFSETS)
      or self:FindFallbackDismountPosition(player)
end

--- Throws a crashed rider as a RagMod ragdoll, when RagMod is installed and both its and our server settings allow it.
--- @param player Player
--- @param ejectVelocity Vector
--- @return boolean # Whether the rider became a ragdoll
local function tryRagmodRagdoll(player, ejectVelocity)
  if (not bicycle.getTuningBool("ragmod_crash")) then
    return false
  end

  if (not ragmod or not ragmod.TryToRagdoll or not RagModOptions or not RagModOptions.Enabled()) then
    return false
  end

  local ragdoll = ragmod:TryToRagdoll(player)

  if (not IsValid(ragdoll)) then
    return false
  end

  ragdoll:SetCollisionGroup(COLLISION_GROUP_WEAPON)
  ragdoll:SetVelocity(ejectVelocity)
  ragdoll:PlayRagSound()

  timer.Simple(RAGMOD_BIKE_NO_COLLIDE_TIME, function()
    if (IsValid(ragdoll) and ragdoll:GetCollisionGroup() == COLLISION_GROUP_WEAPON) then
      ragdoll:SetCollisionGroup(COLLISION_GROUP_NONE)
    end
  end)

  return true
end

--- The engine may still move a player after the leave hooks, so their dismount position is enforced again next tick.
--- @param player Player
--- @param position Vector
--- @param bikePosition Vector
--- @param onHeld? function Called once the position is enforced again
local function holdDismountPosition(player, position, bikePosition, onHeld)
  timer.Simple(0, function()
    if (not IsValid(player) or player:InVehicle() or not player:Alive()) then
      return
    end

    -- Moved far away by something else, such as an admin teleport or a jail.
    if (player:GetPos():DistToSqr(bikePosition) > MAX_DISMOUNT_CORRECTION_DISTANCE * MAX_DISMOUNT_CORRECTION_DISTANCE) then
      return
    end

    player:SetPos(position)

    if (onHeld) then
      onHeld()
    end
  end)
end

function ENT:OnRiderLeave(player)
  if (self:GetRider() ~= player) then
    return
  end

  self:SetRider(NULL)
  self:UpdateMass(false)
  self:ResetTricks()
  self.steerFraction = 0
  player._BicycleNextUseAt = CurTime() + USE_COOLDOWN_AFTER_LEAVING

  local isCrashing = self.isEjectingFromCrash
  self.isEjectingFromCrash = nil

  -- Capped, so a bike thrown with the physgun doesn't fling its rider across the map.
  local velocity = self:GetVelocity()
  local maxEjectSpeed = bicycle.getTuning("sprint_speed")

  if (velocity:Length() > maxEjectSpeed) then
    velocity:Normalize()
    velocity:Mul(maxEjectSpeed)
  end

  local position = self:GetDismountPosition(player, isCrashing)

  player:SetPos(position)
  player:SetEyeAngles(Angle(0, self:GetAngles().y, 0))

  hook.Run("BicycleRiderDismounted", player, self, isCrashing == true)

  holdDismountPosition(player, position, self:GetPos(), isCrashing and function()
    local ejectVelocity = velocity * CRASH_EJECT_VELOCITY_SCALE + vector_up * CRASH_EJECT_UPWARD_SPEED

    -- Lets gamemodes react to the rider flying over the handlebars, such as by knocking them out. Returning false
    -- keeps the rider from being thrown, so the gamemode can handle that itself.
    if (hook.Run("BicycleRiderCrashed", player, self, ejectVelocity) ~= false
          and not tryRagmodRagdoll(player, ejectVelocity)) then
      player:SetVelocity(ejectVelocity)
    end
  end)
end

--- The passenger gets off where a rider would, wherever the bike is, as the seat's own exit points could be in a wall.
function ENT:OnPassengerLeave(player)
  if (self:GetPassenger() == player) then
    self:SetPassenger(NULL)
  end

  player._BicycleNextUseAt = CurTime() + USE_COOLDOWN_AFTER_LEAVING

  local position = self:FindDismountPosition(player, DISMOUNT_OFFSETS) or self:FindFallbackDismountPosition(player)

  player:SetPos(position)
  player:SetEyeAngles(Angle(0, self:GetAngles().y, 0))

  hook.Run("BicyclePassengerDismounted", player, self)

  holdDismountPosition(player, position, self:GetPos())
end

--- @param isIntoWater? boolean Whether the rider rode into water too deep to ride through
function ENT:Crash(isIntoWater)
  if (self:GetCrashed()) then
    return
  end

  local rider = self:GetRider()

  -- Lets gamemodes keep riders on, such as in safe zones.
  if (IsValid(rider) and hook.Run("BicycleShouldCrash", self, rider) == false) then
    return
  end

  self:SetCrashed(true)

  if (isIntoWater) then
    self:EmitBicycleSound("ambient/water/water_splash" .. math.random(1, 3) .. ".wav", 75, math.random(95, 110))
  else
    self:EmitBicycleSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 75, math.random(95, 110))
  end

  if (IsValid(rider)) then
    self.isEjectingFromCrash = true
    rider:ExitVehicle()
  end

  local passenger = self:GetPassenger()

  if (IsValid(passenger)) then
    passenger:ExitVehicle()
  end
end

--- Plays nothing while the server has turned bike sounds off.
function ENT:EmitBicycleSound(...)
  if (bicycle.getTuningBool("sounds")) then
    self:EmitSound(...)
  end
end

--- @param impactSpeed number Speed into what was hit (u/s)
--- @param surfaceNormal Vector Facing out of what was hit
--- @return boolean # Whether hitting something this hard throws the rider off
function ENT:IsCrashImpact(impactSpeed, surfaceNormal)
  if (surfaceNormal:Dot(self:GetUp()) >= MIN_LANDING_GROUND_UP) then
    return impactSpeed > bicycle.getTuning("land_crash_speed")
  end

  local crashSpeed = bicycle.getTuning("crash_speed")
  local isFrontal = math.abs(surfaceNormal:Dot(self:GetForward())) > FRONTAL_IMPACT_DOT

  return (isFrontal and impactSpeed > crashSpeed) or impactSpeed > crashSpeed * ANY_IMPACT_CRASH_SCALE
end

-- Changing entity state inside a physics callback is unsafe, so impacts are only recorded here and handled in Think.
function ENT:PhysicsCollide(collision)
  local approachSpeed = collision.OurOldVelocity:Dot(collision.HitNormal)
  local impactSpeed = math.abs(approachSpeed)
  -- Turned to face against the bike's way into what it hit, whichever way the engine gave it.
  local surfaceNormal = approachSpeed > 0 and collision.HitNormal * -1 or collision.HitNormal

  if (impactSpeed > IMPACT_SOUND_MIN_SPEED and self.nextImpactSoundAt < CurTime()) then
    self.nextImpactSoundAt = CurTime() + IMPACT_SOUND_INTERVAL
    self.pendingImpactSoundSpeed = impactSpeed
  end

  local rider = self:GetRider()

  -- A bike held with the physgun is thrown around by someone else, the rider shouldn't be ejected by it.
  if (not IsValid(rider) or self:GetCrashed() or self.isPhysgunHeld or collision.HitEntity == rider) then
    return
  end

  if (self:IsCrashImpact(impactSpeed, surfaceNormal)) then
    self.hasPendingCrash = true
  end
end

function ENT:HandlePendingImpacts()
  if (self.hasPendingCrash) then
    local isIntoWater = self.isCrashingIntoWater == true

    self.hasPendingCrash = nil
    self.isCrashingIntoWater = nil
    self:Crash(isIntoWater)
  end

  local impactSpeed = self.pendingImpactSoundSpeed

  if (impactSpeed) then
    self.pendingImpactSoundSpeed = nil
    self:EmitBicycleSound(
      "physics/metal/metal_solid_impact_soft" .. math.random(1, 3) .. ".wav",
      70,
      100,
      math.Clamp(impactSpeed / 500, 0.2, 1)
    )
  end
end

--- The ride only records these sounds, since it runs inside the physics step.
function ENT:HandlePendingSounds()
  if (self.hasPendingHopSound) then
    self.hasPendingHopSound = nil
    self:EmitBicycleSound("bicycle/frame_creak.wav", 70, math.random(95, 105))
  end

  if (self.hasPendingBell) then
    self.hasPendingBell = nil
    self:TryRingBell()
  end
end

function ENT:TryRingBell()
  local rider = self:GetRider()

  if (not IsValid(rider) or not bicycle.getTuningBool("bell") or self.nextBellAt > CurTime()) then
    return
  end

  -- Lets gamemodes silence the bell, such as for a team or in a quiet zone.
  if (hook.Run("BicycleCanRingBell", self, rider) == false) then
    return
  end

  self.nextBellAt = CurTime() + bicycle.getTuning("bell_cooldown")
  self:EmitBicycleSound("bicycle/bell.wav", 80, math.random(98, 102))
end

--- Catches riders that left without PlayerLeaveVehicle, such as by dying.
function ENT:ValidateRider()
  local rider, seat = self:GetRider(), self:GetSeat()

  if (not IsValid(rider)) then
    return
  end

  if (not IsValid(seat) or rider:GetVehicle() ~= seat or not rider:Alive()) then
    self:SetRider(NULL)
    self:UpdateMass(false)
    return
  end

  -- PhysicsSimulate stops running once the bike falls asleep, which a balanced bike standing still would.
  local physics = self:GetPhysicsObject()

  if (IsValid(physics)) then
    physics:Wake()
  end
end

--- Catches passengers that left without PlayerLeaveVehicle, such as by dying.
function ENT:ValidatePassenger()
  local passenger = self:GetPassenger()

  if (IsValid(passenger) and (passenger:GetVehicle() ~= self.passengerSeat or not passenger:Alive())) then
    self:SetPassenger(NULL)
  end
end

local function approachPoseFraction(fraction, isActive)
  local target = isActive and 1 or 0
  fraction = Lerp(1 - math.exp(-SEAT_POSE_RESPONSE * FrameTime()), fraction, target)

  if (math.abs(fraction - target) < SEAT_POSE_EPSILON) then
    return target
  end

  return fraction
end

--- Eases the rider forward over the handlebar while they sprint-pedal or lean forward, back and up while they wheelie,
--- and upright once they stop.
function ENT:UpdateSeatPose()
  local rider = self:GetRider()
  local isRiding = IsValid(rider) and not self:GetCrashed()
  local isWheelieing = isRiding and self.isWheelieing
  local isLeaningForward = isRiding and not isWheelieing and rider:KeyDown(IN_ATTACK)
  local isSprinting = isRiding
      and not isWheelieing
      and not isLeaningForward
      and rider:KeyDown(IN_SPEED)
      and rider:KeyDown(IN_FORWARD)
      and self:GetForwardSpeed() > SPRINT_LEAN_MIN_SPEED
  local sprintLeanFraction = approachPoseFraction(self.sprintLeanFraction, isSprinting)
  local wheelieLeanFraction = approachPoseFraction(self.wheelieLeanFraction, isWheelieing)
  local forwardLeanFraction = approachPoseFraction(self.forwardLeanFraction, isLeaningForward)

  if (sprintLeanFraction == self.sprintLeanFraction and wheelieLeanFraction == self.wheelieLeanFraction
        and forwardLeanFraction == self.forwardLeanFraction) then
    return
  end

  self.sprintLeanFraction = sprintLeanFraction
  self.wheelieLeanFraction = wheelieLeanFraction
  self.forwardLeanFraction = forwardLeanFraction

  local seat = self:GetSeat()

  if (IsValid(seat)) then
    seat:SetLocalPos(self:GetSeatOffset())
    seat:SetLocalAngles(self:GetSeatLocalAngles())
  end
end

function ENT:Think()
  self:HandlePendingImpacts()
  self:HandleLandedTricks()
  self:HandlePendingSounds()
  self:ValidateRider()
  self:ValidatePassenger()
  self:UpdateSeatPose()

  self:NextThink(CurTime())
  return true
end

function ENT:OnRemove()
  local rider = self:GetRider()

  if (IsValid(rider) and rider:InVehicle()) then
    rider:ExitVehicle()
  end

  local passenger = self:GetPassenger()

  if (IsValid(passenger)) then
    passenger:ExitVehicle()
  end
end
