-- Speed per unit/s for each bicycle_hud_speed_unit, 1 unit is 1.905 cm. Any other unit hides the speedometer.
local SPEED_UNIT_SCALES = {
  ["km/h"] = 0.06858,
  ["kmh"] = 0.06858,
  ["mp/h"] = 0.042613,
  ["mph"] = 0.042613,
  ["units"] = 1,
}

-- Handlebar angle (deg) at which the arms are at full "vehicle_steer" lock.
local FULL_ARM_STEER_ANGLE = 25

local CAMERA_HULL_MINS = Vector(-4, -4, -4)
local CAMERA_HULL_MAXS = Vector(4, 4, 4)
-- The on-foot view is only blended from when it was seen this recently.
local MAX_FOOT_VIEW_AGE = 0.5
-- How far (deg) a rider that sees their own body can look away from straight ahead. Looking down goes further, to see
-- the pedals over the handlebar. Positive pitch looks down.
local BODY_LOOK_MAX_YAW = 120
local BODY_LOOK_MIN_PITCH = -60
local BODY_LOOK_MAX_PITCH = 80

local LEAN_GAUGE_LENGTH = 60
local LEAN_GAUGE_MARKERS = { -45, 0, 45 }
local DEBUG_PANEL_LINE_HEIGHT = 14
local DEBUG_PANEL_BACKGROUND = Color(0, 0, 0, 170)
local CONTROL_HINTS = {
  "W pedal   S brake/back   A/D steer",
  "SHIFT sprint   SPACE hop   MOUSE2 wheelie",
  "MOUSE1 lean forward (brake to stoppie)",
  "CTRL camera   R bell   E get off",
}

local function getLocalPlayerBicycle()
  return bicycle.getFromSeat(LocalPlayer():GetVehicle())
end

--- @return Entity? # The bicycle the local player rides, or else the one they look at
function bicycle.findLocalBicycle()
  local bike = getLocalPlayerBicycle() or LocalPlayer():GetEyeTrace().Entity

  return (IsValid(bike) and bike.IsBicycle) and bike or nil
end

--- @return boolean # Whether `player` is the local player, riding in first person with bicycle_cam_body on
function bicycle.isShowingFirstPersonBody(player)
  if (player ~= LocalPlayer() or GetViewEntity() ~= player or not bicycle.getClientSettingBool("cam_body")) then
    return false
  end

  local vehicle = player:GetVehicle()

  return bicycle.getFromSeat(vehicle) ~= nil and not vehicle:GetThirdPersonMode()
end

--- Where the rider's playermodel has its eyes this frame. The seat's own eye position doesn't follow the rider leaning
--- over the handlebar, which would put the camera inside their chest when the body is drawn. The bones are set up
--- once with the head kept to measure this, then again for drawing with the head shrunk away.
--- @return Vector?
function bicycle.getRiderEyePosition(player)
  local eyesAttachment = player:LookupAttachment("eyes")

  if (not eyesAttachment or eyesAttachment <= 0) then
    return nil
  end

  player.bicycleKeepHead = true
  player:InvalidateBoneCache()
  player:SetupBones()

  local eyes = player:GetAttachment(eyesAttachment)

  player.bicycleKeepHead = nil
  player:InvalidateBoneCache()

  return eyes and eyes.Pos
end

local function formatVector(vector)
  return string.format("(%6.2f %6.2f %6.2f)", vector.x, vector.y, vector.z)
end

-- Prints every bone of the bicycle you ride or look at, with its position and axes in the bike's own space. The
-- animated bones should turn around their Y axis.
concommand.Add("bicycle_print_bones", function()
  local bike = bicycle.findLocalBicycle()

  if (not bike) then
    print("[bicycle] Ride or look at a bicycle first.")
    return
  end

  bike:SetupBones()
  print(string.format("[bicycle] %s, wheel radius %.2f, wheelbase %.2f", bike:GetModel(), bike.WheelRadius,
    bike.Wheelbase))

  for bone = 0, bike:GetBoneCount() - 1 do
    local matrix = bike:GetBoneMatrix(bone)

    if (matrix) then
      local position = matrix:GetTranslation()
      local localPosition = bike:WorldToLocal(position)

      local function toLocalDirection(direction)
        return bike:WorldToLocal(position + direction) - localPosition
      end

      print(string.format(
        "%2d %-12s pos %s  X %s  Y %s  Z %s",
        bone,
        bike:GetBoneName(bone),
        formatVector(localPosition),
        formatVector(toLocalDirection(matrix:GetForward())),
        -- A matrix's "right" is its negated Y axis.
        formatVector(toLocalDirection(-matrix:GetRight())),
        formatVector(toLocalDirection(matrix:GetUp()))
      ))
    end
  end
end)

