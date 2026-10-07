bicycle.guide.registerChapter({
  id = "settings",
  title = "Settings",
  order = 50,
  content = {
    "Open the spawn menu and go to Options → Bicycle. Changes apply straight away, so you can tweak things while "
    .. "riding.",
    { type = "heading", text = "Client" },
    "Just for you, and saved between sessions: first or third person, camera distance and height, camera roll, "
    .. "speedometer units, how your character sits on the bike and the volume of the riding sounds and wind.",
    { type = "heading", text = "Server" },
    "How every bike on the server rides: top speed, acceleration, steering, grip, suspension and more. In singleplayer "
    .. "and on a server you host from the menu, you change them right there. On a dedicated server, the menu only "
    .. "shows them: set the bicycle_* ConVars from the server console, rcon or cfg/server.cfg instead.",
    {
      type = "tip",
      text = "Changed too much? Run bicycle_reset_client in the console to restore your own settings, or "
          .. "bicycle_reset_tuning (admins) to restore the server settings.",
    },
  },
})
