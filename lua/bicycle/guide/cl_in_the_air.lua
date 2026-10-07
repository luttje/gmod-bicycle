bicycle.guide.registerChapter({
  id = "in_the_air",
  title = "In the air",
  order = 30,
  -- A function, as the server can turn these controls off at any time.
  content = function()
    if (not bicycle.getTuningBool("advanced_air_control")) then
      return {
        "This server has turned advanced air control off, so the bike flies the older, simpler way: it keeps its nose "
        .. "along its path and you can't steer it in the air. Tricks still work.",
      }
    end

    return {
      "Once both wheels leave the ground, the keys steer the bike through the air instead.",
      {
        type = "controls",
        rows = {
          {
            "[+moveleft] / [+moveright]",
            "Spin the bike round, such as to turn round up a quarter pipe and ride back down it",
          },
          { "[+forward] / [+back]", "Tip the nose down / up" },
          {
            "[+forward]",
            "Above the top of a quarter pipe: spine transfer over the top and into the quarter pipe behind it",
          },
        },
      },
      {
        type = "tip",
        text = "Keys you were already holding as you took off, such as pedalling or steering into a jump, only "
            .. "control the bike in the air once you press them again.",
      },
    }
  end,
})
