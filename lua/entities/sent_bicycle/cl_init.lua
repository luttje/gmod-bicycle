include("shared.lua")

local FULL_TURN = math.pi * 2

-- The rider's limbs, each reaching for an attachment on the bike. `side` is 1 on the bike's left, -1 on its right.
local RIDER_LEGS = {
  {
    side = 1,
    thigh = "ValveBiped.Bip01_L_Thigh",
    calf = "ValveBiped.Bip01_L_Calf",
    foot = "ValveBiped.Bip01_L_Foot",
    toe = "ValveBiped.Bip01_L_Toe0",
    pedalAttachment = "pedal_L",
    pedalBone = "pedal_L",
    -- The left pedal is at the top at crank angle 0, the right one half a turn on.
    crankOffset = 0,
  },
  {
    side = -1,
    thigh = "ValveBiped.Bip01_R_Thigh",
    calf = "ValveBiped.Bip01_R_Calf",
    foot = "ValveBiped.Bip01_R_Foot",
    toe = "ValveBiped.Bip01_R_Toe0",
    pedalAttachment = "pedal_R",
    pedalBone = "pedal_R",
    crankOffset = math.pi,
  },
}
local RIDER_ARMS = {
  {
    side = 1,
    upperArm = "ValveBiped.Bip01_L_UpperArm",
    forearm = "ValveBiped.Bip01_L_Forearm",
    hand = "ValveBiped.Bip01_L_Hand",
    finger = "ValveBiped.Bip01_L_Finger2",
    gripAttachment = "grip_L",
    gripBone = "att_grip_L",
  },
  {
    side = -1,
    upperArm = "ValveBiped.Bip01_R_UpperArm",
    forearm = "ValveBiped.Bip01_R_Forearm",
    hand = "ValveBiped.Bip01_R_Hand",
    finger = "ValveBiped.Bip01_R_Finger2",
    gripAttachment = "grip_R",
    gripBone = "att_grip_R",
  },
}

-- Where the handlebar sits in the fist: this far from the wrist towards the middle finger's knuckle.
local GRIP_ALONG_HAND = 0.8
-- Moving the forearm turns the hand too, so the arm is solved again from where the hand ended up.
local ARM_SOLVE_PASSES = 2
-- Knees bend forward, elbows back and down.
local ELBOW_BACK = 0.3

-- In first person the camera sits in the rider's head, so the neck and everything above it is shrunk to almost
-- nothing. Not quite zero, as a degenerate bone matrix can break lighting and anything that inverts it.
local RIDER_NECK_BONE = "ValveBiped.Bip01_Neck1"
local SHRUNK_HEAD_SCALE = Vector(0.0001, 0.0001, 0.0001)

-- Every animated bone turns around its own local Y axis (its head to tail line in Blender), which is what
-- ManipulateBoneAngles calls pitch. The wheels, crank and pedals have that axis pointing left, so positive pitch rolls
-- them forward. The fork's axis is the steering axis pointing up, so positive pitch steers left.
local ANIMATED_BONES = {
  rearWheel = "wheel_rear",
  frontWheel = "wheel_front",
  fork = "fork",
  crank = "crank",
  leftPedal = "pedal_L",
  rightPedal = "pedal_R",
}

local STEERING_AXIS_DEBUG_LENGTH = 30

local cl_interp = GetConVar("cl_interp")
local cl_interp_ratio = GetConVar("cl_interp_ratio")
local cl_updaterate = GetConVar("cl_updaterate")

-- Attachments shown by the debug overlay: the seat and the hand and foot targets.
local DEBUG_ATTACHMENTS = { "seat", "grip_L", "grip_R", "pedal_L", "pedal_R" }

