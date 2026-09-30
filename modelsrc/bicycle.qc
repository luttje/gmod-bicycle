// Bicycle for sent_bicycle. Exported from bicycle.blend with Blender Source Tools, in meters.
// Compile: studiomdl -game <GarrysMod>/garrysmod -nop4 bicycle.qc

$modelname "bicycle/bicycle.mdl"

// Meters to Source units, sized against the player models: at 39.37 (1 unit = 1 inch) the knees stayed bent at the
// bottom of the pedal stroke, at 52.49 (1 unit = 1.905 cm) the handlebar reached a standing player's chest.
$scale 46

// studiomdl turns every model 90 degrees around Z by default (made for models facing -Y). This one already faces +X,
// so the rotation is cancelled out. Without it the mesh and collision model face +Y in game while the bones don't.
$origin 0 0 0 -90

$body "bicycle" "bicycle_ref.smd"

$cdmaterials "models/bicycle/"
$surfaceprop "metal"

$sequence "idle" "bicycle_ref.smd" fps 30

// Zero offsets on the helper bones, so $scale can't move them.
$attachment "seat"    "att_seat"   0 0 0
$attachment "grip_L"  "att_grip_L" 0 0 0
$attachment "grip_R"  "att_grip_R" 0 0 0
$attachment "pedal_L" "pedal_L"    0 0 0
$attachment "pedal_R" "pedal_R"    0 0 0

// Four convex pieces: frame box, handlebar box and two wheel discs. The code shrinks the discs into bump stops, the
// tyres are simulated by traces.
$collisionmodel "bicycle_phys.smd"
{
	$mass 15
	$concave
}
