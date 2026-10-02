bicycle.trick = bicycle.trick or {}

bicycle.includePrefixed("sh_base_trick.lua", "metatables/")

local TRICKS_FOLDER = "bicycle/tricks/"
local FULL_TURN = 360

-- How fast a held spin winds up (deg/s²).
local SPIN_ACCEL = 5000
-- Once let go, a spin slows into the next whole turn at this speed per degree still to go (1/s), down to the minimum
-- (deg/s).
local FINISH_GAIN = 8
local FINISH_MIN_SPEED = 240
-- Let go within this many degrees past a full turn, a spin settles back onto it instead of going round again.
local SETTLE_BACK_ANGLE = 30
-- How fast a spin settles onto the nearest full turn (1/s), and how close counts as settled (deg).
local STRAIGHTEN_RATE = 15
local STRAIGHT_EPSILON = 0.5

-- Tricks are sent as the id of a network string named after them, which the server and clients agree on, instead of
-- by their id.
local NETWORK_NAME_PREFIX = "bicycle.trick."
local NETWORK_ID_BITS = 12

local TRICK_META = FindMetaTable("bicycle.trick")

if (SERVER) then
  util.AddNetworkString("bicycle.TrickStates")
end

--- @type table[] In the order they were registered
local tricks = {}
--- @type table<string, table>
local tricksById = {}