hook.Add("PrePlayerDraw", "bicycle.armSteer", function(player)
  local bike = bicycle.getFromSeat(player:GetVehicle())

  if (not bike) then
    return
  end

  player:SetPoseParameter("vehicle_steer", math.Clamp(bike:GetSteer() / FULL_ARM_STEER_ANGLE, -1, 1))
end)

-- Where the local player looked from while on foot, and when they got on the bike they now ride.
local footView = nil
local mountedSeat = nil
local mountedAt = 0
local isBlendingFromFootView = false

-- The heading, slope and lean the camera follows, trailing the bike's by bicycle_cam_smooth.
local smoothedBike = nil
local smoothedHeading = { pitch = 0, yaw = 0, lean = 0 }
local smoothedFrame = -1

hook.Add("Think", "bicycle.trackFootView", function()
  local player = LocalPlayer()

  if (not IsValid(player) or player:InVehicle()) then
    return
  end

  mountedSeat = nil
  isBlendingFromFootView = false
  smoothedBike = nil
  footView = {
    origin = player:EyePos(),
    angles = player:EyeAngles(),
    seenAt = RealTime(),
  }
end)

-- A bike's Think stops once it leaves the player's view, so its looping sounds would keep playing.
hook.Add("NotifyShouldTransmit", "bicycle.stopSoundLoops", function(entity, shouldTransmit)
  if (not shouldTransmit and entity.IsBicycle and entity.soundLoops) then
    entity:StopSoundLoops()
  end
end)

local function lerpAngleShortest(fraction, from, to)
  return Angle(
    from.p + math.AngleDifference(to.p, from.p) * fraction,
    from.y + math.AngleDifference(to.y, from.y) * fraction,
    from.r + math.AngleDifference(to.r, from.r) * fraction
  )
end

--- Eases the camera from the on-foot view into `cameraView` right after getting on, like Source's own vehicles do.
local function blendFromFootView(vehicle, cameraView)
  if (mountedSeat ~= vehicle) then
    mountedSeat = vehicle
    mountedAt = RealTime()
  end

  isBlendingFromFootView = false

  local blendTime = bicycle.getClientSetting("cam_mount_blend")

  if (blendTime <= 0 or not footView or mountedAt - footView.seenAt > MAX_FOOT_VIEW_AGE) then
    return
  end

  local fraction = (RealTime() - mountedAt) / blendTime

  if (fraction >= 1) then
    return
  end

  isBlendingFromFootView = true
  fraction = math.ease.InOutSine(fraction)
  cameraView.origin = LerpVector(fraction, footView.origin, cameraView.origin)
  cameraView.angles = lerpAngleShortest(fraction, footView.angles, cameraView.angles)
end

--- @return boolean # Whether the local player's camera is still easing into the riding view after getting on
function bicycle.isBlendingFromFootView()
  return isBlendingFromFootView
end

--- Heading, slope pitch and lean are smoothed apart from each other: averaging the bike's angles as a whole mixes the
--- lean into pitch and yaw while leaned over, which makes the camera wobble through a turn.
local function updateSmoothedHeading(bike)
  local forward = bike:GetForward()
  local forwardAngles = forward:Angle()
  local lean = bike:GetLean()

  if (smoothedBike ~= bike) then
    smoothedBike = bike
    smoothedHeading.pitch, smoothedHeading.yaw, smoothedHeading.lean = forwardAngles.p, forwardAngles.y, lean

    return
  end

  -- The view can be calculated more than once per frame, but should only move on once.
  if (smoothedFrame == FrameNumber()) then
    return
  end

  smoothedFrame = FrameNumber()

  local smoothTime = bicycle.getClientSetting("cam_smooth")
  local fraction = smoothTime > 0 and 1 - math.exp(-FrameTime() / smoothTime) or 1

  smoothedHeading.pitch = smoothedHeading.pitch + math.AngleDifference(forwardAngles.p, smoothedHeading.pitch) * fraction
  smoothedHeading.yaw = smoothedHeading.yaw + math.AngleDifference(forwardAngles.y, smoothedHeading.yaw) * fraction
  smoothedHeading.lean = Lerp(fraction, smoothedHeading.lean, lean)
