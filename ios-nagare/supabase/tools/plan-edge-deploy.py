"""Print the production Edge Functions affected by a Git push."""

import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from urllib.parse import unquote, urlsplit


PROJECT = Path(__file__).resolve().parents[2]
FUNCTIONS = PROJECT / "supabase/functions"
CONFIG = PROJECT / "supabase/config.toml"
DENO_CONFIG = FUNCTIONS / "deno.json"
SLUG = re.compile(r"[a-z][a-z0-9-]*")


def git(*args):
    return subprocess.check_output(("git", *args), cwd=PROJECT)


def function_settings(toml):
    return tomllib.loads(toml).get("functions", {})


def runtime_file(path):
    return path.suffix.lower() != ".md" and not path.name.endswith(
        ("_test.ts", ".test.ts"),
    )


def dependencies(entry):
    graph = json.loads(subprocess.check_output(
        ["deno", "info", "--config", str(DENO_CONFIG), "--frozen-lockfile", "--json", str(entry)],
        cwd=PROJECT,
    ))
    for module in graph["modules"]:
        url = urlsplit(module["specifier"])
        if url.scheme == "file":
            yield Path(unquote(url.path))


def plan(before, after):
    repo = Path(git("rev-parse", "--show-toplevel").decode().strip())
    if git("rev-parse", "HEAD").decode().strip() != after:
        raise ValueError("Checkout does not match the push revision.")
    git("merge-base", "--is-ancestor", before, after)

    settings = function_settings(CONFIG.read_text())
    entries = {
        entry.parent.name: entry
        for entry in FUNCTIONS.glob("*/index.ts")
        if not entry.parent.name.startswith("_")
    }
    if set(settings) != set(entries) or any(
        not SLUG.fullmatch(name) or type(config.get("verify_jwt")) is not bool
        for name, config in settings.items()
    ):
        raise ValueError("Every function must have its own explicit verify_jwt setting.")

    previous_file = subprocess.run(
        ["git", "show", f"{before}:{CONFIG.relative_to(repo).as_posix()}"],
        cwd=PROJECT,
        capture_output=True,
    )
    previous = function_settings(previous_file.stdout.decode()) if previous_file.returncode == 0 else {}
    if previous.keys() - settings.keys():
        raise ValueError("Function removal requires a separate production review.")

    changed = {
        repo / path.decode()
        for path in git("diff", "--name-only", "--no-renames", "--no-relative", "-z", before, after, "--",
                        ":(top)" + FUNCTIONS.relative_to(repo).as_posix()).split(b"\0")
        if path
    }
    runtime_changes = {path for path in changed if runtime_file(path)}
    targets = {name for name, config in settings.items()
               if name in previous and config != previous[name]}
    shared = {path for path in runtime_changes if path.relative_to(FUNCTIONS).parts[0] == "_shared"}
    for name, entry in entries.items():
        direct = any(entry.parent in path.parents for path in runtime_changes)
        if direct or (shared and shared.intersection(dependencies(entry))):
            targets.add(name)
    if previous and runtime_changes.intersection({DENO_CONFIG, FUNCTIONS / "deno.lock"}):
        targets.update(entries)

    return [{"name": name, "verify_jwt": settings[name]["verify_jwt"]} for name in sorted(targets)]


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("Usage: plan-edge-deploy.py BEFORE_SHA HEAD_SHA")
        print(json.dumps(plan(*sys.argv[1:]), separators=(",", ":")))
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
