AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Bike Guide"
ENT.Category = bicycle.SPAWN_CATEGORY
ENT.Spawnable = true
ENT.Instructions = "Use it to read how to ride and do tricks"
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Model = "models/props_lab/binderredlabel.mdl"
ENT.IconOverride = "entities/bicycle_guide.png"

-- The label above the binder shows from this close (units), fading in over the last stretch.
local LABEL_DISTANCE = 200
local LABEL_FADE_DISTANCE = 60
local LABEL_HEIGHT = 12
local LABEL_SCALE = 0.1
local LABEL_TITLE = "BIKE GUIDE"
local LABEL_HINT = "Press [+use] to read"
local LABEL_SPACING = 6

if (SERVER) then
  util.AddNetworkString("bicycle.OpenGuide")

  function ENT:Initialize()
    self:SetModel(self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local physics = self:GetPhysicsObject()

    if (IsValid(physics)) then
      physics:Wake()
    end
  end

  function ENT:Use(activator)
    if (not IsValid(activator) or not activator:IsPlayer()) then
      return
    end

    net.Start("bicycle.OpenGuide")
    net.Send(activator)
  end
end

if (CLIENT) then
  net.Receive("bicycle.OpenGuide", function()
    bicycle.guide.open()
  end)

  function ENT:Draw()
    self:DrawModel()
  end

  --- A label above the binder, turned to face whoever is looking at it.
  function ENT:DrawTranslucent()
    local position = self:WorldSpaceCenter()
    local distance = EyePos():Distance(position)

    if (distance > LABEL_DISTANCE) then
      return
    end

    local colors, fonts = bicycle.guide.COLORS, bicycle.guide.FONTS
    local hintTokens = bicycle.guide.parseKeys(LABEL_HINT)
    local hintWidth = bicycle.guide.getKeysWidth(hintTokens)

    position.z = position.z + LABEL_HEIGHT

    cam.Start3D2D(position, Angle(0, EyeAngles().y - 90, 90), LABEL_SCALE)
    surface.SetAlphaMultiplier(math.Clamp((LABEL_DISTANCE - distance) / LABEL_FADE_DISTANCE, 0, 1))

    draw.SimpleText(LABEL_TITLE, fonts.chapter, 3, 3, colors.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(LABEL_TITLE, fonts.chapter, 0, 0, colors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    bicycle.guide.drawKeys(hintTokens, -hintWidth * 0.5, LABEL_SPACING, colors.text)

    surface.SetAlphaMultiplier(1)
    cam.End3D2D()
  end
end
