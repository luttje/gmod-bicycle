-- Clients carry each trick on at its last sent speed, so it's only sent again once it's this far off that (deg).
local TRICK_SEND_TOLERANCE = 1
-- Tricks that clients already carry on right, such as held poses, are resent this often (s) for players who come into
-- view of the bike.
local TRICK_STATES_RESEND_INTERVAL = 0.25

--- @param trick table
--- @return table # `{ angle, speed, direction, data, canSpin, isHeldSinceStart, sent }`, `sent` is
--- `{ angle, speed, tick }` as last sent, nil once sent straight
function ENT:GetTrickState(trick)
  local state = self.trickStates[trick.id]

  if (not state) then
    state = { angle = 0, speed = 0, data = {}, canSpin = false }
    self.trickStates[trick.id] = state
  end

  return state
end

--- @param state table
local function clearTrickMemory(state)
  state.direction = nil
  state.data = {}
end

--- @param state table
--- @return boolean # Whether the trick is spun away from straight or still moving
local function isTrickActive(state)
  return state.angle ~= 0 or state.speed ~= 0
end

--- @param sent table? `state.sent`
--- @param tick number
--- @return number # Where clients have carried the trick on to by `tick`
local function getSentAngle(sent, tick)
  if (not sent) then
    return 0
  end

  return sent.angle + sent.speed * (tick - sent.tick) * engine.TickInterval()
end

--- Sends every trick that isn't straight, so each message replaces the last one whole and a lost one is made up for by
--- the next. Clients carry each trick on at its sent speed, so a message only goes once one drifts from that, or every
--- so often while tricks are done. Those go unreliably to players who can see the bike, except when a trick stops, as
--- clients would otherwise carry it on spinning. Once all are straight again, that goes reliably to everyone, so nobody
--- keeps an old pose.
function ENT:SendTrickStates()
  local tick = engine.TickCount()
  local activeCount = 0
  local isDrifting = false
  local isStopping = false

  for _, trick in ipairs(bicycle.trick.getAll()) do
    local state = self:GetTrickState(trick)
    local sent = state.sent

    if (isTrickActive(state)) then
      activeCount = activeCount + 1
    end

    isDrifting = isDrifting or math.abs(state.angle - getSentAngle(sent, tick)) > TRICK_SEND_TOLERANCE
    isStopping = isStopping or (sent ~= nil and sent.speed ~= 0 and state.speed == 0)
  end

  local isActive = activeCount > 0
  local isEnding = not isActive and self.hasSentActiveTricks
  local isResendDue = CurTime() >= (self.nextTrickStatesSendAt or 0)

  if (not isEnding and not (isActive and (isDrifting or isStopping or isResendDue))) then
    return
  end

  self.hasSentActiveTricks = isActive
  self.nextTrickStatesSendAt = CurTime() + TRICK_STATES_RESEND_INTERVAL

  net.Start("bicycle.TrickStates", isActive and not isStopping)
  net.WriteEntity(self)
  net.WriteUInt(tick, 32)
  net.WriteUInt(activeCount, 8)

  for _, trick in ipairs(bicycle.trick.getAll()) do
    local state = self.trickStates[trick.id]

    if (isTrickActive(state)) then
      bicycle.trick.write(trick)
      net.WriteFloat(state.angle)
      net.WriteFloat(state.speed)

      state.sent = { angle = state.angle, speed = state.speed, tick = tick }
    else
      state.sent = nil
    end
  end

  if (isActive) then
    net.SendPVS(self:GetPos())
  else
    net.Broadcast()
  end
end

function ENT:ResetTricks()
  for _, trick in ipairs(bicycle.trick.getAll()) do
    local state = self:GetTrickState(trick)

    state.angle, state.speed, state.canSpin = 0, 0, false
    clearTrickMemory(state)
  end

  self.isRotatingBike = false
  self.isSpinningBike = false
  self:SendTrickStates()
end

