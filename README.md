# 🚲 Gmod Bicycle

![Screenshot of Kleiner playermodel on an orange mountainbike](materials/entities/colourable_mountain_bike.png)

A bicycle you can actually ride in Garry's Mod. Pedal, lean into corners, bunny hop over things, pull wheelies and
crash spectacularly. The wheels spin, the fork steers and your character keeps their hands on the grips and feet on
the pedals.

## Installing
**Steam Workshop (recommended):** subscribe on the
[Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3810718443) and it will download the next time you
start Garry's Mod.

**Manually:** download this repository and put the contents of this repo in a `bicycle` folder in `garrysmod/addons/`.

## Getting started
1. Open the spawn menu (**Q**), go to **Entities → Fun + Games** and spawn the **Colourable Mountain Bike**. Every
   bike spawns in a random color, and you can repaint it with the Color tool.
2. Walk up to it and press **E** to get on.
3. Hold **W** to pedal and use **A** / **D** to steer.

Knocked the bike over? Press **E** on it and it stands back up when you get on.

## Bicycle Controls

### Riding
| Key | Action |
|---|---|
| W | Pedal |
| S | Brake. When standing still, walk the bike backwards (doesn't animate walking backwards) |
| A / D | Steer Left/Right |
| Shift | Sprint |
| Space | Bunny hop |
| Left mouse (hold) | Lean forward. Brake while leaning to pull a stoppie, then let go of the brake to keep rolling on the front wheel |
| Right mouse (hold) | Wheelie |
| R | Ring the bell |
| E | Get off |

> [!TIP]
> Prefer riding in third person? Turn on **Third person** under **Options → Bicycle → Client**, or run
> `bicycle_cam_third_person 1` in the console.

> [!TIP]
> Hitting something hard enough will throw you over the handlebars.

> [!TIP]
> Water slows you down, and riding in until the bike is half under throws you off. Server admins can change both, or turn
> the throwing off, under **Water** in the server settings.

### Tricks
| Trick | When | Keys | Notes |
|---|---|---|---|
| Tailwhip | In the air | Left mouse + A / D | Spins the frame around the handlebar. Keep holding for more turns |
| Barspin | In the air or in a wheelie | Right mouse + A / D | Spins the handlebar. Keep holding for more turns |
| Tailwhip + barspin | In the air | Both mouse buttons + A / D | Both at once |
| Backflip / front flip | In the air | Double-tap S / W | Keep holding the second press for more flips |
| No-hander | In the air | Ctrl + W | Lasts as long as you hold it |
| No-footer | In the air | Ctrl + S | Lasts as long as you hold it |
| Can-can | In the air | Ctrl + A / D | Left / right leg. Lasts as long as you hold it |
| X-up | In the air or in a wheelie | Right mouse + W | Lasts as long as you hold it |

> [!TIP]
> Land your tricks straight: touching down more than 45° off throws you off. Let go of the buttons early and the spin finishes the turn by itself.

> [!TIP]
> Tricks combine: try a backflip no-hander by double-tapping S, then holding Ctrl + W.

## Settings
Open the spawn menu and go to **Options → Bicycle**. Changes apply straight away, so you can tweak things while riding.

- **Client** is just for you: first or third person, camera distance and height, camera roll, speedometer units (km/h, mph or off), how
  your character sits on the bike and the volume of the riding sounds and wind. These are saved.
- **Server** changes how every bike on the server rides: top speed, acceleration, steering, grip, suspension and more.
  Only the host or an admin can change these, and they reset to the defaults every time the server restarts. Admins can
  also turn all bike sounds off, or just the bell, or give the bell a cooldown under **Sounds**.

> [!TIP]
> If you modify any server ConVars and want to automatically persist them in `cfg/server.vdf`: run the command `host_writeconfig_lua` in the server console (or add the relevant ConVars to your `cfg/server.cfg` file)

> [!TIP]
> Changed too much? Run `bicycle_reset_client` in the console to restore your own settings, or `bicycle_reset_tuning`
(admins) to restore the server settings.

## Permissions
Admin-only actions are [CAMI](https://github.com/glua/CAMI) privileges, so admin mods like ULX, SAM and Helix can grant
them to any group. Without an admin mod, only admins have them.

| Privilege | Allows |
|---|---|
| `Bicycle - Physgun Ridden Bikes` | Picking up a bike someone is riding with the physgun |
| `Bicycle - Reset Tuning` | Running `bicycle_reset_tuning` |
| `Bicycle - Model Editor` | Using `bicycle_editor` |

## Problems and suggestions
Found a bug, a conflict with another addon, or have an idea? Please
[open an issue](../../issues/new/choose). If something about the handling feels off, the **Tuning feedback** template
is the place for it.

## For modders and gamemode developers
Want to add your own bikes or tricks, or have your gamemode react to bikes? The
[📚 `INTEGRATION_GUIDE.md`](INTEGRATION_GUIDE.md) covers registering bike models, writing tricks and all the hooks.
To build a bike model from scratch, see [📚 `MODELING_GUIDE.md`](MODELING_GUIDE.md).

## Credits
The `models/bicycle/bicycle.mdl`/`modelsrc/source/bicycle.fbx` model is "Bicycle Game Asset" (https://skfb.ly/oyZ6w) by RayznGames is licensed under Creative Commons Attribution (http://creativecommons.org/licenses/by/4.0/)

The `models/bicycle/bmx.mdl`/`modelsrc/source/bmx.fbx` model is "Bmx Bike" (https://skfb.ly/YWSG) by Grimecent is licensed under Creative Commons Attribution (http://creativecommons.org/licenses/by/4.0/).

Changes made to both these assets:
- The texture was modified to be gray (instead of orange) to be better recolorable in-game.
- The model was modified (meshes were merged)
- An armature was added to the model to allow it to be animated.
