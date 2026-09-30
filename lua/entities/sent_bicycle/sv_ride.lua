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
local WHEELIE_GAIN = 5
local WHEELIE_MAX_PITCH_SPEED = 90
local WHEELIE_RESPONSE = 10

-- While a tyre is landing, pitch spin is damped (1/s), so one wheel landing hard doesn't kick that end up and slam
-- the other one down, which repeated hops would build into a flip.
local LANDING_PITCH_DAMPING = 12

-- The cranks never visibly turn slower than this while pedalling, even when setting off.
local MIN_PEDALLING_CADENCE = 40
local CADENCE_CHANGE_RATE = 300

local function getGravity()
  local gravity = physenv.GetGravity():Length()

  return gravity > 1 and gravity or 600
end

--- How far to blend towards a target this tick, independent of the tick rate.
local function getBlendFraction(rate, deltaTime)
  return 1 - math.exp(-rate * deltaTime)
end

local function getDirection(speed)
  return speed > 0 and 1 or -1
end

local function projectOntoPlane(direction, normal)
  local projected = direction - normal * direction:Dot(normal)
  projected:Normalize()

  return projected
end

--- Parked bikes hold their brakes.
--- @param rider Player?
--- @return table
function ENT:ReadRiderInput(rider)
  if (not IsValid(rider)) then
    self.wasJumpHeld = false

    return {
      isPedalHeld = false,
      isBrakeHeld = true,
      steerDirection = 0,
      isSprintHeld = false,
      isHopPressed = false,
      isWheelieHeld = false,
    }
  end

  local isJumpHeld = rider:KeyDown(IN_JUMP)
  local isHopPressed = isJumpHeld and not self.wasJumpHeld
  self.wasJumpHeld = isJumpHeld

  return {
    isPedalHeld = rider:KeyDown(IN_FORWARD),
    isBrakeHeld = rider:KeyDown(IN_BACK),
    steerDirection = (rider:KeyDown(IN_MOVERIGHT) and 1 or 0) - (rider:KeyDown(IN_MOVELEFT) and 1 or 0),
    isSprintHeld = rider:KeyDown(IN_SPEED),
    isHopPressed = isHopPressed,
    isWheelieHeld = rider:KeyDown(IN_ATTACK2),
  }
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
    gravity = getGravity(),
    isRidden = isRidden,
    isCrashed = isCrashed,
    isOnSide = isOnSide,
    isControlled = not isCrashed and not self.isPhysgunHeld and not isOnSide and (isRidden or canParkUpright),
  }
end

--- While balanced, tyre support pushes on the line through the centre of mass (pitch only, no roll torque), so the
--- lean controller never fights gravity. During a wheelie it pushes through the centre of mass itself (no pitch torque
--- either), otherwise the rear tyre alone would carry the weight behind it and slam the nose down. Uncontrolled, it
--- pushes at the contact point and the bike falls naturally.
function ENT:ApplyTyreSpring(physics, ride, wheel, contact, deltaTime)
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

  if (ride.isWheelieing) then
    forcePosition = physics:LocalToWorld(ride.massCenter)
  elseif (ride.isControlled) then
    forcePosition = physics:LocalToWorld(Vector(wheel.position.x, ride.massCenter.y, ride.massCenter.z))
  end

  physics:ApplyForceOffset(normal * (acceleration * ride.mass * deltaTime), forcePosition)
end

--- Springs each grounded tyre and adds what the tyres touch to `ride`: the ground normal, which wheels are down and
--- the bike's heading and speed along the ground.
function ENT:ApplyTyreSuspension(physics, ride, deltaTime)
  local groundNormalSum = Vector(0, 0, 0)

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

        groundNormalSum:Add(contact.normal)
        self:ApplyTyreSpring(physics, ride, wheel, contact, deltaTime)
      end
    end
  end

  ride.groundNormal = ride.groundedCount > 0 and groundNormalSum:GetNormalized() or vector_up
  ride.groundedFraction = ride.groundedCount / #self.Wheels
  ride.forwardAlongGround = projectOntoPlane(ride.forward, ride.groundNormal)
  ride.sideAlongGround = projectOntoPlane(ride.right, ride.groundNormal)
  ride.speed = ride.velocity:Dot(ride.forwardAlongGround)
  ride.absoluteSpeed = math.abs(ride.speed)
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

