ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Bicycle"
-- Not spawnable itself: every registered model is its own class derived from this one.
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.IsBicycle = true

-- Geometry is entity-local with forward as +X and up as +Z. The server measures the wheels and the seat from the model
-- on spawn and networks them. The values below are only used until then or if measuring fails.
ENT.EmptyMass = 15
ENT.WheelRadius = 16
ENT.Wheelbase = 48
ENT.SeatPosition = Vector(-12, 0, 21)
ENT.Wheels = {
  { position = Vector(-24, 0, 0), isFront = false },
  { position = Vector(24, 0, 0),  isFront = true },
}
-- The collision hull's wheels are shrunk so they only act as bump stops, the wheel traces carry the bike.
ENT.WheelHullScale = 0.7
-- Wheel revolutions per crank revolution.
ENT.GearRatio = 2.8
-- Where the rider sits relative to the saddle, and how far they lean forward.
ENT.SeatOffset = Vector(0, 0, 0)
ENT.SeatPitch = 0
-- How many degrees further forward the rider tucks while sprint-pedalling.
ENT.SprintLeanPitch = 25
-- How many degrees the rider leans back during a wheelie, and how far the seat moves with it (forward, left, up).
ENT.WheelieLeanPitch = 1
ENT.WheelieSeatShift = Vector(-1.93, 0, 1.58)
-- How many degrees the rider leans forward while holding the forward lean (for stoppies), and how far the seat moves
-- with it (forward, left, up).
ENT.LeanForwardPitch = 15
ENT.LeanForwardSeatShift = Vector(3, 0, 1)
-- How far out from the pedal attachments the feet go, and how far above the pedal's axle the ball of the foot sits.
ENT.PedalCenterOffset = 0
ENT.FootBallHeight = 1
-- Where the hands hold relative to the grip attachments: forward, outward (mirrored for each side) and up.
ENT.GripOffset = Vector(0, 0, 0)
-- The attachment a passenger seat is put at. Without one the bike has no passenger seat.
ENT.PassengerAttachment = nil
-- Where the passenger sits relative to the passenger attachment.
ENT.PassengerSeatOffset = Vector(0, 0, 0)
-- Degrees each of the passenger's legs is turned outward at the hip, so they fit around the rider.
ENT.PassengerLegSpread = 0
-- Bodygroups set on spawn, as { [bodygroup name] = submodel index }.
ENT.BodyGroups = nil
-- Prisoner pods face their own +Y.
ENT.SeatAngles = Angle(0, -90, 0)
-- The rider's eye angles, which are relative to the seat, that look straight along the bike.
ENT.SeatForwardEyeAngles = Angle(0, 90, 0)

ENT.RearWheelBone = "wheel_rear"
ENT.FrontWheelBone = "wheel_front"
ENT.SeatAttachment = "seat"

