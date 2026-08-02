# Copy Migration Safety Contract

`development/d724/migrate-careoncloud-brand.sh` is a copy migration tool, not
a production cutover command. Its execute mode is fail-closed:

- `--compose-project` is mandatory, so a Compose file's implicit project name
  cannot accidentally select a running environment.
- `--allow-writer-stop` is a separate explicit acknowledgement before it can
  stop the selected project's web and daemon writers.
- Old application/update volumes must already exist; target volumes must not
  exist. The tool never removes the old volumes.
- The target database must not exist. This prevents an import into an unknown
  or previously used database.
- The logical source dump is non-empty and its SHA-256 is written to
  `migration-result.txt`, together with source/target identifiers and the
  rollback direction.

Before a real run, use plan mode, verify each exact Docker volume and Compose
project, save the dump outside the temporary working directory, and define a
separate restore acceptance. A successful copy is not a cutover or a restore
proof.
