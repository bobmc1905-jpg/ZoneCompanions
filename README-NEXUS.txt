[center][size=6][b]ZONE COMPANIONS[/b][/size]
[size=4][i]Don't walk the Zone alone.[/i][/size][/center]

A squad of NPC companions for ZERO Sievert. Hire them from a contact in the hub bar, and they spawn beside you at the start of every raid, follow you in formation, fight what you fight, patch you up when you're hurt, scout ahead with their own working eyes, and carry their injuries between raids.

The difference from a scripted follower mod is what's driving them. Zone Companions is built on GMLoader, so your companions inherit the game's own NPC brain — the same utility AI that makes bandits take cover, flank, shoot and reload, and the same A* navigation grid the base game paths on. When a firefight starts, this mod steps aside and lets vanilla's combat AI take over completely.

[b]This mod contains no combat code at all.[/b] That's deliberate — it's why your squad fights like the game's own NPCs instead of like a script.

[b]Version 1.1.1[/b] — now with paid recruitment from an NPC in the hub, companion vision that reveals the map, and a config that updates itself.


[size=5][b]What your squad does[/b][/size]

[list]
[*][b]Fights with the game's real AI[/b] — cover, flanking, reloading, target selection. Not approximated.
[*][b]Paths properly[/b] — they route around buildings and terrain on the game's own A* navigation grid instead of grinding into walls.
[*][b]Sees for you[/b] — enemies, loot containers and the companions themselves are drawn when a companion can see them, even when you can't, and each companion's view cone clears the fog of war exactly like your own.
[*][b]Holds a formation that covers where you're looking[/b] — they sit behind your heading, so they're out of your line of fire, but slide toward your cursor so they screen the direction you're actually watching.
[*][b]Keeps up with you[/b] — follow speed is derived from your live current speed, so backpacks, hunter skills and the hub's run bonus can't leave them trailing behind.
[*][b]Patches you up[/b] — a companion breaks off to heal you when you're hurt, and abandons a firefight to reach you when you're critical. Exactly one claims each wound, so the whole squad doesn't drop formation for the same injury. Charges refill every raid.
[*][b]Won't shoot you, and you won't shoot them[/b] — protection runs both ways, enforced inside the game's own bullet-collision checks, so a blocked round isn't wasted and can still hit the enemy behind it.
[*][b]Belongs to your character[/b] — the roster is saved in that character's save slot, carries injuries between raids, and is deleted with the save.
[*][b]Behaves naturally when idle[/b] — they drift around their position while you stand still, and snap back into formation the moment you move.
[*][b]Tells you what's going on[/b] — a squad panel shows each companion's name, health, remaining field dressings and current mode.
[/list]


[size=5][b]Hiring companions[/b][/size]

Companions are bought, from a hireable-labour contact who stands in the hub bar under a floating [i]Labour Contracts[/i] label. Walk up, press [b]F[/b] — the game's normal Interact key — and pick a tier:

[list]
[*][b]Rookie — 2,500 roubles.[/b] The loner_novice preset at baseline health.
[*][b]Veteran — 6,000 roubles.[/b] loner_regular, 1.75× health.
[*][b]Elite — 12,000 roubles.[/b] loner_regular, 3× health.
[/list]

In the menu: [b]W[/b]/[b]S[/b] to choose, [b]Enter[/b] to buy, [b]Backspace[/b] to close.

The tier is not cosmetic. The preset is where the game gets an NPC's reflexes, health and weapon setup, so a more expensive companion genuinely fights better. Names, prices, presets and multipliers are all configurable, and you can point a tier at the bandit ladder (bandit_veteran, bandit_master) for smarter AI at the cost of looking like a bandit.

Money is taken through the game's own trader transfer, so a hire shows up in your rouble count exactly like any other purchase. The menu refuses with a reason when you can't afford a tier, or when the roster is already at max_companions. Hire in a raid and the companion appears beside you; hire in the hub and they join the roster for your next raid.

[size=5][b]What your companions can see[/b][/size]

Companions have working eyes, and what they see counts as something you can see:

