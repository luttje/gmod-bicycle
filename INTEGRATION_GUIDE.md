# Integrating with Gmod Bicycle

This guide is for addon and gamemode developers. It covers adding your own bikes, tricks and guide chapters, and the
hooks that let your code react to bikes. For riding, settings and installing, see the [README](README.md).

## Adding your own bikes
Other addons can add their own bike models. Each one gets its own entry in the spawn menu. Register it from a shared
`lua/autorun/` file:

```lua
AddCSLuaFile()

hook.Add("BicycleRegisterModels", "myaddon.bike", function()
  bicycle.registerModel("mybike", {
    name = "My Bike",
    model = "models/myname/bicycle.mdl",
    seatOffset = Vector(-8, 0, 1), -- rider position relative to the "seat" attachment
    seatPitch = 50,                -- how far the rider leans forward (deg)
  })
end)
```

- Every setting a model can have is listed in [`lua/bicycle/sh_models.lua`](lua/bicycle/sh_models.lua).
- To line up the rider's seat, hands and feet by eye, ride or look at your bike and run `bicycle_editor` (admins). It
  gives you the matching `bicycle.registerModel` call to copy.
- [📚 `MODELING_GUIDE.md`](MODELING_GUIDE.md) explains how to build a model that works with the addon.
- With `developer 1`, a debug overlay shows the simulated wheels and the model's attachments.

## Adding your own tricks
Every trick is a file in `lua/bicycle/tricks/`. The addon loads every file in that folder on the server and the
client, so another addon can add a trick by putting a file there too. A trick is an angle the server moves on from the
rider's input, which the rider has to land near a whole turn:

```lua
-- lua/bicycle/tricks/myaddon_tabletop.lua
local TRICK = {}

TRICK.id = "myaddon_tabletop"
TRICK.name = "Tabletop"
-- Shown in the bike guide. Bracketed binds are drawn as the key the player has bound to them
TRICK.keys = "[+duck] + [+forward]"
TRICK.description = "Lays the bike flat beneath you. Lasts as long as you hold it."
-- Which wheels may touch the ground during the trick: "none", "rear", "front" and/or "both"
TRICK.contact = { none = true }

-- Server: which way to drive the trick (1, -1, or 0 to let it finish), and whether it takes the steering
function TRICK:ReadInput(input, rider, state)
  return (input.isTrickHeld and input.isPedalHeld) and 1 or 0, false
end

-- Server: hold the pose half a turn in while driven, see also bicycle.trick.spin for whole turns
function TRICK:Spin(state, isDriven, direction, deltaTime)
  bicycle.trick.hold(state, isDriven, direction, 700, deltaTime)
end

if (CLIENT) then
  -- Moves the bike's bones, with `frame` holding the bike's directions and steering axis
  function TRICK:PoseBike(bike, angle, frame)
  end
end

bicycle.trick.register(TRICK)
```

A trick can also apply forces to the bike (`Simulate`), judge its own landing (`Land`), turn the real bike over
(`rotatesBike`), move the rider's hands and feet (`AdjustGripTarget`, `AdjustFootTarget`) and carry the passenger
along when it turns the frame (`GetFrameRotation`). All of it is documented
in [`lua/bicycle/metatables/sh_base_trick.lua`](lua/bicycle/metatables/sh_base_trick.lua). The built-in tricks are
complete examples, such as the [tailwhip](lua/bicycle/tricks/tailwhip.lua), the [backflip](lua/bicycle/tricks/backflip.lua)
and the [no-hander](lua/bicycle/tricks/no_hander.lua).

To give tricks more controls, add fields to the rider's input with the [`BicycleReadInput`](#tricks) hook.

Every registered trick gets its own card in the **Tricks** chapter of the bike guide, showing its `name`, `keys` and
`description`. The card says where the trick can be done, such as in the air or in a wheelie, based on its `contact`.

## Adding your own guide chapters
Using the **Bike Guide** binder (or running `bicycle_guide`) opens a window of chapters on riding. Each chapter is a
`cl_` file in `lua/bicycle/guide/`, and the addon loads every file in that folder on the client, so another addon can
add a chapter by putting a file there too:

```lua
-- lua/bicycle/guide/cl_myaddon_grinds.lua
bicycle.guide.registerChapter({
  id = "myaddon_grinds",
  title = "Grinds",
  -- Chapters are sorted by this. The built-in ones are 10, 20, 30, 40 and 50
  order = 45,
  -- A list of blocks, or a function returning one that runs each time the chapter is shown
  content = {
    "A plain string is a paragraph of text.",
    { type = "heading", text = "Rails" },
    { type = "controls", rows = { { "[+use]", "Grind the rail you're on" } } },
    { type = "tip", text = "Grinds combine with tricks." },
    { type = "card", title = "Feeble", tag = "on a rail", keys = "[+duck]", text = "Hangs the front wheel over." },
  },
})
```

Text in brackets in `keys` is drawn as a keycap. A bracketed bind such as `[+forward]` is drawn as whichever key the
player has bound to it. To add a block type of your own, call `bicycle.guide.registerBlockType(name, build)`, where
`build(parent, block)` adds the block's panels to `parent`, docked to the top. The built-in block types are in
[`lua/bicycle/cl_guide.lua`](lua/bicycle/cl_guide.lua), and the built-in chapters in
[`lua/bicycle/guide/`](lua/bicycle/guide/).

## Hooks
These hooks let gamemodes and other addons react to bikes. They run on the server, except for the HUD one.

### Getting on and off
`BicycleCanMount` runs when a player presses **E** on a bike. Return `false` to keep them off it:

