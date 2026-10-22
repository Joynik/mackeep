# Merge settings between machines

Mackeep copies whole files. It does not merge their contents or keep a history
of older snapshots. Restoring a backup can replace settings that exist only
on the destination machine.

1. On each machine, inspect the application's paths with `mackeep-cli show bash`
   (replace `bash` with its identifier).
2. Make a separate copy of each machine's files outside the selected backup
   paths. Keep these copies until you have checked the merged result.
3. Choose one machine and manually merge the settings you want to retain from
   all copies. Exclude machine-specific files or settings where possible.
4. Preview with `mackeep-cli --dry-run backup bash`, then run
   `mackeep-cli backup bash` on that machine.
5. Wait for the storage folder to sync. On each other machine, preview
   `mackeep-cli --dry-run restore bash`, restore with `mackeep-cli restore bash`,
   and check the application before discarding your separate copies.

Use the same storage on each machine and run one operation at a time.
Copy mode requires another backup/restore when settings change; editing one
machine does not automatically update the others.

See [configuration](README.md) for selection, exclusions, and replacement
behavior. In particular, a new successful backup cleans obsolete tracked
paths, so the shared backup folder should not be your only copy during a merge.
