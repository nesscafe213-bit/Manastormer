MANASTORMER 2.8.26
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
- Fixes chat scanning after a raid reset by ignoring Ascension's stale cached
  dungeon-finder state when the player is no longer in an LFG party.
- Keeps the secure Manastorm entry control outside the main panel so minimize,
  expand, open and close requests can safely wait until combat ends.
- Replaces the blocked delayed UninviteUnit calls with an Ascension-safe secure
  disband flow. The first click snapshots and warns the raid; after five seconds
  a red secure control appears for the leader to click out of combat. It verifies
  the removals and prepares another secure batch only if required. Automatic
  reinvites remain armed for after the leader leaves the dungeon.
- Farewell whispers now correctly wish players good luck with their rolls.
  A detected level-59 player who leaves the group also receives the thank-you
  and download message. A 60-second deduplicator prevents double whispers when
  the secure kick and roster departure happen together.
- Prevents the compact/full interface from splitting apart when expanded in
  combat. Opening, closing, minimizing, expanding and page changes now leave
  the current layout untouched during combat and apply automatically afterward.
- Manastormer now starts closed and paused after every login or /reload. Open
  it only when needed with the minimap button or /msm, then press Listen.
- Reloading the UI now starts genuinely paused. Background level watching,
  kick controls, Aura reminders, chat capture, tank markers and Chaotic Link
  reporting stay off until Listen or Role Check is deliberately started. The
  compact panel clearly says PAUSED while monitoring is off.
- Fixes compact view text being crossed by the full-size header divider. The
  divider now hides in compact mode, and the compact panel grows vertically
  when extra alerts need more lines.
- DISBAND + AUTO REINVITE excludes level-60 and blocked players from the saved
  list and automatically waits out combat before arming its secure control.
- Clicking either secure level-59 or level-60 kick button whispers that player
  a thank-you, wishes them good luck with their roles, explains the scaling
  removal and includes the Manastormer GitHub download link.
- Centres the ROLE headings over the complete role-icon cells in both the
  Recruitment Whispers and Chat Scanner panels.
- Fixes the scanner drag-stop and minimap drag callbacks after the 2.8.16
  local-variable compatibility refactor.
- Load hotfix: consolidates internal helpers so Ascension's legacy Lua engine
  stays safely below its 200-local-variable limit. This restores the GUI,
  minimap button and /msm commands after the broken 2.8.15 build.
- Synchronises grouped-player role and Aura assignments between Manastormer
  users. The raid leader supplies the full snapshot; leader/assistant changes
  are shared immediately, and simultaneous requests are throttled.
- Shows a green GUI confirmation naming the detected Manastormer raid leader,
  or identifies you as the sync host when you lead the raid.
- The raid leader posts one normal /raid reminder every two minutes while any
  occupied subgroup has no assigned Aura. This never uses Raid Warning and
  only one addon copy reports it.
- Fully closing the main GUI now puts Manastormer to sleep: recruitment,
  role capture, capacity replies, level actions, markers, alerts and entry/
  ready state are ignored until the main GUI is reopened. Compact view stays active.
- Restores a secure, user-click ENTER MANASTORM 1 button that activates
  Ascension's native entry control without unsafe automatic protected calls.
- Live level-60 actions require the current roster unit to actually be level
  60; cached blocks use exact full names, expire, and clear below level 60.
- Dungeon Finder suspension now recognises actual LFG party/proposal states
  without suspending solo players or Manastorm recruitment.
- Hotfix: Aura sparkle borders are attached to Recruitment Whisper rows and
  refresh safely when older UI rows are present.
- Aura recruitment whispers have an animated gold sparkling border so priority
  Aura applicants stand out immediately.
- Automatically suspends recruitment capture, chat scanning, capacity replies
  and raid automation for Dungeon Finder queues/groups and inside non-Manastorm
  instances, then resumes afterward.
- Compatible with both ElvUI and Ascension's native WoW interface. Manastormer
  never hides or modifies protected raid frames. Manual-role entries are added
  through Ascension's standard unit-popup hook used by both interfaces.
- CoA Planner-inspired navy, bronze and gold interface with matching fonts.
- Custom Manastormer artwork in the window header and on the minimap.
- Draggable minimap button: left-click toggles the GUI and right-click hides it.
- Compact/full view switches immediately during combat; the secure level-60
  fallback remains independently protected by Ascension.
- Quietly exchanges version numbers with grouped Manastormer users and gives a
  local warning when a newer addon version is available.
- Settings includes a Chaotic Link reporting checkbox plus a 1-10 second
  alert-interval slider. Turning reporting off suppresses every Chaotic Link
  warning, including the critical 0-stack warning.
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
- Restores right-click manual role controls for yourself, party members and raid
  members: toggle Tank, Healer, DPS or Aura, or clear all roles. These options
  do not require the player to be in range. Slash-command controls remain
  available as a fallback.
- Keeps the raid owner unassigned until a role is manually selected or detected.
- Shows level 59 players and provides a secure, user-clicked kick button that
  rechecks the player's current grouped level before appearing.
- Warns when a player reaches level 60.
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