local DEBUG_DISTANCE = 1500
local DEBUG_WHEEL_SEGMENTS = 32
local DEBUG_WHEEL_SPOKES = 4
local DEBUG_LINE_LENGTH = 40
local DEBUG_VELOCITY_SCALE = 0.1
local DEBUG_ATTACHMENT_RADIUS = 1
local EDITOR_MARKER_RADIUS = 1.2
-- Length of the line showing the tilt of the rider's back.
local EDITOR_SPINE_LENGTH = 12

-- Looping sounds fade towards their volume at this rate (1/s), and stop once quieter than the silent volume.
local LOOP_VOLUME_RESPONSE = 8
local LOOP_SILENT_VOLUME = 0.01
-- The freewheel ticks while coasting, faster (higher pitch) the faster the wheel turns. Speeds in u/s.
local FREEWHEEL_MIN_SPEED = 20
local FREEWHEEL_FULL_SPEED = 540
local FREEWHEEL_PITCH_MIN = 60
local FREEWHEEL_PITCH_MAX = 160
local FREEWHEEL_VOLUME_MIN = 0.1
local FREEWHEEL_VOLUME_MAX = 0.5
-- The chain runs while pedalling, higher pitched the faster the cranks turn. Cadences in rpm.
local CHAIN_MIN_CADENCE = 40
local CHAIN_FULL_CADENCE = 120
local CHAIN_PITCH_MIN = 85
local CHAIN_PITCH_MAX = 125
local CHAIN_VOLUME_MIN = 0.8
local CHAIN_VOLUME_MAX = 2
local SKID_PITCH_MIN = 90
local SKID_PITCH_MAX = 110
local SKID_FULL_PITCH_SPEED = 400
-- Only the rider hears the wind, from the min speed up to its loudest at the full speed.
local WIND_MIN_SPEED = 150
local WIND_FULL_SPEED = 700
local WIND_PITCH_MIN = 80
local WIND_PITCH_MAX = 130
local WIND_VOLUME_MAX = 1

local SOUND_LOOPS = {
  freewheel = { path = "bicycle/freewheel_ticking.wav", soundLevel = 65 },
  chain = { path = "bicycle/chain_loop.wav", soundLevel = 65 },
  skid = { path = "bicycle/skid.wav", soundLevel = 75 },
  wind = { path = "bicycle/wind.wav", soundLevel = 0 },
}

function ENT:Initialize()
  self.wheelSpinAngle = 0
  self.crankAngle = 0
  self.soundLoops = {}
  self.soundLoopVolumes = {}
  self.trickAngles = {}
  self.trickSnapshots = {}
  self.restTargetPositions = {}
  self.trickPoseCallback = self:AddCallback("BuildBonePositions", function(entity)
    entity:PoseTricks()
  end)
end

--- The server measures the model on spawn, clients take over its measurements once they arrive.
function ENT:SyncGeometry()
  local wheelRadius = self:GetWheelRadius()

  if (wheelRadius <= 0 or wheelRadius == self.syncedWheelRadius) then
    return
  end

  self.syncedWheelRadius = wheelRadius
  self:ApplyGeometry(self:GetRearHub(), self:GetFrontHub(), wheelRadius)
  -- Measured the same way as on the server, for the bike editor's seat marker.
  self.SeatPosition = self:GetAttachmentLocalPosition(self.SeatAttachment) or self.SeatPosition
end

--- @return table # Bone indices by the keys of `ANIMATED_BONES`, missing bones are left out
function ENT:GetAnimatedBones()
  if (self.animatedBones) then
    return self.animatedBones
  end

  local bones = {}

  for key, boneName in pairs(ANIMATED_BONES) do
    bones[key] = self:LookupBone(boneName)
  end

  self.animatedBones = bones

  return bones
end

--- @return Vector?, Vector? # A point on the steering axis and the axis itself pointing up out of the head tube, in
--- world space. Nil when the model has no fork bone.
function ENT:GetSteeringAxis()
  local fork = self:GetAnimatedBones().fork
  local matrix = fork and self:GetBoneMatrix(fork)

  if (not matrix) then
    return nil, nil
  end

  -- The fork turns around its own local Y axis, which a VMatrix gives as minus its right.
  local axis = -matrix:GetRight()
  axis:Normalize()

  -- Pointing up, so turning around it by positive degrees is counter-clockwise seen from above.
  if (axis:Dot(self:GetUp()) < 0) then
    axis:Mul(-1)
  end

  return matrix:GetTranslation(), axis