end

--- The rider's mouse look as pitch and yaw away from straight ahead. It is read from the seat, but without the seat's
--- own tilt: the seat is pitched forward to lean the rider over the handlebar, and looking around in that tilted frame
--- rolls the horizon.
--- @return Angle
local function getRiderLook(bike, vehicle, viewAngles)
  local _, eyeAngles = WorldToLocal(vector_origin, viewAngles, vector_origin, vehicle:GetAngles())
  local forward = bike.SeatForwardEyeAngles

  return Angle(eyeAngles.p - forward.p, math.AngleDifference(eyeAngles.y, forward.y), 0)
end

--- Keeps a look, as pitch and yaw away from straight ahead, within what a neck can turn.
--- @return Angle
local function clampBodyLook(look)
  return Angle(
    math.Clamp(look.p, BODY_LOOK_MIN_PITCH, BODY_LOOK_MAX_PITCH),
    math.Clamp(look.y, -BODY_LOOK_MAX_YAW, BODY_LOOK_MAX_YAW),
    0
  )
end

-- A rider that sees their own body can't look behind them, where they'd see their neck and shrunken head. Their eye
-- angles are relative to the seat, so they're clamped around the seat's straight ahead. Clamping the input itself
-- rather than just the view means there's no dead zone to turn back through.
hook.Add("CreateMove", "bicycle.limitBodyLook", function(cmd)
  local player = LocalPlayer()

  if (not bicycle.isShowingFirstPersonBody(player)) then
    return
  end

  local forward = bicycle.getFromSeat(player:GetVehicle()).SeatForwardEyeAngles
  local viewAngles = cmd:GetViewAngles()
  local look = Angle(viewAngles.p - forward.p, math.AngleDifference(viewAngles.y, forward.y), 0)
  local clampedLook = clampBodyLook(look)

  if (clampedLook ~= look) then
    cmd:SetViewAngles(Angle(forward.p + clampedLook.p, forward.y + clampedLook.y, viewAngles.r))
  end
end)

--- The view follows the seat, so it turns, pitches and rolls as abruptly as the bike does. This puts the rider's own
--- look onto a calmer frame instead: the smoothed heading and slope, with only bicycle_cam_roll of the smoothed lean.
--- With bicycle_cam_level only the heading is left.
--- @return Angle
local function getSmoothedViewAngles(bike, vehicle, viewAngles)
  updateSmoothedHeading(bike)

  local frame = Angle(0, smoothedHeading.yaw, 0)

  if (not bicycle.getClientSettingBool("cam_level")) then
    frame.p = smoothedHeading.pitch
    frame.r = smoothedHeading.lean * bicycle.getClientSetting("cam_roll")
  end

  local look = getRiderLook(bike, vehicle, viewAngles)

  -- The input is already limited, this only covers the view being calculated before it.
  if (bicycle.isShowingFirstPersonBody(LocalPlayer())) then
    look = clampBodyLook(look)
  end

  local _, smoothedViewAngles = LocalToWorld(vector_origin, look, vector_origin, frame)

  return smoothedViewAngles
end

hook.Add("CalcVehicleView", "bicycle.camera", function(vehicle, player, view)
  local bike = bicycle.getFromSeat(vehicle)

  -- Looking through something else, like a camera.
  if (not bike or GetViewEntity() ~= player) then
    return
  end

  local angles = getSmoothedViewAngles(bike, vehicle, view.angles)

  local fullFovBoostSpeed = math.max(bicycle.getTuning("sprint_speed"), 1)
  local fovBoostFraction = math.Clamp(math.abs(bike:GetForwardSpeed()) / fullFovBoostSpeed, 0, 1)
  local cameraView = {
    origin = view.origin,
    angles = angles,
    fov = view.fov + fovBoostFraction * bicycle.getClientSetting("cam_fov_boost"),
    drawviewer = bicycle.isShowingFirstPersonBody(player),
  }

  if (vehicle:GetThirdPersonMode()) then
    local pivot = bike:GetPos() + vector_up * bicycle.getClientSetting("cam_height")
    local distance = bicycle.getClientSetting("cam_dist") * (1 + vehicle:GetCameraDistance())
    local trace = util.TraceHull({
      start = pivot,
      endpos = pivot - angles:Forward() * distance,
      mins = CAMERA_HULL_MINS,
      maxs = CAMERA_HULL_MAXS,
      filter = { bike, vehicle, player },
      mask = MASK_SOLID_BRUSHONLY,
    })

    cameraView.origin = trace.HitPos
    cameraView.drawviewer = true
  elseif (cameraView.drawviewer) then
    cameraView.origin = bicycle.getRiderEyePosition(player) or cameraView.origin
  end

  blendFromFootView(vehicle, cameraView)

  return cameraView
end)