```lua
--- @param player Player The player trying to get on
--- @param bike Entity The bike
--- @param isPassenger boolean? True when they get on as the passenger, on bikes with a passenger seat
--- @return boolean? Return false to keep the player off the bike
hook.Add("BicycleCanMount", "myaddon.mount", function(player, bike, isPassenger)
end)
```

For example, to keep tied up players off bikes in a [Helix](https://github.com/NebulousCloud/helix) schema:

```lua
hook.Add("BicycleCanMount", "myschema.bicycleRestricted", function(client, bike)
  if (client:IsRestricted()) then
    return false
  end
end)
```

Once a player is on or off the bike, `BicycleRiderMounted` and `BicycleRiderDismounted` run:

```lua
--- @param player Player The rider
--- @param bike Entity The bike
hook.Add("BicycleRiderMounted", "myaddon.mounted", function(player, bike)
end)

--- @param player Player The rider
--- @param bike Entity The bike
--- @param isCrash boolean Whether they were thrown off in a crash, see BicycleRiderCrashed
hook.Add("BicycleRiderDismounted", "myaddon.dismounted", function(player, bike, isCrash)
end)
```

Passengers get `BicyclePassengerMounted` and `BicyclePassengerDismounted` instead. A crash throws the passenger off
too:

```lua
--- @param player Player The passenger
--- @param bike Entity The bike
hook.Add("BicyclePassengerMounted", "myaddon.passengerMounted", function(player, bike)
end)

--- @param player Player The passenger
--- @param bike Entity The bike
hook.Add("BicyclePassengerDismounted", "myaddon.passengerDismounted", function(player, bike)
end)
```

To keep a rider from getting off, use GMod's own `CanExitVehicle` hook. `bicycle.getFromSeat(vehicle)` returns the bike
when the vehicle is a bike's seat:

```lua
hook.Add("CanExitVehicle", "myaddon.stayOnBike", function(vehicle, player)
  if (bicycle.getFromSeat(vehicle)) then
    return false
  end
end)
```

### Crashing
`BicycleShouldCrash` runs when a bike hits something hard enough, tips too far, ends up lying on its frame or rides
into water that's too deep. Return `false` to keep the rider on the bike. While the bike stays tipped over, lying down
or in deep water, this runs every tick, so keep it cheap:

```lua
--- @param bike Entity The bike
--- @param rider Player The rider
--- @return boolean? Return false to stop the crash
hook.Add("BicycleShouldCrash", "myaddon.noCrash", function(bike, rider)
  if (rider:HasGodMode()) then
    return false
  end
end)
```

When a rider flies over the handlebars, the server runs the `BicycleRiderCrashed` hook once they're off the bike, just
before they're thrown. When RagMod is installed and enabled, and the
`bicycle_ragmod_crash` setting is on (the default), they're thrown as a RagMod ragdoll. Return `false` to keep them from
being thrown, for example to throw them your own way:

```lua
--- @param player Player The rider that crashed
--- @param bike Entity The bike they crashed with
--- @param velocity Vector The velocity the rider is about to be thrown with
--- @return boolean? Return false to stop the default throw behaviour and handle it yourself
hook.Add("BicycleRiderCrashed", "myaddon.crash", function(player, bike, velocity)
  player:SetVelocity(velocity * 2)

  return false
end)
```

For example, to knock riders out for 10 seconds in a [Helix](https://github.com/NebulousCloud/helix) schema, put this
in a server-side plugin or schema file:

```lua
hook.Add("BicycleRiderCrashed", "myschema.bicycleKnockout", function(client, bike, velocity)
  client:SetRagdolled(true, 10)
end)
```

### Bell
`BicycleCanRingBell` runs when a rider presses **R** to ring the bell, after the server's **Sounds** settings allow
it. Return `false` to keep the bell silent:

```lua
--- @param bike Entity The bike
--- @param rider Player The rider ringing the bell
--- @return boolean? Return false to keep the bell from ringing
hook.Add("BicycleCanRingBell", "myaddon.quietBell", function(bike, rider)
  if (rider:Team() == TEAM_MUTED) then
    return false
  end
end)
```

### Tricks
`BicycleReadInput` runs on the server every physics tick while the bike is ridden. Add or change fields of `input` to
give tricks (`TRICK:ReadInput`) more controls. It runs often, so keep it cheap:

```lua
--- @param rider Player The rider
--- @param bike Entity The bike
--- @param input table The rider's input, see ENT:ReadRiderInput in lua/entities/sent_bicycle/sv_ride.lua
hook.Add("BicycleReadInput", "myaddon.grab", function(rider, bike, input)
  input.isGrabHeld = rider:KeyDown(IN_USE)
end)
```

When a rider lands tricks cleanly, the server runs `BicycleTrickLanded` with the whole turns of each trick by its id.
Tricks landed without a whole turn are left out:

```lua
--- @param rider Player The rider
--- @param bike Entity The bike
--- @param landedTricks table<string, number> Whole turns by trick id, such as { backflip = 1, no_hander = 1 }
hook.Add("BicycleTrickLanded", "myaddon.score", function(rider, bike, landedTricks)
  for id, turns in pairs(landedTricks) do
    rider:ChatPrint(bicycle.trick.get(id).name .. " x" .. turns)
  end
end)
```

### HUD
On the client, the speedometer and the landed tricks check GMod's own `HUDShouldDraw` hook with the names
`BicycleSpeedometer` and `BicycleTricks`, so a gamemode with its own HUD can hide them:

```lua
hook.Add("HUDShouldDraw", "myaddon.hideBicycleHud", function(name)
  if (name == "BicycleSpeedometer" or name == "BicycleTricks") then
    return false
  end
end)
```