end

--- @return number[] # The fork and everything it carries
function ENT:GetForkBones()
  local fork = self:GetAnimatedBones().fork

  if (not fork) then
    return {}
  end

  local bones = { fork }
  table.Add(bones, bicycle.ik.getDescendants(self, fork))

  return bones
end

--- @return boolean # Whether any trick is drawn spun
function ENT:IsDoingTrick()
  return next(self.trickAngles) ~= nil
end

--- @return boolean # Whether a trick that turns the real bike over, such as a flip, is in progress
function ENT:IsRotatingTrick()
  for id in pairs(self.trickAngles) do
    local trick = bicycle.trick.get(id)

    if (trick and trick.rotatesBike) then
      return true
    end
  end

  return false
end

--- @return table # The directions tricks pose the bike and rider by, see TRICK:PoseBike. The steering pivot and axis
--- are nil when the model has no fork bone.
function ENT:GetTrickFrame()
  local angles = self:GetAngles()
  local steeringPivot, steeringAxis = self:GetSteeringAxis()

  return {
    forward = angles:Forward(),
    left = -angles:Right(),
    up = angles:Up(),
    steeringPivot = steeringPivot,
    steeringAxis = steeringAxis,
  }
end

--- @return Vector?
function ENT:GetBoneWorldPosition(boneName)
  return bicycle.ik.getBonePosition(self, self:LookupBone(boneName))
end

--- Lets every trick being spun move the bike's bones. Runs inside the bike's own
--- "BuildBonePositions".
function ENT:PoseTricks()
  if (not self:IsDoingTrick()) then
    return
  end

  bicycle.ik.beginPass(self)

  for _, leg in ipairs(RIDER_LEGS) do
    self.restTargetPositions[leg.pedalBone] = self:GetBoneWorldPosition(leg.pedalBone)
  end

  for _, arm in ipairs(RIDER_ARMS) do
    self.restTargetPositions[arm.gripBone] = self:GetBoneWorldPosition(arm.gripBone)
  end

  local frame = self:GetTrickFrame()

  if (not frame.steeringPivot) then
    return
  end

  for _, trick in ipairs(bicycle.trick.getAll()) do
    local angle = self.trickAngles[trick.id]

    if (angle) then
      trick:PoseBike(self, angle, frame)
    end
  end
end

local function setBonePitch(entity, bone, pitch)
  if (bone) then
    entity:ManipulateBoneAngles(bone, Angle(pitch, 0, 0))
  end
end

--- Spins the wheels, steers the fork and turns the cranks, with the pedals counter-rotating so they stay level.
function ENT:UpdateBones()
  local bones = self:GetAnimatedBones()
  local wheelSpin = math.deg(self.wheelSpinAngle)
  local crankAngle = math.deg(self.crankAngle)

  setBonePitch(self, bones.rearWheel, wheelSpin)
  setBonePitch(self, bones.frontWheel, wheelSpin)
  setBonePitch(self, bones.fork, -self:GetSteer())
  setBonePitch(self, bones.crank, crankAngle)
  setBonePitch(self, bones.leftPedal, -crankAngle)
  setBonePitch(self, bones.rightPedal, -crankAngle)
end

function ENT:Draw()
  self:DrawModel()
end