[list]
[*][b]Anything inside a companion's vision cone is drawn[/b] — enemies, loot containers, and the companions themselves. This is not cosmetic: the base game fades every raid NPC to fully transparent outside [i]your[/i] line of sight, so before this a companion twenty metres ahead was literally not rendered, and neither was their flashlight.
[*][b]Each cone also clears the fog of war[/b], inside the game's own subtract pass, so it opens the map up exactly the way your own cone does. No coloured overlays or boxes — the map simply opens up where your squad is looking.
[*][b]The cone is the real one[/b] — the same triangle the companion's AI searches for targets, built from its weapon direction, alert radius and visual distance, including the day/night penalty. What gets revealed is precisely what that companion could actually shoot at.
[/list]

Optional white position pins mark companions through fog and walls, with an edge arrow when they're off screen. Off by default, because a companion standing in fog it cleared itself is already visible.


[size=5][b]Companion modes[/b][/size]

[list]
[*][b]Following[/b] — paths to a formation slot around you, drifting a little while you stand still.
[*][b]Fighting[/b] — a hostile is within engagement range of you, and the vanilla combat AI takes over completely.
[*][b]Healing[/b] — on its way to patch you up, or doing it.
[*][b]Holding[/b] — stays put, but still returns fire.
[/list]

Priority is Healing → Fighting → Holding → Following. Fighting outranks Holding, so a companion told to hold position will still defend itself. Healing outranks Fighting only for a [i]critical[/i] wound; otherwise it finishes the firefight first.


[size=5][b]Controls[/b][/size]

[list]
[*][b]F[/b] — Standing next to the recruiter, open the hire menu. Does nothing anywhere else
[*][b]F5[/b] — Show or hide the squad panel
[*][b]F7[/b] — Dismiss the companion nearest you, permanently
[*][b]F8[/b] — Toggle the whole squad between Follow and Hold
[*][b]F9[/b] — Dump full squad state to the log (use this when reporting a bug)
[*][b]F6[/b] — [i]Debug only:[/i] add one free companion from the default preset. Requires debug mode switched on
[/list]

All six are rebindable in the config. Function keys are the defaults because the base game never reads F5–F9 without a modifier, so they can't collide with your movement or inventory bindings.

[b]F is the deliberate exception.[/b] It's the game's own Interact key, because talking to the recruiter should feel like talking to any other NPC. Vanilla's Interact only does anything inside an interactable's own range, and the recruiter's corner of the bar isn't one — so away from him, the recruit action is simply a no-op.

Commands are ignored while the Steam overlay is up, and while you're in a menu, dialogue, the inventory, the PDA, crafting, sleeping, dead, or riding the intro train — so nothing fires behind a UI.

[size=5][b]Requirements[/b][/size]

[list]
[*][b]ZERO Sievert[/b] — tested against 1.2.92
[*][b]GMLoader[/b] — tested against build 34
[*]No other mods required
[/list]

GMLoader makes a backup.win for you — keep your own copy of data.win too.

[b]Important:[/b] this is a GMLoader mod, not a Steam Workshop mod. GMLoader decompiles and recompiles the game's data.win when you install it. That's what makes real companion AI possible, and it's also why this can't go on the Workshop — and why you have to re-run GMLoader after every game update.


[size=5][b]Installation[/b][/size]

[list=1]
[*]Install GMLoader into your ZERO Sievert game folder, next to data.win, following GMLoader's own instructions. You should end up with GMLoader.exe, GMLoader.ini and a mods folder beside the game.
[*][b]Patch the install your launcher actually starts.[/b] On Steam that's usually …\Steam\steamapps\common\ZERO Sievert\ — not some other copy of the game folder. Patching the wrong copy reports complete success while the game you launch stays vanilla, and because both share one save folder it's easy to misdiagnose.
[*][b]Merge[/b] this mod's mods folder into GMLoader's mods folder. GMLoader uses one shared, flat tree — mods do not get their own subfolder — so you're merging, not replacing. 21 files in total.
[*]Run GMLoader from the game folder, and check GMLoader.log for a successful save with no errors.
[*]Launch the game. On first run the mod writes a fully commented reference of every setting to %LOCALAPPDATA%\ZERO_Sievert\csq_config.ini, and an empty csq_config_user.ini next to it for your own changes.
[/list]

