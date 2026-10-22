#!/bin/sh
# Disposable HOME is supplied by the UI test, never the user's HOME.
set -eu
mkdir -p "$HOME/.mackeep"
if [ ! -f "$HOME/.mackeep.cfg" ]; then
    printf '[storage]\nengine = unconfigured\n[applications_to_sync]\n' > "$HOME/.mackeep.cfg"
fi
case "${2:-}" in
    config)
        printf '{"schema_version":4,"version":"test","config_file":"%s/.mackeep.cfg","custom_apps_dir":"%s/.mackeep","custom_apps_dirs":[],"apps_to_sync":[],"apps_to_ignore":[],"global_exclude":[],"storage":{"engine":"unconfigured","path":"","directory":"Mackeep","resolved_backup_dir":"","exists":false}}\n' "$HOME" "$HOME"
        ;;
    list)
        if [ -f "$HOME/.mackeep/new-app.cfg" ]; then
            printf '[{"schema_version":4,"name":"new-app","display_name":"New App","source":"custom","cfg_path":"%s/.mackeep/new-app.cfg","files":[],"xdg_files":[],"exclude":[],"xdg_exclude":[]}]\n' "$HOME"
        else
            printf '[]\n'
        fi
        ;;
    *) printf 'Mackeep test\n';;
esac
