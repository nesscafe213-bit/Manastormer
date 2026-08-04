# Manastormer

Manastormer is a flexible Project Ascension raid-control addon for organised Manastorm levelling groups.

Current release: **v2.8.9**  
Author: **Nesscafe**

## Download and installation

1. Open the latest entry on the repository's **Releases** page.
2. Download `Manastormer-2.8.9.zip`.
3. Extract the `Manastormer` folder into your Ascension client's `Interface\AddOns` folder.
4. Restart Ascension or type `/reload` in game.
5. Type `/msm` to open the addon.

## Highlights

- Flexible raid-size, Tank, Healer and Aura requirements.
- Recruitment whispers and a public LFG chat scanner with individual Invite buttons.
- Automatic capacity replies when a whispered Tank, Healer, DPS or Aura role is already full, with per-player spam protection.
- Automatically suspends recruitment and automation inside non-Manastorm instances, then resumes after leaving.
- Automatic role detection from replies including Tank/Aura and Healer/Aura combinations.
- Correct handling of replies such as `DPS no aura`, `healer no aura` and `without aura`.
- Aura coverage warnings when an occupied raid subgroup has no Aura player.
- Level 59 monitoring and critical level 60 warnings.
- Ready checks, level-and-role raid reports and Tank raid markers.
- Chaotic Link stack tracking with a configurable notification interval.
- Compact combat view and minimap launcher.
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
