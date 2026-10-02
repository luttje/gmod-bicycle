local TRICK = {}

TRICK.id = "x_up"
TRICK.name = "X-up"
TRICK.contact = { none = true, rear = true }
-- Right mouse + W is also pedalling in a wheelie.
TRICK.needsFreshInput = true

local POSE_SPEED = 700
-- How far the bars turn, the way steering right does, with the rider's arms crossing as they hold on.
local BAR_TURN = 160

function TRICK:ReadInput(input)
  return (input.isWheelieHeld and input.isPedalHeld) and 1 or 0
end

function TRICK:Spin(state, isDriven, direction, deltaTime)
  bicycle.trick.hold(state, isDriven, direction, POSE_SPEED, deltaTime)
end

if (CLIENT) then
  --- @param angle number
  --- @return number # Degrees around the steering axis, counter-clockwise seen from above
  local function getBarTurn(angle)
    return -BAR_TURN * bicycle.trick.getPoseFraction(angle)
  end

  function TRICK:PoseBike(bike, angle, frame)
    bicycle.ik.rotateAround(bike, bike:GetForkBones(), frame.steeringPivot, frame.steeringAxis, getBarTurn(angle))
  end

  function TRICK:AdjustGripTarget(bike, arm, target, angle, frame)
    if (not frame.steeringPivot) then
      return target
    end

    return bicycle.ik.rotatePointAround(target, frame.steeringPivot, frame.steeringAxis, getBarTurn(angle))
  end
end

bicycle.trick.register(TRICK)