--- @param physics PhysObj
--- @param ride table
--- @param input table
--- @param rider Player
--- @param deltaTime number
--- @return boolean # Whether a trick takes the steering instead of the bars
function ENT:UpdateTricks(physics, ride, input, rider, deltaTime)
  if (not ride.isRidden or ride.isCrashed or self.isPhysgunHeld or not bicycle.getTuningBool("tricks")) then
    self:ResetTricks()

    return false
  end

  local contact = bicycle.trick.getContact(ride.isFrontGrounded, ride.isRearGrounded)
  local isSteeringTrick = false
  local isRotatingBike = false
  local isSpinningBike = false
  local landedTricks = {}
  local isBailing = false

  for _, trick in ipairs(bicycle.trick.getAll()) do
    local state = self:GetTrickState(trick)
    local canSpin = trick.contact[contact] == true

    if (canSpin) then
      local direction, takesSteering = trick:ReadInput(input, rider, state)
      local isDriven = direction ~= 0

      -- Input already held when the trick became possible is still riding, such as pedalling in a wheelie, and only
      -- does the trick once pressed again.
      if (not state.canSpin) then
        state.isHeldSinceStart = isDriven and trick.needsFreshInput
      elseif (not isDriven) then
        state.isHeldSinceStart = false
      end

      if (state.isHeldSinceStart) then
        isDriven, takesSteering = false, false
      end

      isSteeringTrick = isSteeringTrick or takesSteering == true
      trick:Spin(state, isDriven, direction, deltaTime)
      trick:Simulate(self, physics, ride, state, deltaTime)
    else
      if (state.canSpin) then
        local turns = trick:Land(self, ride, state)

        if (not turns) then
          isBailing = true
        elseif (turns > 0) then
          landedTricks[trick.id] = turns
        end

        clearTrickMemory(state)
      end

      bicycle.trick.straighten(state, deltaTime)
    end

    state.canSpin = canSpin
    isRotatingBike = isRotatingBike or (trick.rotatesBike and (state.angle ~= 0 or state.speed ~= 0))
    isSpinningBike = isSpinningBike or (trick.rotatesBike and state.speed ~= 0)
  end

  -- Read by the crash check next tick, which runs before the tricks.
  self.isRotatingBike = isRotatingBike
  -- Unlike `isRotatingBike`, ends once the bike stops turning over rather than on landing.
  self.isSpinningBike = isSpinningBike
  self:SendTrickStates()

  if (isBailing) then
    self.hasPendingCrash = true
  elseif (next(landedTricks)) then
    self:QueueLandedTricks(landedTricks)
  end

  return isSteeringTrick
end

--- Landed tricks are handled in Think, outside the physics step.
--- @param landedTricks table<string, number> Whole turns by trick id
function ENT:QueueLandedTricks(landedTricks)
  local pending = self.pendingLandedTricks or {}

  for id, turns in pairs(landedTricks) do
    pending[id] = (pending[id] or 0) + turns
  end

  self.pendingLandedTricks = pending
end

function ENT:HandleLandedTricks()
  local landedTricks = self.pendingLandedTricks

  if (not landedTricks) then
    return
  end

  self.pendingLandedTricks = nil

  local rider = self:GetRider()

  -- Thrown off since, such as by an impact in the same tick.
  if (not IsValid(rider) or self:GetCrashed()) then
    return
  end

  self:EmitBicycleSound("bicycle/frame_creak.wav", 70, math.random(110, 120))

  local tricks = {}

  for id, turns in pairs(landedTricks) do
    local trick = bicycle.trick.get(id)

    if (trick) then
      trick:OnLanded(self, rider, turns)
      tricks[#tricks + 1] = { trick = trick, turns = turns }
    end
  end

  -- Shown on the rider's HUD.
  net.Start("bicycle.TricksLanded")
  net.WriteUInt(#tricks, 8)

  for _, landed in ipairs(tricks) do
    bicycle.trick.write(landed.trick)
    net.WriteUInt(math.min(landed.turns, 255), 8)
  end

  net.Send(rider)

  -- Lets gamemodes score tricks. `landedTricks` holds the whole turns of each trick landed cleanly, by trick id (such
  -- as `{ tailwhip = 2, barspin = 1 }`). Tricks without a whole turn are left out.
  hook.Run("BicycleTrickLanded", rider, self, landedTricks)
end