--- Registers a trick, replacing any trick with the same id. Call it on both the server and the client.
--- @param trick table `id` is required
--- @return table? # The trick, nil when it's invalid
function bicycle.trick.register(trick)
  if (not isstring(trick.id) or trick.id == "") then
    ErrorNoHaltWithStack("[bicycle] bicycle.trick.register needs a trick with a string id.\n")
    return nil
  end

  setmetatable(trick, TRICK_META)
  trick.name = trick.name or trick.id

  local existing = tricksById[trick.id]

  if (existing) then
    tricks[table.KeyFromValue(tricks, existing)] = trick
  else
    tricks[#tricks + 1] = trick
  end

  tricksById[trick.id] = trick

  if (SERVER) then
    util.AddNetworkString(NETWORK_NAME_PREFIX .. trick.id)
  end

  return trick
end

--- Writes `trick` to the net message being started.
--- @param trick table
function bicycle.trick.write(trick)
  net.WriteUInt(util.NetworkStringToID(NETWORK_NAME_PREFIX .. trick.id), NETWORK_ID_BITS)
end

--- @return table? # The trick read from the net message, nil when this client doesn't have it
function bicycle.trick.read()
  local name = util.NetworkIDToString(net.ReadUInt(NETWORK_ID_BITS))

  return name and bicycle.trick.get(name:sub(#NETWORK_NAME_PREFIX + 1))
end

--- @param id string
--- @return table?
function bicycle.trick.get(id)
  return tricksById[id]
end

--- @return table[] # Every registered trick, in the order they were registered
function bicycle.trick.getAll()
  return tricks
end

--- @param isFrontGrounded boolean
--- @param isRearGrounded boolean
--- @return string # "none", "rear", "front" or "both"
function bicycle.trick.getContact(isFrontGrounded, isRearGrounded)
  if (isFrontGrounded and isRearGrounded) then
    return "both"
  end

  return isRearGrounded and "rear" or (isFrontGrounded and "front" or "none")
end

--- @param angle number
--- @return number # The nearest whole turn to `angle`
function bicycle.trick.getNearestFullTurn(angle)
  return math.Round(angle / FULL_TURN) * FULL_TURN
end

--- @param angle number
--- @return number # How far into its pose a held trick is: 0 at whole turns, 1 at half turns
function bicycle.trick.getPoseFraction(angle)
  return (1 - math.cos(math.rad(angle))) * 0.5
end

--- @param ride table
--- @return number # Degrees between the bike's up and the ground's normal
function bicycle.trick.getTilt(ride)
  return math.deg(math.acos(math.Clamp(ride.angles:Up():Dot(ride.groundNormal), -1, 1)))
end

--- @param angle number
--- @param releaseAngle number
--- @return number # 0 while `angle` is straight, easing up to 1 at `releaseAngle` off
function bicycle.trick.getReleaseFraction(angle, releaseAngle)
  local fraction = math.min(math.abs(math.NormalizeAngle(angle)) / releaseAngle, 1)

  return math.sin(fraction * math.pi * 0.5)
end

--- Settles a spin onto the nearest whole turn.
--- @param state table
--- @param deltaTime number
function bicycle.trick.straighten(state, deltaTime)
  local target = bicycle.trick.getNearestFullTurn(state.angle)

  state.speed = 0
  state.angle = Lerp(1 - math.exp(-STRAIGHTEN_RATE * deltaTime), state.angle, target)

  if (math.abs(state.angle - target) < STRAIGHT_EPSILON) then
    state.angle = target
  end
end

--- Spins while driven, and once let go carries on into the next whole turn, so a short tap still gives one.
--- @param state table
--- @param isDriven boolean
--- @param direction number 1 or -1 while driven
--- @param maxSpeed number deg/s
--- @param deltaTime number
function bicycle.trick.spin(state, isDriven, direction, maxSpeed, deltaTime)
  if (isDriven) then
    state.speed = math.Approach(state.speed, direction * maxSpeed, SPIN_ACCEL * deltaTime)
  else
    local spinDirection = state.speed > 0 and 1 or -1
    local nextFullTurn = spinDirection > 0
        and math.ceil(state.angle / FULL_TURN) * FULL_TURN
        or math.floor(state.angle / FULL_TURN) * FULL_TURN
    local remaining = math.abs(nextFullTurn - state.angle)

    if (state.speed == 0 or remaining == 0 or remaining > FULL_TURN - SETTLE_BACK_ANGLE) then
      bicycle.trick.straighten(state, deltaTime)
      return
    end

    -- Keeps winding up to full speed, so a tap commits to the whole turn, and only slows down near its end.
    local finishSpeed = math.max(
      math.min(math.Approach(math.abs(state.speed), maxSpeed, SPIN_ACCEL * deltaTime), remaining * FINISH_GAIN),
      FINISH_MIN_SPEED
    )

    if (finishSpeed * deltaTime >= remaining) then
      state.angle, state.speed = nextFullTurn, 0
      return
    end

    state.speed = spinDirection * finishSpeed
  end

  state.angle = state.angle + state.speed * deltaTime
end

--- Holds a pose half a turn in while driven, and once let go carries on to the next whole turn, undoing it.
--- @param state table
--- @param isDriven boolean
--- @param direction number 1 or -1 while driven
--- @param speed number deg/s
--- @param deltaTime number
function bicycle.trick.hold(state, isDriven, direction, speed, deltaTime)
  local isPosed = state.angle % FULL_TURN ~= 0

  -- Driving the other way mid-pose finishes the current pose first.
  if (isDriven and isPosed and direction ~= state.direction) then
    isDriven = false
  end

  if (not isDriven and (not isPosed or not state.direction)) then
    bicycle.trick.straighten(state, deltaTime)
    return
  end

  local poseDirection = isPosed and state.direction or direction
  local base = poseDirection > 0
      and math.floor(state.angle / FULL_TURN) * FULL_TURN
      or math.ceil(state.angle / FULL_TURN) * FULL_TURN
  local target = base + poseDirection * (isDriven and FULL_TURN * 0.5 or FULL_TURN)
  local remaining = target - state.angle

  state.direction = poseDirection

  if (math.abs(remaining) <= speed * deltaTime) then
    state.angle, state.speed = target, 0
    return
  end

  state.speed = (remaining > 0 and 1 or -1) * speed
  state.angle = state.angle + state.speed * deltaTime
end

if (CLIENT) then
  net.Receive("bicycle.TrickStates", function()
    local bike = net.ReadEntity()
    local tick = net.ReadUInt(32)
    local states = {}

    for _ = 1, net.ReadUInt(8) do
      local trick = bicycle.trick.read()
      local angle = net.ReadFloat()
      local speed = net.ReadFloat()

      if (trick) then
        states[trick.id] = { angle = angle, speed = speed }
      end
    end

    -- Each message holds every trick that isn't straight, so one arriving after a newer one is out of date as a whole.
    if (not IsValid(bike) or not bike.IsBicycle or tick < (bike.lastTrickStatesTick or 0)) then
      return
    end

    bike.lastTrickStatesTick = tick
    bike:AddTrickSnapshot(tick * engine.TickInterval(), states)
  end)
end

for _, fileName in ipairs((file.Find(TRICKS_FOLDER .. "*.lua", "LUA"))) do
  if (SERVER) then
    AddCSLuaFile(TRICKS_FOLDER .. fileName)
  end

  include(TRICKS_FOLDER .. fileName)
end
