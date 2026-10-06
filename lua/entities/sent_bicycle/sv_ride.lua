-- The ride itself, simulated every physics tick: tyres, pedals, grip and balance.

-- A bike leaning further than this has no tyre contact at all.
local ON_SIDE_LEAN = 70

-- Caps on the tyre springs, so a bike landing hard or stuck in the ground isn't launched.
local MAX_SUSPENSION_GRAVITIES = 10
local MAX_COMPRESSION_FRACTION = 0.5

-- The handlebar recentres faster than it turns in.
local STEER_RECENTER_SCALE = 1.6

-- Pedalling power fades out over this last fraction of the top speed.
local PEDAL_FADE_FRACTION = 0.3
-- Holding the brake below this speed walks the bike backwards instead.
local REVERSE_BELOW_SPEED = 15
local REVERSE_RESPONSE = 6
local REVERSE_MAX_CORRECTION = 150

-- Pitches the nose up on a hop (deg/s), so the front wheel leaves the ground first.
local HOP_PITCH_SPEED = 35

-- With only the rear wheel down the bike can still partly change heading.
local REAR_ONLY_YAW_AUTHORITY = 0.4
-- Below this speed the heading follows the handlebar directly, instead of waiting for the lean.
local LEAN_LIMITED_TURN_MIN_SPEED = 30
local MAX_SUPPORTING_LEAN = 60

local WHEELIE_MIN_SPEED = 40
-- A stoppie needs this much forward speed, it drops back onto both wheels once slower.
local STOPPIE_MIN_SPEED = 40
-- How firmly a wheelie or stoppie holds its pitch.
local PITCH_HOLD_GAIN = 5
local PITCH_HOLD_MAX_SPEED = 90
local PITCH_HOLD_RESPONSE = 10

-- Keys whose double-taps tricks can read, and how quickly the second press must follow the first (s).
local DOUBLE_TAP_KEYS = { [IN_FORWARD] = true, [IN_BACK] = true, [IN_MOVELEFT] = true, [IN_MOVERIGHT] = true }
local DOUBLE_TAP_WINDOW = 0.3

-- In the air the nose eases along the bike's path, so it lands on its wheels instead of tumbling over: following this
-- fraction of the path's slope, up to the max (deg), at the gain (1/s) and max pitch speed (deg/s).
local AIR_PITCH_FOLLOW = 0.5
local AIR_PITCH_MAX = 25
local AIR_PITCH_GAIN = 4
local AIR_PITCH_MAX_SPEED = 120
local AIR_PITCH_RESPONSE = 6
-- Off a steeper slope, such as a quarter pipe or spine, the nose follows the path further, up to the whole way and as
-- steep as the slope it left, and faster, so it comes back down along the ramp.
local AIR_PITCH_MAX_SPEED_STEEP = 240
local STEEPEST_SLOPE = 90

-- How quickly the bike's spin follows the rider's air controls (1/s).
local AIR_CONTROL_RESPONSE = 10
-- Going up a slope at least this steep (deg) into the air is a vert air: the bike can't drift away from the ramp, only
-- over its top, so it comes back down onto the ramp instead of onto the flat in front of it.
local VERT_AIR_MIN_SLOPE = 60
-- A spine transfer is steered as if it lands at least this soon (s), so pressing late doesn't throw the bike across.
local MIN_TRANSFER_TIME = 0.1
-- How fast a spine transfer may tip the nose over (deg/s).
local MAX_TRANSFER_PITCH_SPEED = 720

-- The bike's path turns with the ground by at most this much per tick (deg), larger jumps aren't the same surface.
local MAX_GROUND_FOLLOW_ANGLE = 45
local MIN_GROUND_FOLLOW_COS = math.cos(math.rad(MAX_GROUND_FOLLOW_ANGLE))
-- Tyres touching ground sloped this differently (deg) are on uneven ground, such as the foot of a ramp.
local UNEVEN_GROUND_ANGLE = 5
local UNEVEN_GROUND_COS = math.cos(math.rad(UNEVEN_GROUND_ANGLE))