[b]If GMLoader stops on a hash check:[/b] different builds of the same game version can hash differently, which is not corruption. Get your own hash with the bundled GMLoader - xxHash.exe utility and put it in GMLoader.ini as SupportedDataHash. Leave CheckHash=true — with the check off, GMLoader never creates backup.win, so it has nothing pristine to recompile from and no way to undo a patch.

[b]After a game update:[/b] delete the stale backup.win, let GMLoader make a fresh one, and re-run it.


[size=5][b]Configuration[/b][/size]

There are two files, both beside your saves in %LOCALAPPDATA%\ZERO_Sievert.

csq_config.ini is a [b]generated reference[/b]: all 97 settings, each with its current default and a comment explaining it. It's rewritten from scratch every launch, so it always matches the version you're running — which means a mod update can never leave you with a config file that quietly lacks its new settings. Don't edit this one.

csq_config_user.ini is [b]yours[/b]. Put in it only the lines you want to change, save, and restart the game — config is read once at boot. The mod never overwrites this file.

[b]Nothing to do when you update.[/b] Coming from 1.0.0, your old settings are moved into the new user file automatically on the first launch. And if you edit the generated file out of habit, the mod moves those lines into your user file for you, applies them that same launch, and says so in the log. Nothing is lost.

The eleven sections at a glance:

[list]
[*][b]debug[/b] — logging verbosity and the debug overlay (off by default)
[*][b]squad[/b] — squad size, the NPC preset used, spawning, toughness
[*][b]follow[/b] — formation shape, follow distances and speeds, teleport rescue
[*][b]roam[/b] — idle drift around the formation slot
[*][b]combat[/b] — engagement range, aggression, faction standings
[*][b]ff[/b] — friendly fire in both directions, grenade disarming
[*][b]medic[/b] — whether and when companions heal you, and how much
[*][b]hud[/b] — squad panel position, size and contents
[*][b]reveal[/b] — what your companions' vision reveals, and how strongly
[*][b]recruit[/b] — the recruiter NPC, the three tiers, their prices, menu keys
[*][b]input[/b] — the six keybinds
[/list]

csq_ is the mod's internal namespace prefix. It shows up in the config filename, the log filename and every log line. It's kept short deliberately: GMLoader loads every mod into one shared flat folder, so a short unique prefix is what stops two mods colliding.

