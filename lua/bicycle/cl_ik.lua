-- Inverse kinematics on world space bone matrices, for use inside a "BuildBonePositions" callback. Rotating a bone
-- there doesn't move its children, so every bone below is carried along by hand.

bicycle.ik = bicycle.ik or {}

-- Below this a direction or rotation is too small to aim with.
local EPSILON = 1e-4
-- A limb is never stretched fully straight, where the bend direction flips.
local MAX_REACH_FRACTION = 0.999

-- Per model: `children` by parent bone, and `descendants` lists collected per bone as they're needed.
local skeletonsByModel = {}

local function getSkeleton(entity)
  local model = entity:GetModel()
  local skeleton = skeletonsByModel[model] or entity.bicycleIkPassSkeleton

  if (skeleton) then
    return skeleton
  end

  skeleton = { children = {}, descendants = {} }
  local rootCount = 0

  for bone = 0, entity:GetBoneCount() - 1 do
    local parent = entity:GetBoneParent(bone)

    if (parent and parent >= 0) then
      skeleton.children[parent] = skeleton.children[parent] or {}
      table.insert(skeleton.children[parent], bone)
    else
      rootCount = rootCount + 1
    end
  end

  -- GetBoneParent returns -1 for bones that haven't been set up yet, as with a player that has only just come into
  -- view: all of them at first, or just the fingers after a setup for attachments only. Caching that would leave hands
  -- behind for everyone with the same model, so a skeleton with loose bones is only used for this pass. Some models
  -- really have more than one root bone, so this has to stay cheap: it is built once per pass, not once per bone.
  if (rootCount <= 1) then
    skeletonsByModel[model] = skeleton
  else
    entity.bicycleIkPassSkeleton = skeleton
  end

  return skeleton
end

--- Call at the start of every "BuildBonePositions" pass that uses the functions below, so a skeleton that couldn't be
--- cached is read again for it.
function bicycle.ik.beginPass(entity)
  entity.bicycleIkPassSkeleton = nil
end

local function collectDescendants(children, bone, descendants)
  for _, child in ipairs(children[bone] or {}) do
    descendants[#descendants + 1] = child
    collectDescendants(children, child, descendants)
  end

  return descendants
end

--- @return number[] # Every bone below `bone`
function bicycle.ik.getDescendants(entity, bone)
  local skeleton = getSkeleton(entity)
  local descendants = skeleton.descendants[bone]

  if (not descendants) then
    descendants = collectDescendants(skeleton.children, bone, {})
    skeleton.descendants[bone] = descendants
  end

  return descendants
end

--- @return Vector?
function bicycle.ik.getBonePosition(entity, bone)
  local matrix = bone and entity:GetBoneMatrix(bone)

  return matrix and matrix:GetTranslation()
end

--- Turns `bones` around the line through `pivot` along `axis`. Only the bones listed are moved.
--- @param bones number[]
--- @param pivot Vector World space
--- @param axis Vector World space, normalized
--- @param degrees number Counter-clockwise looking down the axis
function bicycle.ik.rotateAround(entity, bones, pivot, axis, degrees)
  local rotation = Angle(0, 0, 0)
  rotation:RotateAroundAxis(axis, degrees)

  local delta = Matrix()
  delta:Translate(pivot)
  delta:Rotate(rotation)
  delta:Translate(-pivot)

  for _, bone in ipairs(bones) do
    local matrix = entity:GetBoneMatrix(bone)

    if (matrix) then
      entity:SetBoneMatrix(bone, delta * matrix)
    end
  end
end

--- @param point Vector World space
--- @param pivot Vector World space
--- @param axis Vector World space, normalized
--- @param degrees number Counter-clockwise looking down the axis
--- @return Vector # `point` turned around the line through `pivot` along `axis`
function bicycle.ik.rotatePointAround(point, pivot, axis, degrees)
  local rotation = Angle(0, 0, 0)
  rotation:RotateAroundAxis(axis, degrees)

  local offset = point - pivot
  offset:Rotate(rotation)

  return pivot + offset
end

--- Rotates `bone` around its own position by the shortest turn from direction `from` to direction `to`, carrying every
--- bone below it along.
--- @param from Vector World space
--- @param to Vector World space
function bicycle.ik.aimBone(entity, bone, from, to)
  local matrix = entity:GetBoneMatrix(bone)

  if (not matrix or from:LengthSqr() < EPSILON or to:LengthSqr() < EPSILON) then
    return
  end

  local fromNormal, toNormal = from:GetNormalized(), to:GetNormalized()
  local axis = fromNormal:Cross(toNormal)
  local sine = axis:Length()

  -- Already aimed, or exactly opposite where no single axis is better than another.
  if (sine < EPSILON) then
    return
  end

  axis:Div(sine)

  local bones = { bone }
  table.Add(bones, bicycle.ik.getDescendants(entity, bone))

  bicycle.ik.rotateAround(
    entity,
    bones,
    matrix:GetTranslation(),
    axis,
    math.deg(math.atan2(sine, fromNormal:Dot(toNormal)))
  )
end

--- Bends a two bone limb (thigh and calf, upper arm and forearm) so that `endBone` reaches `target`, with the middle
--- joint bending out towards `pole`. Out of reach, the limb points at the target nearly straight.
--- @param target Vector World space
--- @param pole Vector World space direction the knee or elbow should point
--- @return boolean # False when a bone is missing
function bicycle.ik.solveLimb(entity, upperBone, middleBone, endBone, target, pole)
  local root = bicycle.ik.getBonePosition(entity, upperBone)
  local joint = bicycle.ik.getBonePosition(entity, middleBone)
  local tip = bicycle.ik.getBonePosition(entity, endBone)

  if (not root or not joint or not tip) then
    return false
  end

  local upperLength, lowerLength = root:Distance(joint), joint:Distance(tip)
  local toTarget = target - root
  local distance = toTarget:Length()

  if (distance < EPSILON or upperLength < EPSILON or lowerLength < EPSILON) then
    return true
  end

  local direction = toTarget / distance
  distance = math.Clamp(
    distance,
    math.abs(upperLength - lowerLength) + EPSILON,
    (upperLength + lowerLength) * MAX_REACH_FRACTION
  )

  -- The bend happens in the plane through the limb and the pole, falling back to the plane the animation bent it in.
  local bend = pole - direction * pole:Dot(direction)

  if (bend:LengthSqr() < EPSILON) then
    local currentBend = joint - root
    bend = currentBend - direction * currentBend:Dot(direction)
  end

  bend:Normalize()

  -- Law of cosines for the angle between the upper bone and the line to the target.
  local cosine = math.Clamp(
    (upperLength * upperLength + distance * distance - lowerLength * lowerLength) / (2 * upperLength * distance),
    -1,
    1
  )
  local jointTarget = root + direction * (upperLength * cosine) + bend * (upperLength * math.sqrt(1 - cosine * cosine))

  bicycle.ik.aimBone(entity, upperBone, joint - root, jointTarget - root)

  local newJoint = bicycle.ik.getBonePosition(entity, middleBone)
  local newTip = bicycle.ik.getBonePosition(entity, endBone)
  bicycle.ik.aimBone(entity, middleBone, newTip - newJoint, target - newJoint)

  return true
end
