bicycle.guide.registerChapter({
  id = "riding",
  title = "Riding",
  order = 20,
  content = {
    "Lean into corners, hop curbs and pull wheelies. Everything here works with both wheels on the ground.",
    {
      type = "controls",
      rows = {
        { "[+forward]", "Pedal" },
        { "[+back]", "Brake. Standing still, walk the bike backwards" },
        { "[+moveleft] / [+moveright]", "Steer left / right" },
        { "[+speed]", "Sprint" },
        { "[+jump]", "Bunny hop" },
        {
          "[+attack]",
          "Hold to lean forward. Brake while leaning to pull a stoppie, then let go of the brake to keep rolling on "
          .. "the front wheel",
        },
        { "[+attack2]", "Hold to wheelie" },
        { "[+reload]", "Ring the bell" },
        { "[+use]", "Get off" },
      },
    },
    { type = "heading", text = "Crashing" },
    {
      type = "tip",
      text = "Hitting something hard enough throws you over the handlebars, and so does landing from too high.",
    },
    {
      type = "tip",
      text = "Water slows you down, and riding in until the bike is half under throws you off. Server admins can "
          .. "change both, or turn the throwing off, under Water in the server settings.",
    },
  },
})
