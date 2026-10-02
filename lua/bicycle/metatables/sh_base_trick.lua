--- Defaults for every registered trick, which a trick table overrides by setting the same key. A trick's `state.angle`
--- is signed and keeps counting past whole turns until it lands.
local BASE_TRICK = {}

BASE_TRICK.__index = BASE_TRICK

--- Shown to players, defaults to the id.
BASE_TRICK.name = nil

--- Which wheels may touch the ground while the trick is done.
BASE_TRICK.contact = { none = true, front = nil, rear = nil, both = nil }

--- Whether the trick turns the real bike over, which skips the crash check and holds the camera still.
BASE_TRICK.rotatesBike = false

--- Whether input already driving the trick when it becomes possible is ignored until pressed again. For tricks on keys
--- that also ride the bike, such as pedalling in a wheelie.
BASE_TRICK.needsFreshInput = false

--- Server, every tick while the contact allows the trick.
--- @param input table
--- @param rider Player
--- @param state table `{ angle, speed, direction, data }`, `data` is the trick's own and cleared on landing
--- @return number direction 1 or -1 to drive the trick, 0 to let it finish
--- @return boolean? takesSteering Whether steering drives the trick instead of the bars
function BASE_TRICK:ReadInput(input, rider, state)
  return 0, false
end

--- Server, moves `state.angle` and `state.speed` on, such as with `bicycle.trick.spin` or `bicycle.trick.hold`.
--- @param state table
--- @param isDriven boolean
--- @param direction number 1 or -1 while driven
--- @param deltaTime number
function BASE_TRICK:Spin(state, isDriven, direction, deltaTime)
end

--- Server, applies forces to the bike after `Spin`.
--- @param bike Entity
--- @param physics PhysObj
--- @param ride table
--- @param state table
--- @param deltaTime number
function BASE_TRICK:Simulate(bike, physics, ride, state, deltaTime)
end

--- Server, when the bike touches down in a way the contact doesn't allow.
--- @param bike Entity
--- @param ride table
--- @param state table
--- @return number? # Whole turns landed, nil to throw the rider off
function BASE_TRICK:Land(bike, ride, state)
  local fullTurn = bicycle.trick.getNearestFullTurn(state.angle)
  local offset = state.angle - fullTurn

  state.angle, state.speed = offset, 0

  if (math.abs(offset) > bicycle.getTuning("trick_land_tolerance")) then
    return nil
  end

  return math.abs(fullTurn / 360)
end

--- Server, once landed cleanly with at least one whole turn.
--- @param bike Entity
--- @param rider Player
--- @param turns number
function BASE_TRICK:OnLanded(bike, rider, turns)
end

--- Client, moves the bike's bones inside its "BuildBonePositions".
--- @param bike Entity
--- @param angle number The drawn `state.angle`
--- @param frame table `{ forward, left, up, steeringPivot, steeringAxis }` in world space, the steering axis points up
function BASE_TRICK:PoseBike(bike, angle, frame)
end

--- Client, moves where the rider's foot goes.
--- @param bike Entity
--- @param leg table `leg.side` is 1 on the bike's left, -1 on its right
--- @param target Vector Where the ball of the foot goes, world space
--- @param angle number
--- @param frame table
--- @return Vector
function BASE_TRICK:AdjustFootTarget(bike, leg, target, angle, frame)
  return target
end

--- Client, moves where the rider's hand holds.
--- @param bike Entity
--- @param arm table `arm.side` is 1 on the bike's left, -1 on its right
--- @param target Vector Where the hand holds, world space
--- @param angle number
--- @param frame table
--- @return Vector
function BASE_TRICK:AdjustGripTarget(bike, arm, target, angle, frame)
  return target
end

RegisterMetaTable("bicycle.trick", BASE_TRICK)
