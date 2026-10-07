local TRICK = {}

TRICK.id = "barspin"
TRICK.name = "Barspin"
TRICK.keys = "[+attack2] + [+moveleft] / [+moveright]"
TRICK.description = "Spins the handlebar round. Keep holding for more turns."
TRICK.contact = { none = true, rear = true }

-- How far the hands lift off the grips, fully by the time the bars are this far round (deg).
local HAND_RELEASE_LIFT = 5
local HAND_RELEASE_ANGLE = 45

function TRICK:ReadInput(input)
  if (not input.isWheelieHeld) then
    return 0, false
  end

  return input.steerDirection, true
end

function TRICK:Spin(state, isDriven, direction, deltaTime)
  bicycle.trick.spin(state, isDriven, direction, bicycle.getTuning("barspin_speed"), deltaTime)
end

if (CLIENT) then
  function TRICK:PoseBike(bike, angle, frame)
    bicycle.ik.rotateAround(bike, bike:GetForkBones(), frame.steeringPivot, frame.steeringAxis, -angle)
  end

  function TRICK:AdjustGripTarget(bike, arm, target, angle, frame)
    return target + frame.up * (HAND_RELEASE_LIFT * bicycle.trick.getReleaseFraction(angle, HAND_RELEASE_ANGLE))
  end
end

bicycle.trick.register(TRICK)
