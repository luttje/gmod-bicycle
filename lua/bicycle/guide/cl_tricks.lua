-- Where each contact a trick allows has it done, in the order they're listed.
local CONTACT_PLACES = {
  { contact = "none", place = "in the air" },
  { contact = "rear", place = "in a wheelie" },
  { contact = "front", place = "in a stoppie" },
  { contact = "both", place = "on the ground" },
}

--- @param trick table
--- @return string # Such as "in the air or in a wheelie"
local function getTrickPlaces(trick)
  local places = {}

  for _, contactPlace in ipairs(CONTACT_PLACES) do
    if (trick.contact[contactPlace.contact]) then
      places[#places + 1] = contactPlace.place
    end
  end

  return table.concat(places, " or ")
end

bicycle.guide.registerChapter({
  id = "tricks",
  title = "Tricks",
  order = 40,
  -- A function, so it lists every trick registered by then and the server's current landing tolerance.
  content = function()
    local blocks = {
      "Get some air and throw down. Most tricks keep going for as long as you hold their keys, so let go in time to "
      .. "land them.",
    }

    for _, trick in ipairs(bicycle.trick.getAll()) do
      blocks[#blocks + 1] = {
        type = "card",
        title = trick.name,
        tag = getTrickPlaces(trick),
        keys = trick.keys,
        text = trick.description,
      }
    end

    blocks[#blocks + 1] = { type = "heading", text = "Combos" }
    blocks[#blocks + 1] = "Tricks combine. Try these to get started:"
    blocks[#blocks + 1] = {
      type = "controls",
      rows = {
        { "[+attack] + [+attack2] + [+moveleft] / [+moveright]", "Tailwhip barspin" },
        { "Double-tap [+back], then [+duck] + [+forward]", "Backflip no-hander" },
      },
    }
    blocks[#blocks + 1] = {
      type = "tip",
      text = string.format(
        "Land your tricks straight: touching down more than %d° off throws you off. Let go of the keys early and a "
        .. "spin finishes its turn by itself.",
        math.Round(bicycle.getTuning("trick_land_tolerance"))
      ),
    }

    return blocks
  end,
})