local function drawLeanGaugeSpoke(x, y, lean, color)
  local radians = math.rad(lean)

  surface.SetDrawColor(color)
  surface.DrawLine(x, y, x + math.sin(radians) * LEAN_GAUGE_LENGTH, y - math.cos(radians) * LEAN_GAUGE_LENGTH)
end

local function drawLeanGauge(bike, x, y)
  local colors = bicycle.debugColors

  for _, markerLean in ipairs(LEAN_GAUGE_MARKERS) do
    drawLeanGaugeSpoke(x, y, markerLean, colors.marker)
  end

  drawLeanGaugeSpoke(x, y, bike:GetTargetLean(), colors.targetLean)
  drawLeanGaugeSpoke(x, y, bike:GetLean(), colors.actualLean)
end

local function describeWheelContact(contact)
  if (not contact) then
    return "?"
  end

  return contact.isGrounded and string.format("down %4.1f", contact.compression) or "air      "
end

local function drawDebugPanel(bike, speed)
  local wheelContacts = bike.debugWheelContacts or {}
  local lines = {
    string.format("speed    %5.0f u/s", speed),
    string.format("lean     %5.1f   target %5.1f", bike:GetLean(), bike:GetTargetLean()),
    string.format("steer    %5.1f deg", bike:GetSteer()),
    string.format("cadence  %5.0f rpm", bike:GetCadence()),
    string.format("rear %s   front %s", describeWheelContact(wheelContacts[1]), describeWheelContact(wheelContacts[2])),
    "",
  }

  for _, hint in ipairs(CONTROL_HINTS) do
    lines[#lines + 1] = hint
  end

  local x, y = 24, ScrH() * 0.45

  draw.RoundedBox(4, x - 10, y - 10, 290, #lines * DEBUG_PANEL_LINE_HEIGHT + 20, DEBUG_PANEL_BACKGROUND)

  for index, line in ipairs(lines) do
    draw.SimpleText(line, "BudgetLabel", x, y + (index - 1) * DEBUG_PANEL_LINE_HEIGHT, color_white)
  end
end

hook.Add("HUDPaint", "bicycle.hud", function()
  local bike = getLocalPlayerBicycle()

  if (not bike) then
    return
  end

  local speed = bike:GetForwardSpeed()
  local centerX, speedometerY = ScrW() * 0.5, ScrH() - 90

  local speedUnit = bicycle.getClientSettingString("hud_speed_unit")
  local speedUnitScale = SPEED_UNIT_SCALES[speedUnit]

  -- Gamemodes with their own HUD can hide the speedometer like any other HUD element.
  if (speedUnitScale and hook.Run("HUDShouldDraw", "BicycleSpeedometer") ~= false) then
    draw.SimpleTextOutlined(
      string.format("%d %s", math.Round(math.abs(speed) * speedUnitScale), speedUnit),
      "DermaLarge",
      centerX,
      speedometerY,
      color_white,
      TEXT_ALIGN_CENTER,
      TEXT_ALIGN_CENTER,
      2,
      color_black
    )
  end

  if (not bicycle.isDebugEnabled()) then
    return
  end

  drawLeanGauge(bike, centerX, speedometerY - 30)
  drawDebugPanel(bike, speed)
end)

hook.Add("PostDrawTranslucentRenderables", "bicycle.debugOverlay", function(_, isDrawingSkybox)
  if (isDrawingSkybox or not bicycle.isDebugEnabled()) then
    return
  end

  -- Every registered model is its own class derived from the bicycle entity.
  for _, bike in ipairs(ents.FindByClass(bicycle.ENTITY_CLASS .. "_*")) do
    if (bike:IsWithinDebugDistance()) then
      bike:DrawDebug()
    end
  end
end)
