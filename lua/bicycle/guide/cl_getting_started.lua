bicycle.guide.registerChapter({
  id = "getting_started",
  title = "Getting started",
  order = 10,
  content = {
    "Grab a bike from the spawn menu, under Entities → " .. bicycle.SPAWN_CATEGORY .. ". Every bike spawns in a random "
    .. "color, and you can repaint it with the Color tool.",
    {
      type = "controls",
      rows = {
        { "[+use]", "Get on the bike, and off again" },
        { "[+forward]", "Pedal" },
        { "[+moveleft] / [+moveright]", "Steer" },
      },
    },
    { type = "tip", text = "Knocked the bike over? Get back on and it stands itself back up." },
    {
      type = "tip",
      text = "Prefer riding in third person? Turn on Third person under Options → Bicycle → Client, or run "
          .. "bicycle_cam_third_person 1 in the console.",
    },
    { type = "tip", text = "Lost this binder? Run bicycle_guide in the console to open the guide anywhere." },
  },
})
