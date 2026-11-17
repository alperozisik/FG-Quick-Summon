# Quick Summon release workflow

- This checkout is the source of truth for Quick Summon. Use the SSH origin `git@github.com:alperozisik/FG-Quick-Summon.git` for Git operations.
- Every release must update GitHub and the local Fantasy Grounds extension. Keep the manifest version, load announcement, both READMEs, and changelog in sync.
- Regenerate `docs/assets/spell-icons-preview.png` when the spell artwork changes. Keep map-token assets separate from the extension archive.
- Run `python build_release.py --tag vX.Y.Z` and the relevant behavior checks before release.
- Install `release/QuickSummon.ext` in the Fantasy Grounds `extensions` directory and verify its checksum. Update `tokens/QuickSummon/Spiritual_Weapon.png` if the artwork changed. The user controls `/reload`.
- Commit the source and documentation and push the commit plus the corresponding tag over SSH. The tag workflow publishes the GitHub Release and its assets. Check that the release exists and its artifacts match the local build.
- Release archives contain project files only. Keep campaign databases, logs, local configuration, and credentials out of this repository.
