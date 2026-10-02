local TRICK = {}

TRICK.id = "tailwhip"
TRICK.name = "Tailwhip"
TRICK.contact = { none = true }

-- How far the feet kick clear of the frame (forward, outward mirrored for each side, up), fully by the time the frame
-- is this far round (deg).
local FOOT_KICK_OUT = Vector(-2, 6, 2)
local FOOT_RELEASE_ANGLE = 45

function TRICK:ReadInput(input)
  if (not input.isLeanForwardHeld) then
    return 0, false
  end

  return input.steerDirection, true
end

function TRICK:Spin(state, isDriven, direction, deltaTime)
  bicycle.trick.spin(state, isDriven, direction, bicycle.getTuning("tailwhip_speed"), deltaTime)
end

if (CLIENT) then
  --- @return number[] # The frame and everything on it, except the fork and what it carries
  local function getWhippedBones(bike)
    local frame = bike:LookupBone("frame")
    local fork = bike:GetAnimatedBones().fork

    if (not frame or not fork) then
      return {}
    end

    local isOnFork = { [fork] = true }

    for _, bone in ipairs(bicycle.ik.getDescendants(bike, fork)) do
      isOnFork[bone] = true
    end

    local whippedBones = { frame }

    for _, bone in ipairs(bicycle.ik.getDescendants(bike, frame)) do
      if (not isOnFork[bone]) then
        whippedBones[#whippedBones + 1] = bone
      end
    end

    return whippedBones
  end

  --- Leaves the fork and handlebar where the rider holds them. Spinning counter-clockwise seen from above swings the
  --- rear wheel out to the right.
  function TRICK:PoseBike(bike, angle, frame)
    bicycle.ik.rotateAround(bike, getWhippedBones(bike), frame.steeringPivot, frame.steeringAxis, angle)
  end

  function TRICK:AdjustFootTarget(bike, leg, target, angle, frame)
    local kickOut = frame.forward * FOOT_KICK_OUT.x
        + frame.left * (leg.side * FOOT_KICK_OUT.y)
        + frame.up * FOOT_KICK_OUT.z

    return target + kickOut * bicycle.trick.getReleaseFraction(angle, FOOT_RELEASE_ANGLE)
  end
end

bicycle.trick.register(TRICK)
