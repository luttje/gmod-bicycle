# Making your own bike for Gmod Bicycle

This guide walks you through turning a bike model into one that works with the addon: spinning wheels, a steering handlebar, and turning pedals. The addon finds everything by **bone name**, so as long as you follow the names and rules below, your bike just works. The only code you need is a few lines that register your model with the addon (step 9).

## What you need

- **Blender** with [the **Blender Source Tools** add-on](https://developer.valvesoftware.com/wiki/Blender_Source_Tools) (exports `.smd` files)
- [**Crowbar**](https://developer.valvesoftware.com/wiki/Crowbar) (compiles your model into a `.mdl` for Garry's Mod)
- [**VTFEdit**](https://github.com/NeilJed/VTFLib) (converts your textures to Source's `.vtf` format)
- A bike model. If you download one (for example from Sketchfab), **check the license**: CC-BY means you must credit the author, and "NC" (non-commercial) licenses may limit where you can use it.

---

## 1. Clean up and orient the model

1. Delete everything that isn't the bike: ground planes, lights, stands.
2. Keep it reasonably light: about **5,000–15,000 triangles**. The spokes are usually the heaviest part. Use a Decimate modifier on them, or replace them with a flat disc and a transparent spoke texture.
3. Keep the model at **real-world size, in meters**. Don't scale it up; the compile step does that for you.
4. Rotate the bike so it faces the right way:
   - **Front points to +X** (the way the red X dot points in Blender's 3D View)
   - **Up is +Z**
   - That makes **left +Y** and right −Y.
5. Put the **origin (0,0,0) in the middle of the frame**.
6. Select everything and press **Ctrl+A → All Transforms**.

## 2. Split the bike into parts

Every part that moves needs to be its own object. Select its faces in Edit mode and press **P → Selection**.

| Object | Contains |
|---|---|
| Frame | frame, saddle, chain, derailleur: everything that never moves |
| Handle | handlebar + fork, plus the front brake, front mudguard and anything else that turns with the steering |
| FrontWheel | front wheel |
| RearWheel | rear wheel |
| Pedalier | chainring + both crank arms + the pedal axle stubs |
| Pedal Left | left pedal (on the +Y side) |
| Pedal Right | right pedal (on the −Y side) |

The chain doesn't animate. Leave it on the Frame.

## 3. Build the skeleton (armature)

Bones tell the game **where each part turns and around which line**.

### Add the root bone
In Object mode, press **Shift+A → Armature**. Keep the armature object at location 0, rotation 0, scale 1. Go into Edit mode (Tab) and rename the bone to **`frame`**. Leave it at 0,0,0, pointing straight up. How far up the tail goes doesn't matter.

### Add the other bones
For each bone, find its pivot point first:
1. Select the part's mesh and enter Edit mode.
2. Select a ring of vertices around the axle.
3. Press **Shift+S → Cursor to Selected**. The 3D cursor is now exactly on the pivot.
4. Go back to object mode and select the armature.
5. Go into the armature's Edit mode and press **Shift+A** to add a bone at the cursor.
6. Fine-tune its **Head** and **Tail** in the **N panel → Item** to point it in the direction listed in the table below.

**The one rule that matters:** a bone's **head sits on the pivot**, and the line from **head to tail is the axis it rotates around**. For wheels, the crank and the pedals, that line goes **sideways** (along Y). For the fork, it goes **up along the head tube**, so it tilts backwards a little, just like the real bike.

| Bone | Head goes at | Tail points | Parent |
|---|---|---|---|
| `frame` | 0,0,0 | up | – |
| `fork` | bottom of the head tube | up along the head tube | frame |
| `wheel_front` | front hub center | sideways | fork |
| `wheel_rear` | rear hub center | sideways | frame |
| `crank` | bottom bracket center | sideways | frame |
| `pedal_L` | left pedal spindle (+Y) | sideways | crank |
| `pedal_R` | right pedal spindle (−Y) | sideways | crank |
| `att_seat` | where the rider sits on the saddle | anywhere | frame |
| `att_grip_L` | left handlebar grip (+Y) | anywhere | fork |
| `att_grip_R` | right handlebar grip (−Y) | anywhere | fork |

**Use these names exactly, with no spaces.** The addon looks them up by name.

The `att_` bones don't move anything. They only mark where the rider's seat and hands go.

**To find the fork's axis:** put the cursor on the center of the bottom ring of the steerer tube and set that as the head. Then put the cursor on the top ring and set that as the tail.

### Parent the bones
Parenting happens in the **armature's Edit mode**. Click a bone, then in the **Properties editor → Bone tab (green bone icon) → Relations**, set its **Parent**. Leave **Connected** unchecked, or the bone jumps to its parent.

> Can't click a bone? It's hidden inside the mesh. Press **Alt+Z** (X-ray), or select it in the Outliner.

## 4. Attach the parts to the bones (skinning)

With skinning you tell the game **which bone moves which part of the 3D mesh**. Each part must be skinned to exactly one bone, with **weight 1.0** (full influence). The addon uses the bone names to find the right part.

Do this for each part:
1. In Object mode, click the mesh, Shift-click the armature, then press **Ctrl+P → With Empty Groups**.
2. Go into the mesh's Edit mode and select all (**A**).
3. In **Object Data → Vertex Groups**, pick the matching bone name and click **Assign** (weight 1.0).

| Object | Vertex group |
|---|---|
| Frame | `frame` |
| Handle | `fork` |
| FrontWheel | `wheel_front` |
| RearWheel | `wheel_rear` |
| Pedalier | `crank` |
| Pedal Left | `pedal_L` |
| Pedal Right | `pedal_R` |

*Note that the `att_` bones don't have any mesh assigned to them.*

### Test it
Go to **Pose mode**, select a bone, press **R, then Y twice**, and move the mouse. That rotates the bone around its own axis.
- Wheels and crank should spin **without wobbling**. If they wobble, the head isn't exactly on the hub.
- The fork should steer the handlebar, front wheel and grips together, without the steerer poking out of the head tube. A slight dip and sideways shift of the front wheel is normal bicycle geometry.
- The pedals should travel along with the crank.

Press **Alt+R** to reset the pose afterwards.

## 5. Make the collision (physics) mesh

The game uses a separate, very simple shape for collisions. Make **one object** out of **4 simple pieces**:

| Piece | Shape | Size |
|---|---|---|
| Frame | stretched box | from the rear hub to the head tube, and from the bottom bracket to the top of the saddle; about as wide as a tire |
| Handlebar | flat box | grip end to grip end |
| Rear wheel | cylinder with 12 sides | same size as the tire, centered on the hub |
| Front wheel | cylinder with 12 sides | same size as the tire, centered on the hub |

How to build it:
- **Boxes:** Shift+A → Cube, then scale it around the part in Edit mode. A rough fit is fine.
- **Wheels:** put the cursor on the hub (same trick as before), Shift+A → Cylinder, set **Vertices: 12**, rotate it 90° around X, and scale it to the tire's size.
- Join the four pieces with **Ctrl+J**, name the object `bicycle_phys`, and skin all of it to the **`frame`** bone
  (the same way as in step 4).
- The joined object keeps the location, rotation and scale of whichever piece was active, so press
  **Ctrl+A → All Transforms** on it again. Otherwise the collision model ends up in the wrong spot.
- Right-click → **Shade Smooth**. Otherwise the compiler can split the pieces into lots of little ones.

Rules:
- Every piece must be **convex**: no dents, holes or inward bevels. Plain boxes and cylinders always are.
- Pieces **may overlap** in space, but must **not be connected**, meaning they share no vertices. Ctrl+J is safe; **Merge by Distance** and **Boolean union** are not. To check, hover over a piece in Edit mode and press **L**: only that one piece should light up.
- Make the wheel cylinders **full tire size**. The addon handles the tires itself and shrinks these automatically.
- Leave out the pedals, crank and small details.

## 6. Collections (how the export is grouped)

Blender Source Tools exports **each collection as one file**. Parenting doesn't change that.
- Put all the visible bike parts in a collection called **`bicycle_ref`**.
- Put the physics object in a collection called **`bicycle_phys`**.

Select objects and press **M → + New Collection** to move them. The Source Engine Export panel should now list those two collections, and you export both as **SMD**.

## 7. Textures

Convert your textures to `.vtf` with VTFEdit and write a `.vmt` for each material. Put them in `materials/models/<yourname>/bicycle/`. The **material names in Blender** must match the `.vmt` file names.

## 8. The QC file and compiling

Save this next to your SMDs as `bicycle.qc`:

```
$modelname "<yourname>/bicycle.mdl"
$cdmaterials "models/<yourname>/bicycle/"
$scale 46
$origin 0 0 0 -90

$body "body" "bicycle_ref.smd"
$sequence "idle" "bicycle_ref.smd" fps 1

$attachment "seat"    "att_seat"   0 0 0
$attachment "grip_L"  "att_grip_L" 0 0 0
$attachment "grip_R"  "att_grip_R" 0 0 0
$attachment "pedal_L" "pedal_L"    0 0 0
$attachment "pedal_R" "pedal_R"    0 0 0

$collisionmodel "bicycle_phys.smd" {
    $concave
    $mass 15
}
```

- **`$scale 46`** converts meters to Source units. That's the scale the included bikes use: a little larger than real
  (39.37 would be exact), because at real size the rider's knees stay bent at the bottom of the pedal stroke.
- **`$origin 0 0 0 -90`** cancels the 90° turn that studiomdl gives every model. Without it the mesh and collision
  model face sideways in game while the bones still face forward.
- The attachment offsets are all zero on purpose, because the `att_` bones already mark the exact spots.

Compile with **Crowbar** (game: Garry's Mod) and open the result in **HLMV** to check it:
- the bike faces forward and stands on the ground
- the bone rotations look right
- the attachments show up at the seat, grips and pedals
- the collision view (Physics Model) shows your 4 simple pieces

## 9. Register your bike

Tell the addon about your model with a small Lua file in your own addon, for example `lua/autorun/sh_mybike.lua`:

```lua
AddCSLuaFile()

hook.Add("BicycleRegisterModels", "mybike", function()
  bicycle.registerModel("mybike", {
    name = "My Bike",
    model = "models/<yourname>/bicycle.mdl",
    seatOffset = Vector(-8, 0, 1),
    seatPitch = 50,
  })
end)
```

- `name` is what the spawn menu shows. Your bike appears under **Entities** next to the included one.
- `seatOffset` moves the rider from your `att_seat` bone (forward, left, up), and `seatPitch` leans them forward.
- `gripOffset` moves the hands from your `att_grip_L`/`att_grip_R` bones (forward, outward, up; the same for both
  sides), in case the fists don't sit around the grips.
- `mass`, `gearRatio`, `pedalCenterOffset` (how far out from the pedal bones the feet go) and `footBallHeight` are
  optional. `lua/bicycle/sh_models.lua` in this addon lists every setting and shows how the included bike uses them.

The wheel positions, wheel size and saddle height are measured from your bones and collision mesh when the bike
spawns, so you don't need to enter them.

### Tune it in game

Spawn your bike, ride or look at it, and run **`bicycle_editor`** in the console (admins only). Its sliders change every
setting above live, and markers show where the seat, hands and feet end up. Sit on the bike to see the rider follow.
When it looks right, click **Copy registration** and paste the result over the `bicycle.registerModel` call in your
file. Edits made in the editor only last until the map changes.
