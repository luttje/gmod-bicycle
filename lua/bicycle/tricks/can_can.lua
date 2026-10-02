local TRICK = {}

TRICK.id = "can_can"
TRICK.name = "Can-can"
TRICK.contact = { none = true }

local POSE_SPEED = 700
-- How far the leg crosses to the other side, and how high it lifts over the top tube halfway.
local LEG_CROSS = 14
local LEG_LIFT = 16

-- Steering right swings the right leg over to the left.
function TRICK:ReadInput(input)
  if (not input.isTrickHeld) then
    return 0, false
  end

  return input.steerDirection, true
end

function TRICK:Spin(state, isDriven, direction, deltaTime)
  bicycle.trick.hold(state, isDriven, direction, POSE_SPEED, deltaTime)
end

if (CLIENT) then
  function TRICK:AdjustFootTarget(bike, leg, target, angle, frame)
    -- A positive angle is the right leg, whose side is -1.
    if (leg.side ~= (angle > 0 and -1 or 1)) then
      return target
    end

    local fraction = bicycle.trick.getPoseFraction(angle)

    return target
        + frame.left * (-leg.side * LEG_CROSS * fraction)
        + frame.up * (LEG_LIFT * math.sin(fraction * math.pi))
  end
end

bicycle.trick.register(TRICK)
