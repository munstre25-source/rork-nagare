"""Recover one audited production bundle into a clean local folder."""

import hashlib
import json
import subprocess
import sys
from pathlib import Path


SUPABASE = Path(__file__).resolve().parents[1]
AUDIT = SUPABASE / "audit/production-2026-11-28"


def restore(slug, destination):
    manifest = json.loads((AUDIT / "manifest.json").read_text())["functions"]
    if slug not in manifest:
        raise ValueError("This function is absent from the production snapshot.")
    destination = destination.resolve()
    if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise ValueError("Choose a new or empty directory for the rollback bundle.")

    function = manifest[slug]
    files = {}
    for name, info in function["files"].items():
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or path.parts[0] not in {slug, "_shared"}:
            raise ValueError(f"Invalid source path in the production manifest: {name}")
        if "snapshot" in info:
            content = (AUDIT / info["snapshot"]).read_bytes()
        else:
            content = subprocess.check_output(
                ["git", "cat-file", "blob", info["git_blob"]], cwd=SUPABASE,
            )
        if hashlib.sha256(content).hexdigest() != info["sha256"]:
            raise ValueError(f"Production source checksum mismatch for {name}.")
        files[path] = content

    project = destination / "supabase"
    for relative, content in files.items():
        path = project / "functions" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    verify_jwt = str(function["verify_jwt"]).lower()
    (project / "config.toml").write_text(
        f'project_id = "jojo-rollback"\n\n[functions.{slug}]\nverify_jwt = {verify_jwt}\n'
    )
    print(f"Restored {slug} production version {function['version']} into {destination}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: restore-edge-baseline.py FUNCTION EMPTY_DIRECTORY")
    try:
        restore(sys.argv[1], Path(sys.argv[2]))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
