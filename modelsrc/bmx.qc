$modelname "bicycle/bmx.mdl"
$cdmaterials "models/bicycle/"
$scale 39.37

$body "body" "bmx_ref.smd"
$sequence "idle" "bmx_ref.smd" fps 1

$attachment "seat"    "att_seat"   0 0 0
$attachment "grip_L"  "att_grip_L" 0 0 0
$attachment "grip_R"  "att_grip_R" 0 0 0
$attachment "pedal_L" "pedal_L"    0 0 0
$attachment "pedal_R" "pedal_R"    0 0 0

$collisionmodel "bmx_phys.smd" {
    $concave
    $mass 15
}
