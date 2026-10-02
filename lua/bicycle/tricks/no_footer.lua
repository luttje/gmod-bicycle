local TRICK = {}

TRICK.id = "no_footer"
TRICK.name = "No-footer"
TRICK.contact = { none = true }

local POSE_SPEED = 700
-- Where the feet swing to: forward, outward (mirrored for each side) and up.
local FEET_OUT = Vector(-8, 10, 3)

function TRICK:ReadInput(input)
  return (input.isTrickHeld and input.isBrakeHeld) and 1 or 0
end

function TRICK:Spin(state, isDriven, direction, deltaTime)
  bicycle.trick.hold(state, isDriven, direction, POSE_SPEED, deltaTime)
end

if (CLIENT) then
  function TRICK:AdjustFootTarget(bike, leg, target, angle, frame)
    local swing = frame.forward * FEET_OUT.x + frame.left * (leg.side * FEET_OUT.y) + frame.up * FEET_OUT.z

    return target + swing * bicycle.trick.getPoseFraction(angle)
  end
end

bicycle.trick.register(TRICK)
