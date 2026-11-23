# Changelog

## [0.1.24] - 2026-11-23

- Preserve summon concentration links across [Polymorphism](https://forge.fantasygrounds.com/shop/items/156/view) CT swaps and recognize the original caster in Wild Shape.
- Identify failed concentration saves, replacement spells, fatal or dropping damage, duration expiry, and unclassified removals in the optional GM confirmation.
- Add the host-only `/undounsummon` command for the last Quick Summon removal group, with session-only snapshots.
- Include [5e Undo Last Damage/Heal](https://forge.fantasygrounds.com/shop/items/719/view) compatibility for damage undo on the current Wild Shape form.

Live check on FG 5.1.16 found two remaining issues in v0.1.24: AFTERTURN disappeared on Wild Shape activation, and 5e Undo reported completion while the form retained its wounds.

## [0.1.23] - 2026-11-18

- Filter Conjure Elemental GM candidates by the caster’s selected element, retaining type, CR/upcast, swarm and template restrictions. Support explicit element tags, element names, and known Legacy elemental families; omit unclassified records.
- Display the chosen element in the GM selection message and empty-list notice. Leave other elemental spells unchanged.
- Fix caster rests dismissing Conjure Elemental/Conjure Fey before control can break. Short and long rests now make these creatures hostile, remove their lifetime timer, and preserve the CT entry, including summon-first party-rest order and player-initiated rests.

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

- Integrate newly created, auto-assigned friendly summons with the optional [Pets](https://forge.fantasygrounds.com/shop/items/1960/view) extension, using the caster’s cohort record as the Combat Tracker source.
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

[0.1.23]: https://github.com/alperozisik/FG-Quick-Summon/releases/tag/v0.1.23

[0.1.24]: https://github.com/alperozisik/FG-Quick-Summon/releases/tag/v0.1.24
