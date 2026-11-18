# Changelog

## [0.1.22] - 2026-11-18

- Capture duration initiative from the active Combat Tracker actor when a cast starts, preserving it through chooser steps and reaction casts.
- Set Summoned Creature Initiative Adjust to that snapshot; Spiritual Weapon uses a 0.1 offset for turn-end expiration. Align newly created caster concentration effects with the same cast-time initiative. Existing timers retain their prior initiative.
- Correct Spiritual Weapon slot 2/3 notices: both use the base 1d8; damage increases by another d8 at slots 4, 6, and 8. Keep notices short enough for the chooser.

## [0.1.21] - 2026-11-18

- Restore Spiritual Weapon’s Incapacitated effect while retaining NOREACTION.
- Lock summon NPC sheets before sharing, including Pets-linked records. Repair existing managed sheets on reload.
- Add a Summoned Creature duration effect to temporary summons; its expiration removes the CT entry and linked Pets record.
- Apply one-hour short rests and eight-hour long rests to summon timers, including player-initiated caster rests, without double-counting party rests.
- Remove the duration effect without dismissing a summon when concentration loss makes it hostile; retain manual handling for delayed disappearance.
- Preserve remaining rounds when migrating existing duration links. Keep permanent creatures and Gate arrivals outside lifetime expiration; give ordinary Druid Grove guardians a 24-hour timer.

## [0.1.20] - 2026-11-18

- Integrate newly created, auto-assigned friendly summons with the optional Pets extension, using the caster’s cohort record as the Combat Tracker source.
- Remove that Pets record when the summon leaves the tracker; detach hostile summons from Pets while retaining GM control.
- Continue the normal summon and sheet-sharing workflow when Pets is absent.

## [0.1.19] - 2026-11-18

- Fix Auto Assign Summoned NPC granting access without opening the NPC sheet for the caster’s player. The live Combat Tracker sheet is now shared directly with that player using Fantasy Grounds’ standard window sharing.
- Keep manual assignment (Off), hostile summons, and GM-owned casters unchanged.

## [0.1.18] - 2026-11-17

First GitHub release.

- Includes 36 5E Legacy spell profiles, GM and player selection, slot handling, concentration, and Combat Tracker integration.
- Includes spell-specific chat and chooser icons, the Quick Summon load announcement icon, and the optional Spiritual Weapon map token.
- Includes the full usage guide, Turkish guide, and illustrated spell icon catalogue.

[0.1.18]: https://github.com/alperozisik/FG-Quick-Summon/releases/tag/v0.1.18

[0.1.19]: https://github.com/alperozisik/FG-Quick-Summon/releases/tag/v0.1.19

[0.1.20]: https://github.com/alperozisik/FG-Quick-Summon/releases/tag/v0.1.20

[0.1.21]: https://github.com/alperozisik/FG-Quick-Summon/releases/tag/v0.1.21

[0.1.22]: https://github.com/alperozisik/FG-Quick-Summon/releases/tag/v0.1.22
