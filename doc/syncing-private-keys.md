# Backing up private keys

Mackeep does not encrypt backups. Built-in SSH selects `config` and
`authorized_keys`; GnuPG selects `gpg-agent.conf` and `gpg.conf`. Private key
directories are not selected by those built-in definitions.
Sensitive-path warnings are advisory and are not a complete secret detector.

To deliberately include your entire SSH directory, create
`~/.mackeep/ssh.cfg`:

```ini
[application]
name = SSH

[configuration_files]
.ssh
```

A custom definition replaces the built-in one. Preview with
`mackeep-cli --json --dry-run backup ssh --detail files` before backing up.
This can include private keys, host configuration, and other local state.
Use storage whose access and encryption meet your requirements.

Copied files are restricted to owner access, but this does not encrypt them or
control access through a cloud provider. See [sensitive files](README.md#sensitive-files)
and [custom applications](README.md#custom-applications).