Full reference, including tuning recipes for "they keep falling behind" and "I want a single tanky bodyguard", is in CONFIGURATION.md in the download, and on the [url=https://github.com/bobmc1905-jpg/ZoneCompanions]GitHub page[/url].


[size=5][b]Compatibility and known issues[/b][/size]

[b]Compatibility[/b]
[list]
[*][b]Saves:[/b] safe to add to an existing character, and safe to remove. Roster data lives in its own section of the save that the base game never reads, so leftovers after uninstalling are harmless.
[*][b]Other GMLoader mods:[/b] should coexist. Everything the mod adds lives in its own uniquely-prefixed scripts and its own new objects, and it touches base-game code in only nine places. The two worth knowing about are the bullet-collision checks bullet_can_collide_with_player and bullet_can_collide_with_npc — another mod that rewrites those specific functions could conflict. Each patch is applied independently, so a clash disables that one patch and logs a warning rather than breaking the build.
[*][b]Steam Workshop mods:[/b] the Workshop mod system and GMLoader work differently and don't know about each other. Running both is generally fine, but a Workshop companion or follower mod alongside this one is asking for trouble.
[*][b]Not compatible with:[/b] any mod that also replaces those two bullet-collision functions.
[/list]

[b]Known issues[/b]
[list]
[*]Must be re-applied after every game update, because the update replaces the file GMLoader patched.
[*][b]Wall shadows are cast from your position, not your companion's.[/b] Inside ground a companion has revealed, the fog shader still draws shadows relative to you. The base game hands that shader exactly one light position, and giving each companion its own would mean an extra shader pass per companion. The ground is revealed correctly; only the direction the shadows fall is wrong.
[*]All companions of a tier use one NPC preset. Per-companion presets are stored in the roster and honoured on load, so a mixed squad works, but the choice is per [i]tier[/i] rather than per hire.
[*]Companions carry no inventory and can't be given gear. They spawn with whatever their preset's weapon setup provides. Medic charges are an abstract per-raid count, not an item — healing consumes nothing from anyone's bag.
[*]Companions don't throw grenades while that's switched on in the config, which it is by default. This is blunt on purpose: grenade damage in this game has no faction check of any kind, so there's no way to let them throw and keep you safe.
[*]The medic doesn't treat wounds. It restores health and stops bleeding, exactly like an NPC medic's dialogue heal. Wounds need medication, and the mod deliberately never touches that stat.
[/list]


[size=5][b]Reporting a bug[/b][/size]

The mod writes a fresh log every launch to %LOCALAPPDATA%\ZERO_Sievert\logs\csq_log.txt, at one of four levels — 0 ERROR, 1 WARNING, 2 INFO (the default), 3 DEBUG. DEBUG also needs debug mode switched on, so raising the level alone won't flood the file.

Set log_level = 3 and debug_enabled = true in csq_config_user.ini, restart, reproduce the problem, press F9, and attach the log. F9 works regardless of the debug settings, so you can always get a dump. Please include your game version, your GMLoader build, and any other GMLoader mods you have installed.


[size=5][b]Uninstalling[/b][/size]

[list=1]
[*]Delete this mod's 21 files from GMLoader's mods tree.
[*]Re-run GMLoader to rebuild a clean data.win from backup.win.
[/list]

Optionally also delete csq_config.ini, csq_config_user.ini and logs\csq_log.txt from %LOCALAPPDATA%\ZERO_Sievert. Leftover roster data in a save is harmless.

[size=5][b]Permissions[/b][/size]

This mod is released under the MIT Licence, and the permissions below simply restate it in Nexus terms. In short: do what you like with it, just credit me and link back.

[list]
[*][b]Use in your own mods:[/b] yes. Take the code, the approach, whole modules, whatever's useful.
[*][b]Modify and re-upload:[/b] yes, including here on Nexus — credit the original and link back to this page or the GitHub repo.
[*][b]Fix it or update it for a newer game version:[/b] yes, and you don't need to ask first. If I've gone quiet and the mod is broken, please do.
[*][b]Translate it:[/b] yes, with credit.
[*][b]Include it in a modpack or compilation:[/b] yes, with credit.
[*][b]Convert it to another game or another loader:[/b] yes, with credit.
[*][b]Credit required:[/b] yes, in all of the above. Name the original mod and link back — that's the only condition.
[/list]

Only ask that you don't present it as your own original work, and that if you fork it publicly you keep the MIT licence notice with it.


[size=5][b]Credits[/b][/size]

[list]
[*][b]Bobby[/b] — mod author
[*][b]Senjay-id[/b] — [url=https://github.com/Senjay-id/GMLoader]GMLoader[/url], without which this mod could not exist
[*][b]The Underminers team[/b] — [url=https://github.com/UnderminersTeam/UndertaleModTool]UndertaleModTool[/url], which GMLoader uses to recompile the game
[*][b]The ZERO Sievert modding community[/b] — for mapping out the game's internals
[*][b]CABO Studio[/b] — for ZERO Sievert itself, published by Modern Wolf
[/list]


[size=5][b]Source, full documentation and issue tracker[/b][/size]

[url=https://github.com/bobmc1905-jpg/ZoneCompanions]github.com/bobmc1905-jpg/ZoneCompanions[/url]

Changes in each release are listed in CHANGELOG.md, both in the download and in the repository.

[center][i]Released under the MIT Licence — © 2026 Bobby[/i][/center]
