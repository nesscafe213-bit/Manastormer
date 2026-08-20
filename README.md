# Manastormer

Manastormer is a flexible Project Ascension raid-control addon for organised Manastorm levelling groups.

Current release: **v2.8.29**
Author: **Nesscafe**

## Download and installation

1. Open the latest entry on the repository's **Releases** page.
2. Download `Manastormer-2.8.29.zip`.
3. Extract the `Manastormer` folder into your Ascension client's `Interface\AddOns` folder.
4. Restart Ascension or type `/reload` in game.
5. Type `/msm` to open the addon.

### One-command updater

Keep `Install-Manastormer.ps1` and run it whenever a new version is released:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Manastormer.ps1
```

It downloads the latest GitHub release, detects Ascension's AddOns folder,
backs up the existing addon, installs the update and verifies the version.

## Highlights

- Coordinated **Leave + Regroup** uses Ascension's native Manastorm API: the
  leader snapshots the eligible roster, gives a five-second warning, and all
  participating Manastormer users leave together. Outside, members request and
  safely auto-accept only the saved leader's invitation while reinvites are
  paced and the party converts back to a raid. Level-60 and blocked players are
  never reinvited; non-addon users receive simple manual instructions.
- Removes the old protected `/uninvite` macro and detached secure disband button.
- Level-and-role reports now use normal raid chat rather than Raid Warning.
- The combat-safe Enter Manastorm control now stays aligned beside Ready Check
  across Ascension UI scales and saved window positions.
- Chat scanning resumes immediately after a raid reset even if Ascension leaves
  an old dungeon-finder mode cached until the next reload.
- Combat-safe panel sizing: the secure Manastorm entry control no longer protects
  the main panel, and minimize/expand requests wait cleanly for combat to end.
- Farewell messages say “good luck with your rolls”; detected level-59 players
  are also thanked when they leave, with duplicate whispers suppressed.
- Combat-safe layout changes prevent full-size controls from detaching from the
  compact window; requested open, close, size and page changes apply afterward.
- Starts closed and paused after every login or `/reload`; open it from the
  minimap button or with `/msm` when beginning a Manastorm session.
- Right-click yourself or a grouped player to toggle Tank, Healer, DPS or Aura,
  or clear their Manastormer roles; range is not required.
- Reloading starts paused: background level checks, kick controls, Aura
  reminders and chat monitoring remain off until Listen or Role Check starts.
- Compact view keeps its status writing clear of the header divider and grows
  vertically when several important alerts are visible.
- Leave + Regroup excludes level-60 and blocked players from its saved reinvite list.
- Level-59 and level-60 kick buttons send the removed player a friendly thank-you whisper and the GitHub download link.
- Role headings are centred precisely over the icon cells in both recruitment panels.
- Restores addon loading on Ascension after v2.8.15 exceeded its legacy Lua local-variable limit.
- Role and Aura assignments synchronise between grouped Manastormer users, with the raid leader providing the full shared snapshot.
- The GUI identifies the detected Manastormer raid leader or shows that you are hosting the sync.
- The raid leader posts a normal raid-chat reminder every two minutes when an occupied subgroup has no Aura; it never uses Raid Warning.
- Flexible raid-size, Tank, Healer and Aura requirements.
- Recruitment whispers and a public LFG chat scanner with individual Invite buttons.
- Aura recruitment whispers use an animated gold sparkling border for instant visibility.
- Automatic capacity replies when a whispered Tank, Healer, DPS or Aura role is already full, with per-player spam protection.
- Automatically suspends recruitment and automation for Dungeon Finder queues/groups and inside non-Manastorm instances, then resumes afterward.
- Automatic role detection from replies including Tank/Aura and Healer/Aura combinations.
- Correct handling of replies such as `DPS no aura`, `healer no aura` and `without aura`.
- Aura coverage warnings when an occupied raid subgroup has no Aura player.
- Live-verified level 59 monitoring with a secure user-clicked kick button, plus critical level 60 warnings.
- Level-60 actions are validated against the live roster rather than a cached short name.
- Secure user-click Manastorm Level 1 entry through Ascension's native control.
- Ready checks, level-and-role raid reports and Tank raid markers.
- Chaotic Link stack tracking with a configurable notification interval and a reporting on/off checkbox.
- Compact combat view and minimap launcher.
- Fully closing the main GUI sleeps all Manastorm recruitment and automation until reopened; compact mode remains active.
- Quiet version checks between grouped Manastormer users.
- Compatible with both ElvUI and Ascension's native WoW interface without modifying protected raid frames.

## Commands

```text
/msm                         Open or close Manastormer
/msm listen                  Start role detection
/msm pause                   Pause role detection
/msm whispers                Open recruitment whispers
/msm tank [PlayerName]       Toggle Tank
/msm healer [PlayerName]     Toggle Healer
/msm dps [PlayerName]        Toggle DPS
/msm aura [PlayerName]       Toggle Aura
/msm clearrole [PlayerName]  Clear roles
/msm add PlayerName 13       Assign Tank/Aura using role codes
/msm minimap                 Show or hide the minimap button
/msm help                    Show command help
```

When a player name is omitted, the role command uses your current target.

## Compatibility

Manastormer is made for the Project Ascension Wrath 3.3.5 client. It is not a Retail WoW addon.

To avoid secure-action errors, Manastormer does not programmatically click Ascension's protected Manastorm queue controls. Use the addon's Level 1 check, then click Ascension's native **Enter Group Manastorm** button yourself.