-- Touchdowns are looked for along the bike's path, for ground it falls into at least this steeply (cosine of the angle
-- from its normal). Shallower, the bike hardly moves into the ground.
local MIN_TOUCHDOWN_APPROACH_COS = 0.3
-- Steeper surfaces (deg from the bike's up) are walls, which the tyres don't land on.
local MAX_TOUCHDOWN_GROUND_ANGLE = 60
local MIN_TOUCHDOWN_GROUND_UP = math.cos(math.rad(MAX_TOUCHDOWN_GROUND_ANGLE))

-- While a tyre is landing, pitch spin is damped (1/s), so one wheel landing hard doesn't kick that end up and slam
-- the other one down, which repeated hops would build into a flip.
local LANDING_PITCH_DAMPING = 12

-- In the air gravity won't let a bike stay slower than this (u/s) for long, so a ridden bike with no tyre down that
-- does is lying on its frame, such as on its side after a bad landing. It's thrown off once that's lasted this many
-- times as long as falling takes to pass through that speed.
local RESTING_OFF_WHEELS_SPEED = 50
local RESTING_OFF_WHEELS_FALL_TIMES = 3

-- The cranks never visibly turn slower than this while pedalling, even when setting off.
local MIN_PEDALLING_CADENCE = 40
local CADENCE_CHANGE_RATE = 300

-- The highest Entity:WaterLevel, for a bike completely under water.
local WATER_LEVEL_SUBMERGED = 3

-- Braking skids from this speed and is at its loudest from the full speed (u/s).
local BRAKE_SKID_MIN_SPEED = 60
local BRAKE_SKID_FULL_SPEED = 400
-- Sliding sideways skids from this side speed and is at its loudest from the full side speed (u/s).
local SLIDE_SKID_MIN_SPEED = 40
local SLIDE_SKID_FULL_SPEED = 250
-- The skid is networked in steps of this size, so it doesn't send a new value every tick.
local SKID_NETWORK_STEP = 0.05

local function getGravity()
  local gravity = physenv.GetGravity():Length()

  return gravity > 1 and gravity or 600
end

--- How far to blend towards a target this tick, independent of the tick rate.
local function getBlendFraction(rate, deltaTime)
  return 1 - math.exp(-rate * deltaTime)
end

local function projectOntoPlane(direction, normal)
  local projected = direction - normal * direction:Dot(normal)
  projected:Normalize()

  return projected
end

--- The wheel traces go straight through water, so without this a bike would ride along the bottom as if it were dry.
--- @return boolean
function ENT:IsTooDeepToRide()
  local maxWaterLevel = bicycle.getTuning("water_level")

  return maxWaterLevel > 0 and self:WaterLevel() >= maxWaterLevel
end

--- Called for each key the rider presses, as their command is run. `CurTime` is then the rider's own time, so the
--- double-tap window isn't stretched or squeezed by lag. A triple tap counts once, as the second press is used up.
--- @param key number IN_ key
function ENT:OnRiderKeyPress(key)
  if (not DOUBLE_TAP_KEYS[key]) then
    return
  end

  local now = CurTime()
  local pressedAt = self.tapPressedAt[key]

  if (pressedAt and now - pressedAt <= DOUBLE_TAP_WINDOW) then
    self.pendingDoubleTaps[key] = true
    self.tapPressedAt[key] = nil
  else
    self.tapPressedAt[key] = now
  end
end

--- @return table<number, boolean> # The DOUBLE_TAP_KEYS double-tapped since the last call
function ENT:ReadDoubleTaps()
  local doubleTaps = self.pendingDoubleTaps

  self.pendingDoubleTaps = {}

  return doubleTaps
end

--- Parked bikes hold their brakes. The "BicycleReadInput" hook can add or change fields, which tricks then read.
--- @param rider Player?
--- @return table
function ENT:ReadRiderInput(rider)
  if (not IsValid(rider)) then
    self.wasJumpHeld = false
    self.wasBellHeld = false
    self.tapPressedAt = {}
    self.pendingDoubleTaps = {}

    return {
      isPedalHeld = false,
      isBrakeHeld = true,
      steerDirection = 0,
      isSprintHeld = false,
      isHopPressed = false,
      isWheelieHeld = false,
      isLeanForwardHeld = false,
      isTrickHeld = false,
      isBellPressed = false,
      doubleTaps = {},
    }
  end

  local isJumpHeld = rider:KeyDown(IN_JUMP)
  local isHopPressed = isJumpHeld and not self.wasJumpHeld
  self.wasJumpHeld = isJumpHeld

  local isBellHeld = rider:KeyDown(IN_RELOAD)
  local isBellPressed = isBellHeld and not self.wasBellHeld
  self.wasBellHeld = isBellHeld

  local input = {
    isPedalHeld = rider:KeyDown(IN_FORWARD),
    isBrakeHeld = rider:KeyDown(IN_BACK),
    steerDirection = (rider:KeyDown(IN_MOVERIGHT) and 1 or 0) - (rider:KeyDown(IN_MOVELEFT) and 1 or 0),
    isSprintHeld = rider:KeyDown(IN_SPEED),
    isHopPressed = isHopPressed,
    isWheelieHeld = rider:KeyDown(IN_ATTACK2),
    isLeanForwardHeld = rider:KeyDown(IN_ATTACK),
    isTrickHeld = rider:KeyDown(IN_DUCK),
    isBellPressed = isBellPressed,
    -- IN_ keys double-tapped this tick.
    doubleTaps = self:ReadDoubleTaps(),
  }

  hook.Run("BicycleReadInput", rider, self, input)

  return input
end

--- Everything the ride needs to know about the bike this tick, before any forces are applied.
--- @return table
function ENT:MeasureRide(physics, rider)
  local angles = physics:GetAngles()
  local forward, right = angles:Forward(), angles:Right()
  local lean = -bicycle.getElevation(right)
  local isRidden = IsValid(rider)
  local isCrashed = self:GetCrashed()
  local isOnSide = math.abs(lean) > ON_SIDE_LEAN
  local canParkUpright = bicycle.getTuningBool("park_upright")
      and math.abs(lean) < bicycle.getTuning("park_upright_lean")

  return {
    position = physics:GetPos(),
    angles = angles,
    forward = forward,
    right = right,
    -- Degrees, positive is leaning right and nose up
    lean = lean,
    pitch = bicycle.getElevation(forward),
    velocity = physics:GetVelocity(),
    -- World space, deg/s
    angularVelocity = physics:LocalToWorldVector(physics:GetAngleVelocity()),
    mass = physics:GetMass(),
    massCenter = physics:GetMassCenter(),
    massCenterPosition = physics:LocalToWorld(physics:GetMassCenter()),
    gravity = getGravity(),
    gravityVector = physenv.GetGravity(),
    -- How far the bike is under water, 0-1
    waterFraction = self:WaterLevel() / WATER_LEVEL_SUBMERGED,
    isRidden = isRidden,
    isCrashed = isCrashed,
    isOnSide = isOnSide,
    -- A rider turning the bike in the air may lie it on its side, such as along a quarter pipe halfway round.
    isControlled = not isCrashed and not self.isPhysgunHeld
        and (not isOnSide or (isRidden and self.isAirTurning))
        and (isRidden or canParkUpright),
  }
end

--- While balanced, tyre support pushes on the line through the centre of mass (pitch only, no roll torque), so the
--- lean controller never fights gravity. During a wheelie or stoppie it pushes through the centre of mass itself (no
--- pitch torque either), otherwise the one tyre left down would carry the weight beyond it and slam the other end down.
--- Uncontrolled, it pushes at the contact point and the bike falls naturally.
--- @param isWall boolean Whether `contact` is a wall the tyre presses against, rather than ground
function ENT:ApplyTyreSpring(physics, ride, wheel, contact, deltaTime, isWall)
  local normal = contact.normal
  local compression = math.min(contact.compression, self.WheelRadius * MAX_COMPRESSION_FRACTION)
  local compressionSpeed = -physics:GetVelocityAtPoint(contact.hubPosition):Dot(normal)
  local acceleration = bicycle.getTuning("spring") * compression + bicycle.getTuning("damper") * compressionSpeed

  -- A tyre can only push the bike away from the ground, never pull it down.
  if (acceleration <= 0) then
    return
  end

  acceleration = math.min(acceleration, ride.gravity * MAX_SUSPENSION_GRAVITIES)

  local forcePosition = contact.contactPosition
  local force = normal * (acceleration * ride.mass * deltaTime)

  -- Arcade-feel: ground never holds the bike back along its heading, such as at the foot of a ramp.
  if (ride.isControlled and not isWall) then
    force:Sub(ride.forwardAlongGround * force:Dot(ride.forwardAlongGround))
  end

  if (ride.isWheelieing or ride.isStoppieing) then
    forcePosition = physics:LocalToWorld(ride.massCenter)
  elseif (ride.isControlled) then
    forcePosition = physics:LocalToWorld(Vector(wheel.position.x, ride.massCenter.y, ride.massCenter.z))

    -- Only the part along the shared ground normal pushes there. Where the tyres touch differently
    -- sloped ground, such as either side of a crest, the rest would push the ends of the bike different
    -- ways and slowly turn it, so it pushes through the centre of mass instead.
    local support = ride.groundNormal * force:Dot(ride.groundNormal)

    physics:ApplyForceCenter(force - support)
    force = support
  end

  physics:ApplyForceOffset(force, forcePosition)
end

--- Springs each grounded tyre and adds what the tyres touch to `ride`: the ground normal, which wheels are down and
--- the bike's heading and speed along the ground. All tyres are traced before any is sprung, since the springs need
--- the ground normal they share.
function ENT:ApplyTyreSuspension(physics, ride, deltaTime)
  local groundNormalSum = Vector(0, 0, 0)
  local groundedContacts = {}
  local wallContacts = {}

  ride.groundedCount = 0
  ride.isFrontGrounded = false
  ride.isRearGrounded = false

  if (not ride.isOnSide) then
    local filter = self:GetWheelTraceFilter()

    for index, wheel in ipairs(self.Wheels) do
      local contact = self:TraceWheel(index, filter, ride.position, ride.angles)

      if (contact.isGrounded) then
        ride.groundedCount = ride.groundedCount + 1

        if (wheel.isFront) then
          ride.isFrontGrounded = true
        else
          ride.isRearGrounded = true
        end

        -- On a step's edge the bike rides onto the step's top, it isn't steered up the edge like a ramp, which would
        -- launch it off a curb.
        groundNormalSum:Add(contact.groundNormal)
        groundedContacts[index] = contact
      end

      wallContacts[index] = contact.wall
    end
  end

  ride.groundNormal = ride.groundedCount > 0 and groundNormalSum:GetNormalized() or vector_up
  ride.groundContactPosition = nil

  if (ride.groundedCount > 0) then
    local contactPositionSum = Vector(0, 0, 0)

    for _, contact in pairs(groundedContacts) do
      contactPositionSum:Add(contact.contactPosition)
    end

    ride.groundContactPosition = contactPositionSum / ride.groundedCount
  end
  ride.forwardAlongGround = projectOntoPlane(ride.forward, ride.groundNormal)
  ride.sideAlongGround = projectOntoPlane(ride.right, ride.groundNormal)
  ride.isGroundUneven = false

  for _, contact in pairs(groundedContacts) do
    if (contact.normal:Dot(ride.groundNormal) < UNEVEN_GROUND_COS) then
      ride.isGroundUneven = true
    end
  end

  self:FollowGround(physics, ride)
  self:CushionTouchdown(physics, ride, deltaTime)

  for index, contact in pairs(groundedContacts) do
    self:ApplyTyreSpring(physics, ride, self.Wheels[index], contact, deltaTime, false)
  end

  for index, contact in pairs(wallContacts) do
    self:ApplyTyreSpring(physics, ride, self.Wheels[index], contact, deltaTime, true)
  end

  ride.groundedFraction = ride.groundedCount / #self.Wheels
  ride.speed = ride.velocity:Dot(ride.forwardAlongGround)
  ride.absoluteSpeed = math.abs(ride.speed)
end

--- Arcade-feel: while grounded, the bike's path turns as the ground does, so it rolls into a ramp or quarter pipe instead
--- of losing its speed against it. Only into the ground, so the bike can still fly off a crest.
function ENT:FollowGround(physics, ride)
  local previousNormal = self.lastGroundNormal
  local normal = ride.groundNormal

  self.lastGroundNormal = (ride.isControlled and ride.groundedCount > 0) and normal or nil

  if (not previousNormal or not self.lastGroundNormal or ride.velocity:Dot(normal) >= 0) then
    return
  end

  local axis = previousNormal:Cross(normal)
  local sine = axis:Length()
  local cosine = previousNormal:Dot(normal)

  if (sine < 1e-4 or cosine < MIN_GROUND_FOLLOW_COS) then
    return
  end

  axis:Div(sine)

  -- Rodrigues' rotation by the same turn as the ground's.
  local velocity = ride.velocity
  local turned = velocity * cosine + axis:Cross(velocity) * sine + axis * (axis:Dot(velocity) * (1 - cosine))

  physics:AddVelocity(turned - velocity)
  ride.velocity = turned
end

--- @return Vector?, number? # The normal of the ground `wheel` lands on along `direction`, and how far its tyre is from
--- touching it. Nil when there is no ground within `reach`.
function ENT:TraceTouchdown(ride, wheel, filter, direction, reach)
  local hubPosition = LocalToWorld(wheel.position, angle_zero, ride.position, ride.angles)
  local trace = util.TraceLine({
    start = hubPosition,
    endpos = hubPosition + direction * reach,
    filter = filter,
    mask = MASK_SOLID,
  })

  if (not trace.Hit or trace.StartSolid or trace.HitNormal:Dot(ride.angles:Up()) < MIN_TOUCHDOWN_GROUND_UP) then
    return nil
  end

  return trace.HitNormal, (hubPosition - trace.HitPos):Dot(trace.HitNormal) - self.WheelRadius
end

function ENT:CushionTouchdown(physics, ride, deltaTime)
  local speed = ride.velocity:Length()

  if (ride.groundedCount > 0 or not ride.isRidden or not ride.isControlled or speed < 1) then
    return
  end

  local direction = ride.velocity / speed
  local reach = (self.WheelRadius + speed * deltaTime) / MIN_TOUCHDOWN_APPROACH_COS
  local filter = self:GetWheelTraceFilter()
  -- Damping alone stops a tyre within speed / damping, so this is the fastest it stops within its travel.
  local maxTouchdownSpeed = bicycle.getTuning("damper") * self.WheelRadius * (1 - self.WheelHullScale)
  local cushionNormal, cushionSpeed = nil, 0

  for _, wheel in ipairs(self.Wheels) do
    local normal, gap = self:TraceTouchdown(ride, wheel, filter, direction, reach)

    if (normal) then
      local approachSpeed = -ride.velocity:Dot(normal)
      -- Only slowed once it would otherwise reach the ground this tick, so it doesn't stop short in mid-air: first to
      -- end the tick just short of it, then to touch down next tick.
      local wantedSpeed = math.max(maxTouchdownSpeed, (gap - maxTouchdownSpeed * deltaTime) / deltaTime)

      if (approachSpeed - wantedSpeed > cushionSpeed and not self:IsCrashImpact(approachSpeed, normal)) then
        cushionNormal, cushionSpeed = normal, approachSpeed - wantedSpeed
      end
    end
  end

  if (cushionNormal) then
    local speedChange = cushionNormal * cushionSpeed

    physics:AddVelocity(speedChange)
    ride.velocity = ride.velocity + speedChange
  end
end

--- The faster the bike goes, the fewer degrees of handlebar a full steer gives: it narrows from bicycle_steer_max to
--- bicycle_steer_max_fast between bicycle_steer_slow_speed and bicycle_steer_fast_speed.
--- @return number # Handlebar angle in degrees, positive is right
function ENT:UpdateSteering(steerDirection, absoluteSpeed, deltaTime)
  local slowSpeed = bicycle.getTuning("steer_slow_speed")
  -- The speeds can be set equal or the wrong way around.
  local narrowingRange = math.max(bicycle.getTuning("steer_fast_speed") - slowSpeed, 1)
  local narrowingFraction = math.Clamp((absoluteSpeed - slowSpeed) / narrowingRange, 0, 1)
  local maxSteerAngle = Lerp(narrowingFraction, bicycle.getTuning("steer_max"), bicycle.getTuning("steer_max_fast"))
  local steerRate = bicycle.getTuning("steer_rate")

  if (steerDirection == 0) then
    steerRate = steerRate * STEER_RECENTER_SCALE
  end

  self.steerFraction = math.Approach(self.steerFraction, steerDirection, steerRate * deltaTime)

  return self.steerFraction * maxSteerAngle
end

--- Like static friction: brings `speed` to a standstill this tick and holds it there against `slopeAcceleration` (the
--- gravity pulling along that direction), but never pushes harder than `maxAcceleration` or past a standstill.
--- @return number # Acceleration to apply (u/s^2)
local function getHoldingAcceleration(speed, slopeAcceleration, maxAcceleration, deltaTime)
  return math.Clamp(-speed / deltaTime - slopeAcceleration, -maxAcceleration, maxAcceleration)
end

function ENT:ApplyPedalsAndBrakes(physics, ride, input, isPedalling, deltaTime)
  local speed = ride.speed
  -- Without holding against this, gravity would creep the bike down even a slight slope with the brakes on.
  local slopeAcceleration = ride.gravityVector:Dot(ride.forwardAlongGround)
  local acceleration = 0

  if (isPedalling) then
    local topSpeed = input.isSprintHeld and bicycle.getTuning("sprint_speed") or bicycle.getTuning("top_speed")
    local pedalAcceleration = bicycle.getTuning("pedal_accel") *
        (input.isSprintHeld and bicycle.getTuning("sprint_accel") or 1)

    acceleration = acceleration
        + pedalAcceleration * math.Clamp((topSpeed - speed) / (topSpeed * PEDAL_FADE_FRACTION), 0, 1)
  end

  if (input.isBrakeHeld) then
    local brakeAcceleration = bicycle.getTuning("brake_accel")

    if (ride.isRidden and speed < REVERSE_BELOW_SPEED) then
      local reverseCorrection = (-bicycle.getTuning("reverse_speed") - speed) * REVERSE_RESPONSE

      acceleration = acceleration + math.Clamp(reverseCorrection, -brakeAcceleration, REVERSE_MAX_CORRECTION)
    else
      acceleration = acceleration + getHoldingAcceleration(
        speed,
        slopeAcceleration,
        brakeAcceleration * ride.groundedFraction,
        deltaTime
      )
    end
  elseif (not isPedalling) then
    -- Rolling resistance holds the bike on slopes too gentle to overcome it, steeper ones roll it down.
    acceleration = acceleration + getHoldingAcceleration(
      speed,
      slopeAcceleration,
      bicycle.getTuning("rolling") * ride.groundedFraction + bicycle.getTuning("drag") * speed * speed,
      deltaTime
    )
  end

  -- Wading slows the bike whatever the rider does. Taking a fraction of the speed never turns the bike around.
  local newSpeed = speed + acceleration * deltaTime
  local waterSlowdown = newSpeed
      * getBlendFraction(bicycle.getTuning("water_drag") * ride.waterFraction, deltaTime)

  physics:AddVelocity(ride.forwardAlongGround * (newSpeed - waterSlowdown - speed))
end

function ENT:TryBunnyHop(physics, ride)
  if (CurTime() <= self.nextHopAt) then
    return
  end

  self.nextHopAt = CurTime() + bicycle.getTuning("hop_cooldown")

  physics:AddVelocity(ride.groundNormal * bicycle.getTuning("hop"))
  physics:AddAngleVelocity(physics:WorldToLocalVector(ride.right * HOP_PITCH_SPEED))

  self.hasPendingHopSound = true
end

--- Removes sideways slip and holds the bike against gravity pulling it sideways down a slope, but never harder than
--- tyre friction allows, so the bike can still slide.
function ENT:ApplyTyreGrip(physics, ride, deltaTime)
  local sideSpeed = ride.velocity:Dot(ride.sideAlongGround)
  local slopeSpeedChange = ride.gravityVector:Dot(ride.sideAlongGround) * deltaTime
  local maxSpeedChange = bicycle.getTuning("mu") * ride.gravity * ride.groundedFraction * deltaTime
  local speedChange = math.Clamp(
    -sideSpeed * getBlendFraction(bicycle.getTuning("grip"), deltaTime) - slopeSpeedChange,
    -maxSpeedChange,
    maxSpeedChange
  )

  physics:AddVelocity(ride.sideAlongGround * speedChange)

  ride.sideSpeed = sideSpeed
end

--- @return number # How hard the tyres skid, 0-1
function ENT:GetSkidAmount(ride, input)
  if (ride.groundedCount == 0 or not ride.isRidden) then
    return 0
  end

  local slideSkid = math.Clamp(
    (math.abs(ride.sideSpeed) - SLIDE_SKID_MIN_SPEED) / (SLIDE_SKID_FULL_SPEED - SLIDE_SKID_MIN_SPEED),
    0,
    1
  )
  local brakeSkid = 0

  -- Below REVERSE_BELOW_SPEED the brake walks the bike backwards instead.
  if (input.isBrakeHeld and ride.speed >= REVERSE_BELOW_SPEED) then
    brakeSkid = math.Clamp(
      (ride.absoluteSpeed - BRAKE_SKID_MIN_SPEED) / (BRAKE_SKID_FULL_SPEED - BRAKE_SKID_MIN_SPEED),
      0,
      1
    )
  end

  return math.max(slideSkid, brakeSkid)
end

--- Only corners as hard as the current lean supports (plus bicycle_lean_slack), so the bike leans in first and then
--- carves.
--- @return Vector # Angular velocity correction in world space, deg/s
function ENT:GetHeadingCorrection(ride, steeredYawRate, lateralAcceleration, deltaTime)
  local authority = ride.isFrontGrounded and 1 or (ride.isRearGrounded and REAR_ONLY_YAW_AUTHORITY or 0)

  if (authority == 0) then
    return Vector(0, 0, 0)
  end

  local yawRate = steeredYawRate

  if (ride.absoluteSpeed > LEAN_LIMITED_TURN_MIN_SPEED) then
    local turnDirection = lateralAcceleration >= 0 and 1 or -1
    local leanIntoTurn = math.Clamp(ride.lean * turnDirection, 0, MAX_SUPPORTING_LEAN)
    local supportedAcceleration = ride.gravity * math.tan(math.rad(leanIntoTurn)) + bicycle.getTuning("lean_slack")

    yawRate = turnDirection * math.min(math.abs(lateralAcceleration), supportedAcceleration) / ride.speed
  end

  -- Around the ground normal, where positive turns left.
  local wantedYawSpeed = -math.deg(yawRate)
  local currentYawSpeed = ride.angularVelocity:Dot(ride.groundNormal)
  local blend = getBlendFraction(bicycle.getTuning("yaw_response"), deltaTime)

  return ride.groundNormal * ((wantedYawSpeed - currentYawSpeed) * blend * authority)
end

--- A P controller on the lean angle picks a roll speed, which the bike's actual roll is then blended towards.
--- @return Vector # Angular velocity correction in world space, deg/s
function ENT:GetLeanCorrection(ride, targetLean, deltaTime)
  local authority = ride.groundedCount > 0 and 1 or bicycle.getTuning("air_control")
  local maxRollSpeed = bicycle.getTuning("lean_rate")
  local wantedRollSpeed = math.Clamp((targetLean - ride.lean) * bicycle.getTuning("lean_p"), -maxRollSpeed, maxRollSpeed)
  local currentRollSpeed = ride.angularVelocity:Dot(ride.forward)
  local blend = getBlendFraction(bicycle.getTuning("lean_response"), deltaTime)

  return ride.forward * ((wantedRollSpeed - currentRollSpeed) * blend * authority)
end

--- Holds the nose at `targetPitch` for a wheelie or stoppie.
--- @param targetPitch number Degrees, positive is nose up
--- @return Vector # Angular velocity correction in world space, deg/s
function ENT:GetPitchHoldCorrection(ride, targetPitch, deltaTime)
  local wantedPitchSpeed = math.Clamp(
    (targetPitch - ride.pitch) * PITCH_HOLD_GAIN,
    -PITCH_HOLD_MAX_SPEED,
    PITCH_HOLD_MAX_SPEED
  )
  -- Positive pitches the nose up.
  local currentPitchSpeed = ride.angularVelocity:Dot(ride.right)

  return ride.right * ((wantedPitchSpeed - currentPitchSpeed) * getBlendFraction(PITCH_HOLD_RESPONSE, deltaTime))
end

--- Only while the bike moves into the ground, so the pitch a hop kicks in on take-off is left alone. Not on uneven
--- ground either, where the bike must pitch to follow it.
--- @return Vector # Angular velocity correction in world space, deg/s
function ENT:GetLandingPitchCorrection(ride, deltaTime)
  if (ride.groundedCount == 0 or ride.isGroundUneven or ride.velocity:Dot(ride.groundNormal) >= 0) then
    return Vector(0, 0, 0)
  end

  local currentPitchSpeed = ride.angularVelocity:Dot(ride.right)

  return ride.right * (-currentPitchSpeed * getBlendFraction(LANDING_PITCH_DAMPING, deltaTime))
end

--- Unlike `ride.pitch`, keeps counting past 90 once the nose tips over backwards, such as straight up a quarter pipe,
--- where the pitch would otherwise read as short of vertical and be pushed further over.
--- @return number # Degrees, positive is nose up
local function getUnwrappedPitch(ride)
  local heading = vector_up:Cross(ride.right)
  local headingLength = heading:Length()

  -- On its side the bike has no pitch to speak of.
  if (headingLength < 1e-2) then
    return ride.pitch
  end

  return math.deg(math.atan2(ride.forward.z, ride.forward:Dot(heading) / headingLength))
end

--- Not realistic, but riding off jumps without tumbling over is more fun. Scaled by bicycle_air_pitch_control.
--- @return Vector # Angular velocity correction in world space, deg/s
function ENT:GetAirPitchCorrection(ride, deltaTime)
  local pathPitch = bicycle.getElevation(ride.velocity:GetNormalized())

  -- Rolling backwards, the rear leads down the path.
  if (ride.velocity:Dot(ride.forward) < 0) then
    pathPitch = -pathPitch
  end

  local isAdvanced = bicycle.getTuningBool("advanced_air_control")
  local maxPitch = isAdvanced and math.max(AIR_PITCH_MAX, self.takeoffSlope) or AIR_PITCH_MAX
  local steepness = (maxPitch - AIR_PITCH_MAX) / (STEEPEST_SLOPE - AIR_PITCH_MAX)
  local maxPitchSpeed = Lerp(steepness, AIR_PITCH_MAX_SPEED, AIR_PITCH_MAX_SPEED_STEEP)
  local targetPitch = math.Clamp(pathPitch * Lerp(steepness, AIR_PITCH_FOLLOW, 1), -maxPitch, maxPitch)
  local pitchError = math.NormalizeAngle(targetPitch - (isAdvanced and getUnwrappedPitch(ride) or ride.pitch))
  local wantedPitchSpeed = math.Clamp(pitchError * AIR_PITCH_GAIN, -maxPitchSpeed, maxPitchSpeed)
  local currentPitchSpeed = ride.angularVelocity:Dot(ride.right)
  local blend = getBlendFraction(AIR_PITCH_RESPONSE, deltaTime) * bicycle.getTuning("air_pitch_control")

  return ride.right * ((wantedPitchSpeed - currentPitchSpeed) * blend)
end

--- Keys already held when the bike leaves the ground, such as pedalling or carving off a jump, keep riding as before
--- and only control the bike in the air once pressed again. Adds `airPitchDirection` to `ride`: 1 pitches the nose up,
--- -1 down.
function ENT:ReadAirControls(ride, input)
  if (not bicycle.getTuningBool("advanced_air_control")) then
    self.vertAir = nil
    self.isAirSpinControlled = false
    self.isAirTurning = false
    ride.airPitchDirection = 0

    return
  end

  local heldSinceTakeoff = self.airKeysHeldSinceTakeoff

  if (ride.groundedCount > 0 or not ride.isRidden) then
    heldSinceTakeoff.steerDirection = input.steerDirection
    heldSinceTakeoff.isPedalHeld = input.isPedalHeld
    heldSinceTakeoff.isBrakeHeld = input.isBrakeHeld
    self.takeoffSlope = math.abs(bicycle.getElevation(ride.forwardAlongGround))
    self.vertAir = self:MeasureVertAirTakeoff(ride)
    self.isAirSpinControlled = false
    self.isAirTurning = false
    ride.airPitchDirection = 0

    return
  end

  if (heldSinceTakeoff.steerDirection ~= input.steerDirection) then
    heldSinceTakeoff.steerDirection = 0
  end

  heldSinceTakeoff.isPedalHeld = heldSinceTakeoff.isPedalHeld and input.isPedalHeld
  heldSinceTakeoff.isBrakeHeld = heldSinceTakeoff.isBrakeHeld and input.isBrakeHeld

  -- Once the rider steers in the air, the bike only spins while they do, for the rest of the jump.
  local isFreshSteer = input.steerDirection ~= 0 and heldSinceTakeoff.steerDirection == 0

  if (isFreshSteer and bicycle.getTuning("air_turn_speed") > 0) then
    self.isAirSpinControlled = true
  end

  self.isAirTurning = self.isAirSpinControlled and self.steerFraction ~= 0

  -- Ctrl and right mouse turn W and S into pose tricks instead.
  if (input.isTrickHeld or input.isWheelieHeld or bicycle.getTuning("air_pitch_speed") <= 0) then
    ride.airPitchDirection = 0
  else
    ride.airPitchDirection = ((input.isBrakeHeld and not heldSinceTakeoff.isBrakeHeld) and 1 or 0)
        - ((input.isPedalHeld and not heldSinceTakeoff.isPedalHeld) and 1 or 0)
  end
end

--- Called every tick on the ground, so the last one holds the take-off.
--- @return table? # `{ away, rampPoint, takeoffOffset, takeoffHeight, isTransferring, timeLeft? }`, nil unless the bike
--- goes up steep enough ground for a vert air. `away` is horizontal, out of the ramp, and `takeoffOffset` how far the
--- centre of mass was out from the ramp at `rampPoint`.
function ENT:MeasureVertAirTakeoff(ride)
  if (self.takeoffSlope < VERT_AIR_MIN_SLOPE or ride.velocity.z <= 0 or not ride.groundContactPosition) then
    return nil
  end

  local away = Vector(ride.groundNormal.x, ride.groundNormal.y, 0)

  if (away:LengthSqr() < 1e-2) then
    return nil
  end

  away:Normalize()

  return {
    away = away,
    rampPoint = ride.groundContactPosition,
    takeoffOffset = (ride.massCenterPosition - ride.groundContactPosition):Dot(away),
    takeoffHeight = ride.massCenterPosition.z,
    isTransferring = false,
  }
end

--- @return number # Seconds until the centre of mass falls back to `height`, at least MIN_TRANSFER_TIME
local function getTimeToFallTo(ride, height)
  local verticalSpeed = ride.velocity.z
  local rise = ride.massCenterPosition.z - height
  local fallTime = (verticalSpeed + math.sqrt(math.max(verticalSpeed * verticalSpeed + 2 * ride.gravity * rise, 0)))
      / ride.gravity

  return math.max(fallTime, MIN_TRANSFER_TIME)
end

--- Whether the bike can move by `crossing` without passing through anything, such as once it's above a spine.
function ENT:IsClearToCross(ride, crossing)
  local filter = self:GetWheelTraceFilter()
  local starts = { ride.massCenterPosition }

  for _, wheel in ipairs(self.Wheels) do
    starts[#starts + 1] = LocalToWorld(wheel.position, angle_zero, ride.position, ride.angles)
  end

  for _, start in ipairs(starts) do
    local trace = util.TraceLine({ start = start, endpos = start + crossing, filter = filter, mask = MASK_SOLID })

    if (trace.Hit) then
      return false
    end
  end

  return true
end

--- Arcade-feel: in a vert air, such as straight up a quarter pipe, the tyres springing back off the ramp would carry
--- the bike away from it to land on the flat, so its horizontal speed away from the ramp is taken. Pressing W with
--- nothing over the top transfers: as if there were a quarter pipe right behind this one, such as on a spine, the bike
--- is steered to land as far behind the ramp as it took off in front of it, at the same height.
function ENT:UpdateVertAir(physics, ride)
  local vertAir = self.vertAir

  if (not vertAir or ride.groundedCount > 0 or not ride.isRidden or ride.isCrashed) then
    return
  end

  local away = vertAir.away
  local offset = (ride.massCenterPosition - vertAir.rampPoint):Dot(away)

  if (not vertAir.isTransferring and ride.airPitchDirection < 0
        and self:IsClearToCross(ride, away * -(offset + vertAir.takeoffOffset))) then
    vertAir.isTransferring = true
  end

  local awaySpeed = ride.velocity:Dot(away)
  local wantedAwaySpeed = math.min(awaySpeed, 0)

  if (vertAir.isTransferring) then
    vertAir.timeLeft = getTimeToFallTo(ride, vertAir.takeoffHeight)
    wantedAwaySpeed = (-vertAir.takeoffOffset - offset) / vertAir.timeLeft
  end

  local speedChange = away * (wantedAwaySpeed - awaySpeed)

  physics:AddVelocity(speedChange)
  ride.velocity = ride.velocity + speedChange
end

--- A / D spin the bike around its own up, which up a quarter pipe turns it round to come back down nose first, and
--- W / S pitch its nose, such as over a spine. Without W / S the nose follows the bike's path.
--- @return Vector # Angular velocity correction in world space, deg/s
function ENT:GetAirControlCorrection(ride, deltaTime)
  local correction = Vector(0, 0, 0)
  local blend = getBlendFraction(AIR_CONTROL_RESPONSE, deltaTime)

  if (self.isAirSpinControlled) then
    local up = ride.angles:Up()
    -- Positive turns left.
    local wantedSpinSpeed = -self.steerFraction * bicycle.getTuning("air_turn_speed")

    correction:Add(up * ((wantedSpinSpeed - ride.angularVelocity:Dot(up)) * blend))
  end

  -- A flip turns the bike over itself. With advanced air control it hands the bike back once it stops turning, so the
  -- rider can still straighten it before landing.
  local isFlipInControl = self.isRotatingBike

  if (bicycle.getTuningBool("advanced_air_control")) then
    isFlipInControl = self.isSpinningBike
  end

  if (isFlipInControl) then
    return correction
  end

  local vertAir = self.vertAir

  if (vertAir and vertAir.isTransferring) then
    -- Tips the nose over the top, to come down the other side as steeply as it went up by the time it lands there.
    local pitchError = -self.takeoffSlope - getUnwrappedPitch(ride)
    local wantedPitchSpeed = math.Clamp(
      pitchError / vertAir.timeLeft,
      -MAX_TRANSFER_PITCH_SPEED,
      MAX_TRANSFER_PITCH_SPEED
    )

    correction:Add(ride.right * ((wantedPitchSpeed - ride.angularVelocity:Dot(ride.right)) * blend))
  elseif (ride.airPitchDirection ~= 0) then
    local wantedPitchSpeed = ride.airPitchDirection * bicycle.getTuning("air_pitch_speed")

    correction:Add(ride.right * ((wantedPitchSpeed - ride.angularVelocity:Dot(ride.right)) * blend))
  elseif (not self.isAirTurning) then
    -- Mid-turn the nose may point along the ramp, where pitching it would only spin the bike back.
    correction:Add(self:GetAirPitchCorrection(ride, deltaTime))
  end

  return correction
end

--- Keeps the bike balanced, leaning into the turn the handlebar asks for and heading where that lean allows.
--- @return number # The lean the bike aims for in degrees, positive is right
function ENT:ApplyBalance(physics, ride, input, steerAngle, deltaTime)
  local gravity = ride.gravity
  local maxLateralAcceleration = bicycle.getTuning("mu") * gravity
  -- Radians per second, positive is right.
  local steeredYawRate = ride.speed * math.tan(math.rad(steerAngle)) / self.Wheelbase
  local lateralAcceleration = math.Clamp(ride.speed * steeredYawRate, -maxLateralAcceleration, maxLateralAcceleration)
  local targetLean = 0

  if (ride.isRidden) then
    local maxLean = bicycle.getTuning("lean_max")

    -- The lean a real bike needs for this turn: tan(lean) = lateral acceleration / gravity.
    targetLean = math.Clamp(math.deg(math.atan(lateralAcceleration / gravity)), -maxLean, maxLean)
  end

  local correction = self:GetHeadingCorrection(ride, steeredYawRate, lateralAcceleration, deltaTime)

  -- Turning in the air leaves the lean to the rider, so the bike can lie along a quarter pipe halfway round.
  if (not self.isAirTurning) then
    correction:Add(self:GetLeanCorrection(ride, targetLean, deltaTime))
  end

  if (ride.isWheelieing and ride.isRearGrounded) then
    correction:Add(self:GetPitchHoldCorrection(ride, bicycle.getTuning("wheelie_angle"), deltaTime))
  elseif (ride.isStoppieing and ride.isFrontGrounded) then
    correction:Add(self:GetPitchHoldCorrection(ride, -bicycle.getTuning("stoppie_angle"), deltaTime))
  elseif (ride.groundedCount == 0) then
    correction:Add(self:GetAirControlCorrection(ride, deltaTime))
  else
    correction:Add(self:GetLandingPitchCorrection(ride, deltaTime))
  end

  physics:AddAngleVelocity(physics:WorldToLocalVector(correction))

  return targetLean
end

function ENT:UpdateNetworkedVisuals(absoluteSpeed, isPedalling, steerAngle, targetLean, deltaTime)
  local wheelRevolutionsPerMinute = absoluteSpeed / (2 * math.pi * self.WheelRadius) * 60
  -- Freewheeling leaves the cranks still.
  local wantedCadence = isPedalling
      and math.max(wheelRevolutionsPerMinute / self.GearRatio, MIN_PEDALLING_CADENCE)
      or 0

  self:SetCadence(math.Approach(self:GetCadence(), wantedCadence, CADENCE_CHANGE_RATE * deltaTime))
  self:SetSteer(steerAngle)
  self:SetTargetLean(targetLean)
end

--- Velocities are measured once into `ride` before any forces are applied, so every stage steers the bike from the
--- same starting state.
function ENT:PhysicsSimulate(physics, deltaTime)
  deltaTime = math.Clamp(deltaTime, 0.001, 0.05)

  local rider = self:GetRider()
  local input = self:ReadRiderInput(rider)
  local ride = self:MeasureRide(physics, rider)

  if (ride.isRidden and not ride.isCrashed and self:IsTooDeepToRide()) then
    self.hasPendingCrash = true
    self.isCrashingIntoWater = true
  end

  -- Decided before the tyres are sprung, since a wheelie or stoppie changes where they push.
  local forwardSpeed = ride.velocity:Dot(ride.forward)

  ride.isWheelieing = input.isWheelieHeld and ride.isControlled and math.abs(forwardSpeed) > WHEELIE_MIN_SPEED
  -- Braking while leaning forward lifts the rear wheel. Once it's up, letting go of the brake keeps the bike rolling on
  -- its front wheel for as long as the rider keeps leaning forward.
  ride.isStoppieing = input.isLeanForwardHeld and not ride.isWheelieing and ride.isControlled
      and forwardSpeed > STOPPIE_MIN_SPEED
      and (input.isBrakeHeld or self.isStoppieing)

  self:ApplyTyreSuspension(physics, ride, deltaTime)

  -- Crashing ejects the rider, which can't happen inside the physics step. Only on the ground, never in the air, and
  -- pitch is against the ground so steep ramps aren't crashes. A trick turning the bike over judges its own landing.
  local groundPitch = math.deg(math.asin(math.Clamp(ride.forward:Dot(ride.groundNormal), -1, 1)))

  if (ride.isRidden and not ride.isCrashed and not self.isPhysgunHeld and not self.isRotatingBike
        and ride.groundedCount > 0
        and (math.abs(ride.lean) > bicycle.getTuning("crash_lean") or math.abs(groundPitch) > bicycle.getTuning("crash_pitch"))) then
    self.hasPendingCrash = true
  end

  -- Catches what the lean and pitch check above can't, such as a bike propped up by its handlebar just short of the
  -- crash lean, or one that landed a flip on its side and so never touched down to judge it.
  if (ride.isRidden and not ride.isCrashed and not self.isPhysgunHeld and ride.groundedCount == 0
        and ride.velocity:Length() < RESTING_OFF_WHEELS_SPEED) then
    self.restingOffWheelsTime = self.restingOffWheelsTime + deltaTime

    local fallThroughTime = RESTING_OFF_WHEELS_SPEED * 2 / ride.gravity

    if (self.restingOffWheelsTime > fallThroughTime * RESTING_OFF_WHEELS_FALL_TIMES) then
      self.hasPendingCrash = true
    end
  else
    self.restingOffWheelsTime = 0
  end

  -- For the rider's pose.
  self.isWheelieing = ride.isWheelieing and ride.isRearGrounded
  -- Keeps the stoppie going next tick without the brake, until the front wheel leaves the ground.
  self.isStoppieing = ride.isStoppieing and ride.isFrontGrounded

  -- Steering spins a trick while its button is held, so the bike doesn't also land crossed up.
  local isSteeringTrick = self:UpdateTricks(physics, ride, input, rider, deltaTime)
  local steerAngle = self:UpdateSteering(isSteeringTrick and 0 or input.steerDirection, ride.absoluteSpeed, deltaTime)

  self:ReadAirControls(ride, input)
  self:UpdateVertAir(physics, ride)

  local isPedalling = input.isPedalHeld and ride.isRearGrounded

  if (input.isBellPressed) then
    self.hasPendingBell = true
  end

  if (ride.groundedCount > 0) then
    self:ApplyPedalsAndBrakes(physics, ride, input, isPedalling, deltaTime)

    if (input.isHopPressed) then
      self:TryBunnyHop(physics, ride)
    end

    self:ApplyTyreGrip(physics, ride, deltaTime)
  end

  local targetLean = 0

  if (ride.isControlled) then
    targetLean = self:ApplyBalance(physics, ride, input, steerAngle, deltaTime)
  end

  self:UpdateNetworkedVisuals(ride.absoluteSpeed, isPedalling, steerAngle, targetLean, deltaTime)
  self:SetSkid(math.Round(self:GetSkidAmount(ride, input) / SKID_NETWORK_STEP) * SKID_NETWORK_STEP)

  return vector_origin, vector_origin, SIM_NOTHING
end
