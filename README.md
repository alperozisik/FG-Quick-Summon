# Quick Summon

<img src="art/branding/quick_summon.png" alt="Quick Summon" width="112" />

Summon and manage creatures from the **Actions** tab in **Fantasy Grounds Unity 5E Legacy (2014)**. Quick Summon handles creature selection, spell slots, the Combat Tracker, and spell-specific scaling for **36 spell profiles**.

[Download the latest release](https://github.com/alperozisik/FG-Quick-Summon/releases/latest) · [Türkçe](README.tr.md) · [Changelog](CHANGELOG.md)

## Installation

1. Download `QuickSummon.ext` from [Releases](https://github.com/alperozisik/FG-Quick-Summon/releases) and copy it to your Fantasy Grounds data folder under `extensions/`.
2. For the custom **Spiritual Weapon** map token, download `Spiritual_Weapon.png` from the same release. Create `tokens/QuickSummon/` under the Fantasy Grounds data folder and place the PNG there.
3. Enable **Quick Summon** in the campaign launcher. Use a **5E Legacy** campaign and load the NPC modules you want to use on the GM side.
4. Enable [Initiative Nanny](https://forge.fantasygrounds.com/shop/items/2089/view) if you want `AFTERTURN` and `SHARETURN` to control initiative order.

The chat announces **Quick Summon v0.1.18 loaded.** with the extension icon. For updates to an open campaign, replace the package and use `/reload` when you are ready.

## Casting a spell

1. Open the caster’s character sheet and use **Actions → Cast** on a supported spell. Quick Summon matches the spell name and checks the recorded base level when available.
2. Choose a slot or a ritual if offered. The lowest usable slot is selected by default. Empty slots stay visible and disabled where the slot picker applies. The upcast note shows changes at the chosen level and calls out levels with no additional benefit.
3. Choose any parameters the caster controls, such as the number and CR combination or a spirit’s form. When the GM chooses the creature, the GM receives a separate selection step. A step with a single valid outcome can resolve automatically.
4. **Confirm** adds the summon to the Combat Tracker. Quick Summon spends the selected slot, reports it in chat, and adds any supported concentration or duration effect. The GM can then drag the token from the tracker onto the map.

**Cancel** or the close button stops a pending summon before confirmation. Counterspell follows the table’s normal procedure. Close the pending summon if the spell is countered and apply slot use as part of that procedure.

### Choosing creatures

- **Refresh** rescans the host’s loaded NPC modules and updates slot availability. It clears the current creature selection.
- **Select randomly** appears when at least two eligible choices are available. The result stays editable and waits for **Confirm**. For **Animate Objects**, it finds a combination that spends the entire size budget when possible and otherwise uses the highest reachable amount.
- The GM can open an NPC’s source sheet using the shortcut to the left of its name. The player’s list shows creature names, types, and CRs where available. It contains no links to the source sheets.
- The catalogue includes modules loaded by the GM, including modules the player cannot open. Eligible creature names from those modules can appear in a player’s chooser.
- A matching NPC record must be present in a loaded module. Some spirit forms use named templates supplied by the corresponding rules module or an automation module. The extension contains the rules and artwork used to run the flow.

## Combat Tracker and ownership

- **Options → Quick Summon → Auto Assign Summoned NPC** defaults to **On**. Friendly summons are assigned to the player who controls the caster. Set it to **Off** to assign them manually.
- If the caster already has initiative, the summon uses the spell’s initiative behavior. Spells can roll individually, roll once for the summoned group, or use the caster’s value. Quick Summon supplies the caster link for `AFTERTURN` and `SHARETURN` effects.
- **Find Familiar** adds a persistent `Familiar` effect to the new CT entry.
- **Spiritual Weapon** shares the caster’s turn through `SHARETURN`. Its **Spiritual Weapon Strike** bonus action appears in the NPC sheet and CT with the caster’s spell attack bonus, force damage, and Legacy upcast scaling. Its movement is 20 ft. and the CT entry carries `NOREACTION`. The caster must be on the tracker.
- Scaled spirits use the selected slot for AC and hit points and take their spell attack bonus, save DC, and proficiency from the caster. How much action text can be scaled depends on the module’s stat block wording.

## Supported spells

| Group | Profiles |
| --- | --- |
| Conjuration and calling | Conjure Animals, Conjure Celestial, Conjure Elemental, Conjure Fey, Conjure Minor Elementals, Conjure Woodland Beings, Gate, Infernal Calling, Planar Ally, Summon Greater Demon, Summon Lesser Demons |
| Scaling spirits | Spirit of Death, Summon Aberration, Summon Beast, Summon Celestial, Summon Construct, Summon Draconic Spirit, Summon Elemental, Summon Fey, Summon Fiend, Summon Shadowspawn, Summon Undead |
| Familiars and mounts | Find Familiar, Find Greater Steed, Find Steed, Flock of Familiars, Phantom Steed |
| Animation and creation | Animate Dead, Animate Objects, Create Homunculus, Create Magen, Create Undead, Danse Macabre, Druid Grove, Tiny Servant |
| Spell effect | Spiritual Weapon |

### Scope and manual rulings

- Quick Summon uses the 2014 rules. 2024 spell automation and polymorph-style transformations are outside its scope.
- Animate Dead and Create Undead automate new creatures. Resolve renewal of control manually.
- Gate covers its named-creature use, and Druid Grove covers Grove Guardians.
- Awaken, Simulacrum, Finger of Death, and Negative Energy Flood do not have a Quick Summon flow.
- Concentration spells require the caster to be on the tracker. The GM handles targeting and map placement, material requirements, terrain, special command or control checks, and other case-specific rulings.

## Icons Preview

The 36 spell icons are shown below. Chat uses **40 × 40 px** icons. The chooser uses **96 × 96 px** icons, and Spiritual Weapon uses a **256 × 256 px** map token.

![Quick Summon Icons Preview showing all 36 spell icons](docs/assets/spell-icons-preview.png)

## Build and release

Run `python build_release.py` from the repository root. The `release/` directory receives the installable extension, the optional map token, and their SHA-256 checksums. The build uses Python’s standard library.

For a new release, update the extension manifest, announcement, guides, and changelog together. Push the source commit and a matching `vX.Y.Z` tag to the SSH remote. GitHub Actions checks the tag against the manifest and publishes the release files. See [Release instructions](AGENTS.md).

## License

[MIT](LICENSE). Fantasy Grounds, D&D, and third-party modules are separate products.
