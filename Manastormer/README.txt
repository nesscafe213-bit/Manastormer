MANASTORMER 2.8.9
Project Ascension flexible Manastorm raid helper

INSTALL
Copy the Manastormer folder into:
Interface\AddOns\

Restart Ascension or type /reload.

OPEN THE ADDON
/msm
/manastorm
/manastormer

MAIN FEATURES
- Automatically suspends recruitment capture, chat scanning, capacity replies
  and raid automation inside non-Manastorm instances, then resumes after leaving.
- Compatible with both ElvUI and Ascension's native WoW interface. Manastormer
  detects the active interface but never hooks, hides or modifies its protected
  raid frames or unit-popup menus.
- CoA Planner-inspired navy, bronze and gold interface with matching fonts.
- Custom Manastormer artwork in the window header and on the minimap.
- Draggable minimap button: left-click toggles the GUI and right-click hides it.
- Compact/full view switches immediately during combat; the secure level-60
  fallback remains independently protected by Ascension.
- Quietly exchanges version numbers with grouped Manastormer users and gives a
  local warning when a newer addon version is available.
- Settings includes a 1-10 second Chaotic Link alert-interval slider to control
  stack-warning spam. The critical 0-stack warning always fires immediately.
- Includes a Settings page for flexible Total, Tank, Healer and Aura targets.
- Calculates the DPS target from Total minus Tanks and Healers.
- Tracks Aura as an overlapping role with its own configurable target.
- Shows a yellow caution icon when any occupied raid subgroup has no Aura,
  including when multiple Aura players have been placed in the same group.
- Reads chat role responses such as tank, healer, DPS, aura, 1, 2, 3,
  tank aura, healer aura, 13 and 23. The word "looms" is ignored.
- Understands Aura-negation replies such as "DPS no aura", "without aura"
  and "don't have aura". Aura is explicitly removed; a bare "no aura" reply
  is treated as ordinary DPS.
- Opens a live recruitment whisper panel from the WHISPERS button.
- Ignores unrelated whispers and only keeps role/Aura replies or requests asking
  whether the group has room.
- While role listening is active, leader/assist automatically whispers recruits
  when their offered Tank, Healer, DPS or Aura role is already full. Combination
  replies identify both the full role and any offered role still needed.
- Identical capacity replies to the same player are limited to once per two
  minutes, with a minimum 30-second gap if raid needs change.
- While the recruitment window is open, watches every chat channel for posts
  containing LFG + MS + Tank, Healer, DPS or Aura; LFM posts are ignored.
- Displays public-channel matches in a separate cyan Chat Scanner panel attached
  to the right of the recruitment-whisper window, with its own scrolling and
  Invite buttons.
- Lets the Chat Scanner move independently and snap to any edge of the Whispers
  panel; free and docked positions persist after reload.
- Highlights priority Tank, Healer and Aura whispers in gold.
- Detects DPS in longer recruitment whispers such as "DPS LFG MS full looms".
- Uses Ascension's native blue-shield Tank, green-cross Healer and red-swords
  DPS icons, plus item 818059's exact in-game icon for Aura.
- Centers and enlarges visible role icons, including combination roles.
- Keeps up to 50 whispers with mouse-wheel and Older/Newer scrolling.
- Shows nine clean rows per recruitment panel so messages cannot overlap the
  footer controls; longer messages are clipped to one line.
- Highlights Tank rows blue, Healer rows green and Aura rows gold.
- Lets you drag the whisper window and pull its bottom-right grip downward to
  reveal more fixed-size chat rows; the selected height persists after reload.
- Gives every whisper its own Invite button, which invites only that player.
- Chat Scanner Invite buttons save the detected roles before inviting, so the
  player is counted correctly as soon as they join.
- Ignores identical Chat Scanner advertisements repeated by the same player
  within 60 seconds.
- Avoids modifying Blizzard/ElvUI's protected right-click raid menus. Manual
  roles remain available through /msm tank PlayerName, /msm healer PlayerName,
  /msm dps PlayerName and /msm aura PlayerName.
- Keeps the raid owner unassigned until a role is manually selected or detected.
- Shows level 59 players and warns when a player reaches level 60.
- Provides a user-clicked secure kick button for level-60 players without making
  automatic UninviteUnit calls that can taint protected raid controls.
- Warns three times to wipe if a level-60 player enters the next Manastorm.
- Assigns raid markers to Tanks when entering a Manastorm.
- Reports every player's level and role through Raid Warning.
- Provides separate Ready Check and Enter Manastorm 1 buttons for testing.
- Ready Check only checks the current raid and never queues automatically.
- Check Manastorm 1 now performs read-only validation. It never calls
  C_Manastorm.Enter or programmatically clicks Ascension's protected queue
  controls; the final Enter Group Manastorm click must be made on Ascension's UI.
- Ready Check and Manastorm entry do not require a 15-player raid.
- Lets you select one numbered LFM posting channel in Settings, preventing
  multi-channel advertisement spam.
- Recruitment advertisements begin with "[Manastormer] LFM MS".
- Tracks spell 93459, ignores duplicate/same-stack events, uses the configured
  warning interval and announces the final 0 stacks only once per boss.
- Silences automation when you are not raid leader or assistant.
- Does not run Manastorm automation inside ordinary dungeons or raids.
- Supports a compact view with level, departure and missing-role information.

REMOVED IN 2.4.0
- Build Groups and automatic raid-party rearrangement.
- Me: Tank, Me: Healer, Me: DPS and Me: Aura buttons.
- Save/Disband and Reinvite Saved controls.

ROLE COMMANDS
/msm tank PlayerName
/msm healer PlayerName
/msm dps PlayerName
/msm aura PlayerName
/msm clearrole PlayerName

If no player name is supplied, the command uses your current target.

OTHER COMMANDS
/msm listen
/msm pause
/msm clear
/msm api
/msm minimap
/msm whispers

ASCENSION NOTES
- This addon targets Project Ascension's Wrath 3.3.5 client, not Retail WoW.
- Protected group and window actions cannot be changed during combat. If needed,
  Manastormer waits until combat ends.
- Ascension's custom C_Manastorm API is used first for Level 1 entry, with its
  interface controls retained as a fallback.
