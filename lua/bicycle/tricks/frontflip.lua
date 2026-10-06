local TRICK = {}

TRICK.id = "frontflip"
TRICK.name = "Front flip"
TRICK.contact = { none = true }
TRICK.rotatesBike = true

-- How quickly the bike's pitch follows the flip (1/s), and how hard it catches up on rotation it's behind (1/s).
local FLIP_RESPONSE = 20
local FLIP_ANGLE_GAIN = 8
-- A double-tap keeps driving the flip at least this far round, so a quick second tap still commits to it (deg).
local FLIP_COMMIT_ANGLE = 60

--- Double-tap forward in the air to flip, keep holding it for more flips. Holding Ctrl leaves the key to the pose
--- tricks, so a flip combined with one doesn't chain.
function TRICK:ReadInput(input, rider, state)
  local data = state.data

  if (input.doubleTaps[IN_FORWARD] and not input.isTrickHeld) then
    data.isTriggered = true
    data.isFlipping = true
  elseif ((not input.isPedalHeld or input.isTrickHeld) and math.abs(state.angle) >= FLIP_COMMIT_ANGLE) then
    data.isTriggered = false
  end

  return data.isTriggered and -1 or 0
end

function TRICK:Spin(state, isDriven, spinDirection, deltaTime)
  bicycle.trick.spin(state, isDriven, spinDirection, bicycle.getTuning("flip_speed"), deltaTime)
end

-- Turns the bike's pitch to follow the spin, positive is nose up.
function TRICK:Simulate(bike, physics, ride, state, deltaTime)
  local data = state.data

  if (not data.isFlipping) then
    return
  end

  local pitchSpeed = ride.angularVelocity:Dot(ride.right)

  -- With advanced air control, a finished flip hands the bike back to the rider's air controls instead of holding it
  -- where it ended, which may be tilted by the first tap of the double-tap. Its last spin is stopped so the bike
  -- doesn't carry on turning over.
  if (state.speed == 0 and bicycle.getTuningBool("advanced_air_control")) then
    if (not data.isReleased) then
      data.isReleased = true
      physics:AddAngleVelocity(physics:WorldToLocalVector(ride.right * -pitchSpeed))
    end

    return
  end

  data.isReleased = false
  data.rotated = (data.rotated or 0) + pitchSpeed * deltaTime

  local wantedPitchSpeed = state.speed + (state.angle - data.rotated) * FLIP_ANGLE_GAIN
  local blend = 1 - math.exp(-FLIP_RESPONSE * deltaTime)

  physics:AddAngleVelocity(physics:WorldToLocalVector(ride.right * ((wantedPitchSpeed - pitchSpeed) * blend)))
end

-- Judged by how the bike really lands, not by the spin.
function TRICK:Land(bike, ride, state)
  local turns = math.abs(bicycle.trick.getNearestFullTurn(state.angle) / 360)

  state.angle, state.speed = 0, 0

  if (state.data.isFlipping and bicycle.trick.getTilt(ride) > bicycle.getTuning("trick_land_tolerance")) then
    return nil
  end

  return turns
end

bicycle.trick.register(TRICK)