function ENT:ApplyPedalsAndBrakes(physics, ride, input, isPedalling, deltaTime)
  local speed = ride.speed
  -- Braking and resistance may stop the bike within a tick, but never push it the other way.
  local stoppingAcceleration = ride.absoluteSpeed / deltaTime
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
      local braking = math.min(brakeAcceleration * ride.groundedFraction, stoppingAcceleration)

      acceleration = acceleration - braking * getDirection(speed)
    end
  elseif (not isPedalling) then
    local resistance = math.min(
      bicycle.getTuning("rolling") * ride.groundedFraction + bicycle.getTuning("drag") * speed * speed,
      stoppingAcceleration
    )

    acceleration = acceleration - resistance * getDirection(speed)
  end

  physics:AddVelocity(ride.forwardAlongGround * (acceleration * deltaTime))
end

function ENT:TryBunnyHop(physics, ride)
  if (CurTime() <= self.nextHopAt) then
    return
  end

  self.nextHopAt = CurTime() + bicycle.getTuning("hop_cooldown")

  physics:AddVelocity(ride.groundNormal * bicycle.getTuning("hop"))
  physics:AddAngleVelocity(physics:WorldToLocalVector(ride.right * HOP_PITCH_SPEED))
end

--- Removes sideways slip, but never faster than tyre friction allows, so the bike can still slide.
function ENT:ApplyTyreGrip(physics, ride, deltaTime)
  local sideSpeed = ride.velocity:Dot(ride.sideAlongGround)
  local maxSpeedChange = bicycle.getTuning("mu") * ride.gravity * ride.groundedFraction * deltaTime
  local speedChange = math.Clamp(
    -sideSpeed * getBlendFraction(bicycle.getTuning("grip"), deltaTime),
    -maxSpeedChange,
    maxSpeedChange
  )

  physics:AddVelocity(ride.sideAlongGround * speedChange)
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

--- Holds the nose at bicycle_wheelie_angle.
--- @return Vector # Angular velocity correction in world space, deg/s
function ENT:GetWheelieCorrection(ride, deltaTime)
  local wantedPitchSpeed = math.Clamp(
    (bicycle.getTuning("wheelie_angle") - ride.pitch) * WHEELIE_GAIN,
    -WHEELIE_MAX_PITCH_SPEED,
    WHEELIE_MAX_PITCH_SPEED
  )
  -- Positive pitches the nose up.
  local currentPitchSpeed = ride.angularVelocity:Dot(ride.right)

  return ride.right * ((wantedPitchSpeed - currentPitchSpeed) * getBlendFraction(WHEELIE_RESPONSE, deltaTime))
end

--- Only while the bike moves into the ground, so the pitch a hop kicks in on take-off is left alone.
--- @return Vector # Angular velocity correction in world space, deg/s
function ENT:GetLandingPitchCorrection(ride, deltaTime)
  if (ride.groundedCount == 0 or ride.velocity:Dot(ride.groundNormal) >= 0) then
    return Vector(0, 0, 0)
  end

  local currentPitchSpeed = ride.angularVelocity:Dot(ride.right)

  return ride.right * (-currentPitchSpeed * getBlendFraction(LANDING_PITCH_DAMPING, deltaTime))
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
  correction:Add(self:GetLeanCorrection(ride, targetLean, deltaTime))

  if (ride.isWheelieing and ride.isRearGrounded) then
    correction:Add(self:GetWheelieCorrection(ride, deltaTime))
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

  -- Crashing ejects the rider, which can't happen inside the physics step.
  if (ride.isRidden and not ride.isCrashed and not self.isPhysgunHeld
        and (math.abs(ride.lean) > bicycle.getTuning("crash_lean") or math.abs(ride.pitch) > bicycle.getTuning("crash_pitch"))) then
    self.hasPendingCrash = true
  end

  -- Decided before the tyres are sprung, since a wheelie changes where they push.
  ride.isWheelieing = input.isWheelieHeld and ride.isControlled
      and math.abs(ride.velocity:Dot(ride.forward)) > WHEELIE_MIN_SPEED

  self:ApplyTyreSuspension(physics, ride, deltaTime)

  -- For the rider's pose.
  self.isWheelieing = ride.isWheelieing and ride.isRearGrounded

  local steerAngle = self:UpdateSteering(input.steerDirection, ride.absoluteSpeed, deltaTime)
  local isPedalling = input.isPedalHeld and ride.isRearGrounded

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

  return vector_origin, vector_origin, SIM_NOTHING
end
