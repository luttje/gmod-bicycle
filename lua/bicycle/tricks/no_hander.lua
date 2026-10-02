local TRICK = {}

TRICK.id = "no_hander"
TRICK.name = "No-hander"
TRICK.contact = { none = true }

local POSE_SPEED = 700
-- Where the hands go with the arms spread: outward (mirrored for each side) and up.
local HANDS_OUT = 12
local HANDS_UP = 8

function TRICK:ReadInput(input)
  return (input.isTrickHeld and input.isPedalHeld) and 1 or 0
end

function TRICK:Spin(state, isDriven, direction, deltaTime)
  bicycle.trick.hold(state, isDriven, direction, POSE_SPEED, deltaTime)
end

if (CLIENT) then
  function TRICK:AdjustGripTarget(bike, arm, target, angle, frame)
    local spread = frame.left * (arm.side * HANDS_OUT) + frame.up * HANDS_UP

    return target + spread * bicycle.trick.getPoseFraction(angle)
  end
end

bicycle.trick.register(TRICK)