-- Below this the wheel's own "down" has almost no length, meaning the bike is lying on its side.
local MIN_WHEEL_DOWN_LENGTH = 0.35
-- Wheel traces start this far behind the hub, so a hub resting on the ground still finds it.
local WHEEL_TRACE_BACKOFF = 6
local WHEEL_TRACE_REACH_PAST_RIM = 8
-- The wheel traces fan across the lower half of the wheel (deg either side of the bike's down), so steep slopes and
-- ramps ahead are found too.
local WHEEL_TRACE_FAN_ANGLE = 90
local WHEEL_TRACE_FAN_COUNT = 9
-- Steeper surfaces (deg from the bike's up) are walls: they push the wheel back but aren't ridden on.
local MAX_GROUND_ANGLE = 60
local MIN_GROUND_NORMAL_UP = math.cos(math.rad(MAX_GROUND_ANGLE))
-- A wall whose top is below the hub is a step, such as a curb. The wheel rolls over its edge as long as the edge pushes
-- it at most this steeply (deg from the bike's up), which allows steps up to about three quarters of the wheel radius.
local MAX_STEP_EDGE_ANGLE = 75
local MIN_STEP_EDGE_NORMAL_UP = math.cos(math.rad(MAX_STEP_EDGE_ANGLE))
-- How far past a wall's face the step's top is looked for.
local STEP_PROBE_DEPTH = 2

function ENT:SetupDataTables()
  self:NetworkVar("Entity", "Seat")
  self:NetworkVar("Entity", "Rider")
  -- Whoever sits in the passenger seat, on bikes that have one.
  self:NetworkVar("Entity", "Passenger")
  -- Handlebar angle in degrees, positive is right.
  self:NetworkVar("Float", "Steer")
  -- Crank rpm, purely visual.
  self:NetworkVar("Float", "Cadence")
  -- Degrees, positive is right.
  self:NetworkVar("Float", "TargetLean")
  -- How hard the tyres skid from braking or sliding sideways, 0-1. Only drives the skid sound.
  self:NetworkVar("Float", "Skid")
  self:NetworkVar("Bool", "Crashed")
  -- Measured by the server from the model.
  self:NetworkVar("Float", "WheelRadius")
  self:NetworkVar("Vector", "RearHub")
  self:NetworkVar("Vector", "FrontHub")
end

--- @param rearHub Vector Entity-local
--- @param frontHub Vector Entity-local
--- @param wheelRadius number
function ENT:ApplyGeometry(rearHub, frontHub, wheelRadius)
  -- A table of this entity's own, the class's default is shared by every bike.
  self.Wheels = {
    { position = rearHub,  isFront = false },
    { position = frontHub, isFront = true },
  }
  self.WheelRadius = wheelRadius
  self.Wheelbase = frontHub.x - rearHub.x
end

--- @return Vector? # Entity-local, nil when the model has no such attachment
function ENT:GetAttachmentLocalPosition(attachmentName)
  local attachment = self:GetAttachment(self:LookupAttachment(attachmentName))

  return attachment and self:WorldToLocal(attachment.Pos)
end

--- The saddle plus the model's seat offset. On the server this includes the shift back while wheelieing and forward
--- while leaning forward.
function ENT:GetSeatOffset()
  return self.SeatPosition + self.SeatOffset
      + self.WheelieSeatShift * (self.wheelieLeanFraction or 0)
      + self.LeanForwardSeatShift * (self.forwardLeanFraction or 0)
end

--- Pitches the whole seat, and the rider with it, forward around the bike's sideways axis. On the server this includes
--- the extra tuck while sprinting, the lean back while wheelieing and the lean forward while leaning forward.
function ENT:GetSeatLocalAngles()
  local pitch = self.SeatPitch
      + self.SprintLeanPitch * (self.sprintLeanFraction or 0)
      - self.WheelieLeanPitch * (self.wheelieLeanFraction or 0)
      + self.LeanForwardPitch * (self.forwardLeanFraction or 0)
  local angles = Angle(self.SeatAngles)
  angles:RotateAroundAxis(Vector(0, 1, 0), pitch)

  return angles
end

--- The passenger attachment plus the model's passenger seat offset.
--- @return Vector? # Entity-local, nil when the model has no passenger seat
function ENT:GetPassengerSeatOffset()
  if (not self.PassengerAttachment) then
    return nil
  end

  -- Read once, as the attachment follows the posed bones on the client.
  self.passengerSeatPosition = self.passengerSeatPosition
      or self:GetAttachmentLocalPosition(self.PassengerAttachment)

  return self.passengerSeatPosition and self.passengerSeatPosition + self.PassengerSeatOffset
end

--- @return number # Degrees, positive is leaning right
function ENT:GetLean()
  -- Leaning right dips the bike's right side below the horizon.
  return -bicycle.getElevation(self:GetRight())
end

--- @return number # Speed along the bike's heading, negative when rolling backwards
function ENT:GetForwardSpeed()
  return self:GetVelocity():Dot(self:GetForward())
end

--- @return Entity[] # The bike, its seats and whoever sits in them
function ENT:GetWheelTraceFilter()
  local filter = { self }
  local seat, rider = self:GetSeat(), self:GetRider()

  if (IsValid(seat)) then
    filter[#filter + 1] = seat
  end

  if (IsValid(rider)) then
    filter[#filter + 1] = rider
  end

  local passengerSeat, passenger = self.passengerSeat, self:GetPassenger()

  if (IsValid(passengerSeat)) then
    filter[#filter + 1] = passengerSeat
  end

  if (IsValid(passenger)) then
    filter[#filter + 1] = passenger
  end

  return filter
end

--- @return table? # { distance, contactPosition, normal }, nil when the trace reaches nothing
local function traceWheelRay(hubPosition, direction, radius, filter)
  local reach = radius + WHEEL_TRACE_REACH_PAST_RIM
  local trace = util.TraceLine({
    start = hubPosition - direction * WHEEL_TRACE_BACKOFF,
    endpos = hubPosition + direction * reach,
    filter = filter,
    mask = MASK_SOLID,
  })

  if (not trace.Hit) then
    return nil
  end

  if (trace.StartSolid) then
    -- A trace starting inside the ground has no usable fraction or normal, so push straight back along it instead.
    return { distance = radius * 0.5, contactPosition = trace.HitPos, normal = -direction }
  end

  return {
    distance = trace.Fraction * (WHEEL_TRACE_BACKOFF + reach) - WHEEL_TRACE_BACKOFF,
    contactPosition = trace.HitPos,
    normal = trace.HitNormal,
  }
end

--- Retraces along the hit surface's normal within the wheel plane, which is exact on flat surfaces.
--- @return table # The closer of `hit` and the retrace
local function refineWheelHit(hit, hubPosition, right, up, radius, filter)
  local direction = right * hit.normal:Dot(right) - hit.normal
  local directionLength = direction:Length()

  if (directionLength < MIN_WHEEL_DOWN_LENGTH) then
    return hit
  end

  direction:Div(directionLength)

  local refined = traceWheelRay(hubPosition, direction, radius, filter)
  local isGround = hit.normal:Dot(up) >= MIN_GROUND_NORMAL_UP

  if (refined and refined.distance < hit.distance and (refined.normal:Dot(up) >= MIN_GROUND_NORMAL_UP) == isGround) then
    return refined
  end

  return hit
end

--- Looks for the top of the step a wall hit belongs to. The fan only finds the step's flat top and face, never the edge
--- between them, so a wheel against a curb would be held up by the top and pushed back by the face, and never climb.
--- @return table? # { distance, contactPosition, normal, groundNormal } for the edge, with `normal` from the edge to
--- the hub and `groundNormal` the step's top. Nil when the wall is no step, or too tall to climb.
local function findStepEdge(wall, hubPosition, right, up, filter)
  local probe = wall.contactPosition - wall.normal * STEP_PROBE_DEPTH
  local topTrace = util.TraceLine({
    start = probe + up * (hubPosition - probe):Dot(up),
    endpos = probe,
    filter = filter,
    mask = MASK_SOLID,
  })

  -- Starting in solid, the wall reaches past the hub.
  if (not topTrace.Hit or topTrace.StartSolid or topTrace.HitNormal:Dot(up) < MIN_GROUND_NORMAL_UP) then
    return nil
  end

  local edge = topTrace.HitPos + wall.normal * STEP_PROBE_DEPTH
  local offset = hubPosition - edge
  offset:Sub(right * offset:Dot(right))

  local distance = offset:Length()

  if (distance < 1e-3) then
    return nil
  end

  offset:Div(distance)

  if (offset:Dot(up) < MIN_STEP_EDGE_NORMAL_UP) then
    return nil
  end

  return { distance = distance, contactPosition = edge, normal = offset, groundNormal = topTrace.HitNormal }
end

--- Finds the nearest ground and wall within the wheel disc, so the contact stays correct while leaning or on slopes.
--- @param wheelIndex number
--- @param filter? table Defaults to `ENT:GetWheelTraceFilter()`
--- @param position? Vector Defaults to the bike's position
--- @param angles? Angle Defaults to the bike's angles
--- @return table # { hubPosition, isHit, isGrounded, compression, contactPosition?, normal?, groundNormal?, wall? },
--- where `normal` is the way the ground pushes the wheel and `groundNormal` the surface it rides on, which differ on
--- the edge of a step. `wall` is { hubPosition, compression, contactPosition, normal } while the wheel presses against
--- one
function ENT:TraceWheel(wheelIndex, filter, position, angles)
  position = position or self:GetPos()
  angles = angles or self:GetAngles()
  filter = filter or self:GetWheelTraceFilter()

  local radius = self.WheelRadius
  local hubPosition = LocalToWorld(self.Wheels[wheelIndex].position, angle_zero, position, angles)
  local contact = { hubPosition = hubPosition, isHit = false, isGrounded = false, compression = 0 }

  local forward, right, up = angles:Forward(), angles:Right(), angles:Up()

  -- How much of world down lies within the wheel plane.
  if (math.sqrt(1 - right.z * right.z) < MIN_WHEEL_DOWN_LENGTH) then
    return contact
  end

  local nearestGround, nearestWall

  for ray = 0, WHEEL_TRACE_FAN_COUNT - 1 do
    local fanAngle = math.rad(WHEEL_TRACE_FAN_ANGLE * (ray * 2 / (WHEEL_TRACE_FAN_COUNT - 1) - 1))
    local hit = traceWheelRay(hubPosition, forward * math.sin(fanAngle) - up * math.cos(fanAngle), radius, filter)

    if (hit) then
      if (hit.normal:Dot(up) >= MIN_GROUND_NORMAL_UP) then
        if (not nearestGround or hit.distance < nearestGround.distance) then
          nearestGround = hit
        end
      elseif (not nearestWall or hit.distance < nearestWall.distance) then
        nearestWall = hit
      end
    end
  end

  if (nearestGround) then
    nearestGround = refineWheelHit(nearestGround, hubPosition, right, up, radius, filter)
  end

  if (nearestWall) then
    nearestWall = refineWheelHit(nearestWall, hubPosition, right, up, radius, filter)

    local stepEdge = findStepEdge(nearestWall, hubPosition, right, up, filter)

    -- The edge stands in for the step's face, so the wheel rolls up over it instead of being pushed back.
    if (stepEdge) then
      nearestWall = nil

      if (not nearestGround or stepEdge.distance < nearestGround.distance) then
        nearestGround = stepEdge
      end
    end
  end

  if (nearestGround) then
    contact.isHit = true
    contact.contactPosition = nearestGround.contactPosition
    contact.normal = nearestGround.normal
    contact.groundNormal = nearestGround.groundNormal or nearestGround.normal
    contact.compression = radius - nearestGround.distance
    contact.isGrounded = contact.compression > 0
  end

  if (nearestWall) then
    if (nearestWall.distance < radius) then
      contact.wall = {
        hubPosition = hubPosition,
        compression = radius - nearestWall.distance,
        contactPosition = nearestWall.contactPosition,
        normal = nearestWall.normal,
      }
    end
  end

  return contact
end