--- @return ... # The bone index for each name, in the same order, nil when missing
local function lookupBones(entity, ...)
  local names = { ... }
  local bones = {}

  for index, name in ipairs(names) do
    bones[index] = entity:LookupBone(name)
  end

  return unpack(bones, 1, #names)
end

function ENT:GetAttachmentPosition(attachmentName)
  local attachment = self:GetAttachment(self:LookupAttachment(attachmentName))

  return attachment and attachment.Pos
end

--- While a trick is spun, the position of the attachment's bone before any trick moved it. That way the rider's hands
--- and feet don't follow the spinning bars or frame, and each trick moves them itself.
--- @return Vector?
function ENT:GetRiderTargetPosition(attachmentName, boneName)
  return (self:IsDoingTrick() and self.restTargetPositions[boneName]) or self:GetAttachmentPosition(attachmentName)
end

--- @return Vector? # Where the ball of the foot goes: out from the pedal attachment and above its axle
function ENT:GetFootBallTarget(leg, left, up)
  local pedalPosition = self:GetRiderTargetPosition(leg.pedalAttachment, leg.pedalBone)

  return pedalPosition and pedalPosition + left * (leg.side * self.PedalCenterOffset) + up * self.FootBallHeight
end

--- @return Vector? # Where the hand holds: the grip attachment moved by the model's grip offset
function ENT:GetGripTarget(arm, forward, left, up)
  local gripPosition = self:GetRiderTargetPosition(arm.gripAttachment, arm.gripBone)
  local gripOffset = self.GripOffset

  return gripPosition and gripPosition + forward * gripOffset.x + left * (arm.side * gripOffset.y) + up * gripOffset.z
end

--- Plants the ball of the foot on the pedal, with the foot's angle following the pedal stroke (ankling). Tricks being
--- spun can move the foot elsewhere.
function ENT:PoseRiderLeg(rider, leg, frame)
  local forward, left, up = frame.forward, frame.left, frame.up
  local footBall = self:GetFootBallTarget(leg, left, up)
  local thigh, calf, foot, toe = lookupBones(rider, leg.thigh, leg.calf, leg.foot, leg.toe)

  if (not footBall or not thigh or not calf or not foot) then
    return
  end

  for _, trick in ipairs(bicycle.trick.getAll()) do
    local angle = self.trickAngles[trick.id]

    if (angle) then
      footBall = trick:AdjustFootTarget(self, leg, footBall, angle, frame)
    end
  end

  -- The heel drops as the pedal comes over the front and lifts as it goes round the back.
  local pedalAngle = self.crankAngle + leg.crankOffset
  local toeDown = math.rad(
    bicycle.getClientSetting("rider_foot_pitch") - bicycle.getClientSetting("rider_ankling") * math.sin(pedalAngle)
  )
  local footDirection = forward * math.cos(toeDown) - up * math.sin(toeDown)

  local footPosition, toePosition = bicycle.ik.getBonePosition(rider, foot), bicycle.ik.getBonePosition(rider, toe)
  local footLength = (footPosition and toePosition) and footPosition:Distance(toePosition) or 0
  local kneePole = forward + left * (leg.side * bicycle.getClientSetting("rider_knee_out"))

  bicycle.ik.solveLimb(rider, thigh, calf, foot, footBall - footDirection * footLength, kneePole)

  if (footLength > 0) then
    footPosition, toePosition = bicycle.ik.getBonePosition(rider, foot), bicycle.ik.getBonePosition(rider, toe)

    if (footPosition and toePosition) then
      bicycle.ik.aimBone(rider, foot, toePosition - footPosition, footDirection)
    end
  end
end

--- Closes the hand around the grip, keeping the hand's own pose from the rider's sequence. Tricks being spun can move
--- the hand elsewhere.
function ENT:PoseRiderArm(rider, arm, frame)
  local forward, left, up = frame.forward, frame.left, frame.up
  local gripPosition = self:GetGripTarget(arm, forward, left, up)
  local upperArm, forearm, hand, finger = lookupBones(rider, arm.upperArm, arm.forearm, arm.hand, arm.finger)

  if (not gripPosition or not upperArm or not forearm or not hand) then
    return
  end

  for _, trick in ipairs(bicycle.trick.getAll()) do
    local angle = self.trickAngles[trick.id]

    if (angle) then
      gripPosition = trick:AdjustGripTarget(self, arm, gripPosition, angle, frame)
    end
  end

  local elbowPole = left * (arm.side * bicycle.getClientSetting("rider_elbow_out")) - up - forward * ELBOW_BACK

  for _ = 1, ARM_SOLVE_PASSES do
    local handPosition = bicycle.ik.getBonePosition(rider, hand)

    -- Bones the engine skips in this setup pass have no matrix.
    if (not handPosition) then
      return
    end

    local fingerPosition = bicycle.ik.getBonePosition(rider, finger)
    local fistCenter = fingerPosition and LerpVector(GRIP_ALONG_HAND, handPosition, fingerPosition) or handPosition

    bicycle.ik.solveLimb(rider, upperArm, forearm, hand, handPosition + (gripPosition - fistCenter), elbowPole)
  end
end

--- Runs inside the rider's "BuildBonePositions", after their sequence has posed them.
function ENT:PoseRider(rider)
  if (self:GetRider() ~= rider or not bicycle.getClientSettingBool("rider_ik")) then
    return
  end

  local frame = self:GetTrickFrame()

  for _, leg in ipairs(RIDER_LEGS) do
    self:PoseRiderLeg(rider, leg, frame)
  end

  for _, arm in ipairs(RIDER_ARMS) do
    self:PoseRiderArm(rider, arm, frame)
  end
end

--- Moves a bone to `position` and scales it there. Its children are left where they are.
local function shrinkBone(entity, bone, position, scale)
  local matrix = bone and entity:GetBoneMatrix(bone)

  if (matrix) then
    matrix:SetTranslation(position)
    matrix:Scale(scale)
    entity:SetBoneMatrix(bone, matrix)
  end
end

--- Collapses the neck and head, with everything attached to them, while the local rider sees their body in first
--- person. Runs inside the rider's "BuildBonePositions".
function ENT:ShrinkRiderHead(rider)
  -- Skipped while the camera measures where the rider's eyes are, see bicycle.getRiderEyePosition. While the camera
  -- still eases in from the on-foot view it is outside the head, so the head stays until it arrives.
  if (
        self:GetRider() ~= rider
        or rider.bicycleKeepHead
        or not bicycle.isShowingFirstPersonBody(rider)
        or bicycle.isBlendingFromFootView()
      ) then
    return
  end

  local neck = rider:LookupBone(RIDER_NECK_BONE)
  local neckPosition = bicycle.ik.getBonePosition(rider, neck)

  if (not neckPosition) then
    return
  end

  shrinkBone(rider, neck, neckPosition, SHRUNK_HEAD_SCALE)

  for _, descendant in ipairs(bicycle.ik.getDescendants(rider, neck)) do
    shrinkBone(rider, descendant, neckPosition, SHRUNK_HEAD_SCALE)
  end
end

function ENT:StopPosingRider()
  if (IsValid(self.posedRider) and self.riderPoseCallback) then
    self.posedRider:RemoveCallback("BuildBonePositions", self.riderPoseCallback)
    self.posedRider:SetLOD(-1)
  end

  self.posedRider = nil
  self.riderPoseCallback = nil
end

--- Hooks the rider's bone setup whenever someone else gets on.
function ENT:UpdateRiderPose()
  local rider = self:GetRider()

  if (self.posedRider == rider) then
    return
  end

  self:StopPosingRider()

  if (not IsValid(rider)) then
    return
  end

  self.posedRider = rider
  -- Lower detail levels leave bones like the toes and fingers out of the bone setup, and the limbs can't be solved
  -- without them, so the rider would drop back to their plain sitting pose a short way off.
  rider:SetLOD(0)
  self.riderPoseCallback = rider:AddCallback("BuildBonePositions", function(player)
    -- A dormant bike's Think doesn't run, so it can't unhook itself and its rider may be stale.
    if (IsValid(self) and not self:IsDormant()) then
      bicycle.ik.beginPass(player)
      self:PoseRider(player)
      self:ShrinkRiderHead(player)
    end
  end)
end

function ENT:IsWithinDebugDistance()
  return self:GetPos():DistToSqr(EyePos()) < DEBUG_DISTANCE * DEBUG_DISTANCE
end

--- The client traces the wheels itself for the debug overlay, as the server's contacts aren't networked.
function ENT:UpdateDebugWheelContacts()
  if (not bicycle.isDebugEnabled() or not self:IsWithinDebugDistance()) then
    self.debugWheelContacts = nil
    return
  end

  self.debugWheelContacts = self.debugWheelContacts or {}

  for index = 1, #self.Wheels do
    self.debugWheelContacts[index] = self:TraceWheel(index)
  end
end

--- Fades the loop towards `volume`, starting it when it becomes audible and stopping it once silent.
function ENT:UpdateSoundLoop(name, volume, pitch, deltaTime)
  local currentVolume = Lerp(
    1 - math.exp(-LOOP_VOLUME_RESPONSE * deltaTime),
    self.soundLoopVolumes[name] or 0,
    volume
  )
  local loop = self.soundLoops[name]

  self.soundLoopVolumes[name] = currentVolume

  if (currentVolume < LOOP_SILENT_VOLUME) then
    if (loop and loop:IsPlaying()) then
      loop:Stop()
    end

    return
  end

  if (not loop) then
    local settings = SOUND_LOOPS[name]

    loop = CreateSound(self, settings.path)
    loop:SetSoundLevel(settings.soundLevel)
    self.soundLoops[name] = loop
  end

  if (loop:IsPlaying()) then
    loop:ChangeVolume(currentVolume)
    loop:ChangePitch(pitch)
  else
    loop:PlayEx(currentVolume, pitch)
  end
end

function ENT:UpdateSoundLoops(deltaTime)
  local absoluteSpeed = math.abs(self:GetForwardSpeed())
  local isEnabled = bicycle.getTuningBool("sounds")
  local ridingVolume = isEnabled and bicycle.getClientSetting("sound_volume") or 0
  local windVolume = isEnabled and bicycle.getClientSetting("sound_wind") or 0

  -- Pedalling drives the hub, which silences the freewheel.
  local freewheelFraction = math.Clamp(
    (absoluteSpeed - FREEWHEEL_MIN_SPEED) / (FREEWHEEL_FULL_SPEED - FREEWHEEL_MIN_SPEED),
    0,
    1
  )
  local isCoasting = self:GetCadence() == 0 and absoluteSpeed > FREEWHEEL_MIN_SPEED

  self:UpdateSoundLoop(
    "freewheel",
    isCoasting and Lerp(freewheelFraction, FREEWHEEL_VOLUME_MIN, FREEWHEEL_VOLUME_MAX) * ridingVolume or 0,
    Lerp(freewheelFraction, FREEWHEEL_PITCH_MIN, FREEWHEEL_PITCH_MAX),
    deltaTime
  )

  local cadence = self:GetCadence()
  local chainFraction = math.Clamp(
    (cadence - CHAIN_MIN_CADENCE) / (CHAIN_FULL_CADENCE - CHAIN_MIN_CADENCE),
    0,
    1
  )

  self:UpdateSoundLoop(
    "chain",
    cadence > 0 and Lerp(chainFraction, CHAIN_VOLUME_MIN, CHAIN_VOLUME_MAX) * ridingVolume or 0,
    Lerp(chainFraction, CHAIN_PITCH_MIN, CHAIN_PITCH_MAX),
    deltaTime
  )

  self:UpdateSoundLoop(
    "skid",
    self:GetSkid() * ridingVolume,
    Lerp(math.Clamp(absoluteSpeed / SKID_FULL_PITCH_SPEED, 0, 1), SKID_PITCH_MIN, SKID_PITCH_MAX),
    deltaTime
  )

  local windFraction = 0
  local rider = self:GetRider()

  if (IsValid(rider) and rider == LocalPlayer()) then
    windFraction = math.Clamp(
      (self:GetVelocity():Length() - WIND_MIN_SPEED) / (WIND_FULL_SPEED - WIND_MIN_SPEED),
      0,
      1
    )
  end

  self:UpdateSoundLoop(
    "wind",
    windFraction * WIND_VOLUME_MAX * windVolume,
    Lerp(windFraction, WIND_PITCH_MIN, WIND_PITCH_MAX),
    deltaTime
  )
end

--- Also called when the bike leaves the player's view, since Think stops running and would leave the loops playing.
function ENT:StopSoundLoops()
  for name, loop in pairs(self.soundLoops) do
    loop:Stop()
    self.soundLoopVolumes[name] = 0
  end
end

--- @return number # How far behind the server entities are drawn (s), as the engine works it out
local function getInterpolationDelay()
  return math.max(cl_interp:GetFloat(), cl_interp_ratio:GetFloat() / math.max(cl_updaterate:GetFloat(), 1))
end

--- Keeps the trick states the server sent, until the bike is drawn as of when they were sent.
--- @param time number Server time they were sent at
--- @param states table<string, table> `{ angle, speed }` of every trick that isn't straight, by trick id
function ENT:AddTrickSnapshot(time, states)
  self.trickSnapshots[#self.trickSnapshots + 1] = { time = time, states = states }
end

--- Draws tricks as of the moment the bike itself is drawn, so they're in step with its movement. The server sends
--- a trick again once it drifts from its last sent speed, so carrying it on at that speed stays close.
function ENT:UpdateTrickAngles()
  local snapshots = self.trickSnapshots
  local drawTime = CurTime() - getInterpolationDelay()

  -- Only the newest snapshot the bike is drawn past is needed.
  while (snapshots[2] and snapshots[2].time <= drawTime) do
    table.remove(snapshots, 1)
  end

  table.Empty(self.trickAngles)

  local snapshot = snapshots[1]

  if (not snapshot or snapshot.time > drawTime) then
    return
  end

  for id, state in pairs(snapshot.states) do
    local angle = state.angle + state.speed * (drawTime - snapshot.time)

    self.trickAngles[id] = angle ~= 0 and angle or nil
  end
end

function ENT:Think()
  local deltaTime = FrameTime()

  self:SyncGeometry()

  self:UpdateTrickAngles()

  self.wheelSpinAngle = (self.wheelSpinAngle + self:GetForwardSpeed() / self.WheelRadius * deltaTime) % FULL_TURN
  self.crankAngle = (self.crankAngle + self:GetCadence() / 60 * FULL_TURN * deltaTime) % FULL_TURN

  self:UpdateBones()
  self:UpdateRiderPose()
  self:UpdateDebugWheelContacts()
  self:UpdateSoundLoops(deltaTime)

  self:SetNextClientThink(CurTime())
  return true
end

function ENT:OnRemove()
  if (self.trickPoseCallback) then
    self:RemoveCallback("BuildBonePositions", self.trickPoseCallback)
  end

  self:StopPosingRider()
  self:StopSoundLoops()
end

--- Draws the wheels as the ride simulates them, with their spin and steering and where they touch the ground, to
--- compare against the model's own wheels.
function ENT:DrawDebugWheel(index, wheel)
  local colors = bicycle.debugColors
  local radius = self.WheelRadius
  local hubPosition = self:LocalToWorld(wheel.position)
  local wheelAngles = Angle(self:GetAngles())

  if (wheel.isFront) then
    wheelAngles:RotateAroundAxis(wheelAngles:Up(), -self:GetSteer())
  end

  local forward, up = wheelAngles:Forward(), wheelAngles:Up()
  local contact = self.debugWheelContacts and self.debugWheelContacts[index]
  local color = (contact and contact.isGrounded) and colors.grounded or colors.airborne

  local function getRimPoint(angle)
    return hubPosition + forward * (math.cos(angle) * radius) + up * (math.sin(angle) * radius)
  end

  local previousPoint = getRimPoint(0)

  for segment = 1, DEBUG_WHEEL_SEGMENTS do
    local point = getRimPoint(segment / DEBUG_WHEEL_SEGMENTS * FULL_TURN)

    render.DrawLine(previousPoint, point, color, false)
    previousPoint = point
  end

  for spoke = 0, DEBUG_WHEEL_SPOKES - 1 do
    render.DrawLine(hubPosition, getRimPoint(-self.wheelSpinAngle + spoke * FULL_TURN / DEBUG_WHEEL_SPOKES), color, false)
  end

  if (contact and contact.isHit) then
    render.DrawLine(hubPosition, contact.contactPosition, colors.wheelTrace, false)
    render.DrawWireframeSphere(contact.contactPosition, 1.2, 6, 6, color, false)
  end
end

function ENT:DrawDebug()
  local colors = bicycle.debugColors

  for index, wheel in ipairs(self.Wheels) do
    self:DrawDebugWheel(index, wheel)
  end

  for _, attachmentName in ipairs(DEBUG_ATTACHMENTS) do
    local attachment = self:GetAttachment(self:LookupAttachment(attachmentName))

    if (attachment) then
      render.DrawWireframeSphere(attachment.Pos, DEBUG_ATTACHMENT_RADIUS, 6, 6, colors.attachment, false)
    end
  end

  local position = self:GetPos()
  local flatRight = self:GetRight()
  flatRight.z = 0
  flatRight:Normalize()

  local targetLeanRadians = math.rad(self:GetTargetLean())
  local targetUp = vector_up * math.cos(targetLeanRadians) + flatRight * math.sin(targetLeanRadians)

  render.DrawLine(position, position + self:GetUp() * DEBUG_LINE_LENGTH, colors.actualLean, false)
  render.DrawLine(position, position + targetUp * DEBUG_LINE_LENGTH, colors.targetLean, false)
  render.DrawLine(position, position + self:GetVelocity() * DEBUG_VELOCITY_SCALE, colors.velocity, false)

  local steeringPivot, steeringAxis = self:GetSteeringAxis()

  if (steeringPivot) then
    render.DrawLine(
      steeringPivot,
      steeringPivot + steeringAxis * STEERING_AXIS_DEBUG_LENGTH,
      colors.steeringAxis,
      false
    )
  end
end

--- Marks where the model's settings place the rider: the seat with the tilt of the rider's back, and the hand and foot
--- targets.
function ENT:DrawEditorOverlay()
  local colors = bicycle.debugColors
  local angles = self:GetAngles()
  local forward, left, up = angles:Forward(), -angles:Right(), angles:Up()
  local seatPosition = self:LocalToWorld(self:GetSeatOffset())
  local seatUp = self:LocalToWorldAngles(self:GetSeatLocalAngles()):Up()

  render.DrawWireframeSphere(seatPosition, EDITOR_MARKER_RADIUS, 8, 8, colors.editorSeat, false)
  render.DrawLine(seatPosition, seatPosition + seatUp * EDITOR_SPINE_LENGTH, colors.editorSeat, false)

  for _, arm in ipairs(RIDER_ARMS) do
    local target = self:GetGripTarget(arm, forward, left, up)

    if (target) then
      render.DrawWireframeSphere(target, EDITOR_MARKER_RADIUS, 8, 8, colors.editorGrip, false)
    end
  end

  for _, leg in ipairs(RIDER_LEGS) do
    local target = self:GetFootBallTarget(leg, left, up)

    if (target) then
      render.DrawWireframeSphere(target, EDITOR_MARKER_RADIUS, 8, 8, colors.editorFoot, false)
    end
  end
end
