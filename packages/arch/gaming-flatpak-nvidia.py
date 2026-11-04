#!/usr/bin/python3 -I
"""Ensure only gaming's exact NVIDIA GL refs; deployed as a root-owned ALPM helper."""
import argparse
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys

PACKAGE = "nvidia-580xx-utils"
VERSION = r"[0-9]+\.[0-9]+(?:\.[0-9]+)?"
BASE_ENV = {"PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"}
RETRY = "/usr/bin/python3 -I /usr/local/libexec/gaming-flatpak-nvidia --sync"


def run(argv, env, timeout=20):
    return subprocess.run(
        argv, env=env, cwd="/", stdin=subprocess.DEVNULL,
        capture_output=True, text=True, timeout=timeout,
    )


def required_refs():
    # Query installed userspace, not nvidia-smi (which can fail pre-reboot) or
    # modinfo (which describes an on-disk module, not the loaded one).
    package = run(["/usr/bin/pacman", "-Q", PACKAGE], BASE_ENV)
    match = re.fullmatch(
        rf"{PACKAGE} (?:[0-9]+:)?({VERSION})-[0-9]+(?:\.[0-9]+)*",
        package.stdout.strip(),
    )
    if package.returncode or not match:
        raise RuntimeError(f"Cannot determine installed {PACKAGE} version: {package.stderr.strip() or package.stdout.strip()}")
    versions = [match[1]]
    try:
        loaded = Path("/sys/module/nvidia/version").read_text().strip()
    except FileNotFoundError:
        loaded = None  # Module not loaded: still prepare the next boot's ref.
    if loaded is not None:
        if not re.fullmatch(VERSION, loaded):
            raise RuntimeError(f"Invalid loaded NVIDIA version: {loaded!r}")
        versions.append(loaded)
    print(f"gaming NVIDIA GL: installed={versions[0]}, loaded={loaded or 'not loaded'}", flush=True)
    return [
        f"runtime/org.freedesktop.Platform.GL.nvidia-{version.replace('.', '-')}/x86_64/1.4"
        for version in dict.fromkeys(versions)
    ]


def become_gaming():
    account = pwd.getpwnam("gaming")
    if account.pw_uid <= 0 or account.pw_gid <= 0 or not account.pw_dir.startswith("/") or account.pw_dir == "/":
        raise RuntimeError("Refusing unsafe gaming account identity/home")
    # Drop supplementary groups and all root IDs before touching user-controlled
    # Flatpak configuration/remotes. No user shell, user script, or session bus.
    os.initgroups("gaming", account.pw_gid)
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)
    home = account.pw_dir
    return {
        **BASE_ENV, "HOME": home, "USER": "gaming", "LOGNAME": "gaming",
        "XDG_CONFIG_HOME": f"{home}/.config",
        "XDG_DATA_HOME": f"{home}/.local/share",
        "XDG_CACHE_HOME": f"{home}/.cache",
    }


def flatpak(args, env, seconds=20):
    # timeout also terminates child processes; nothing can wait for input.
    return run(
        ["/usr/bin/timeout", "--kill-after=10s", f"{seconds}s", "/usr/bin/flatpak", *args],
        env, timeout=seconds + 20,
    )


def installed_refs(env):
    result = flatpak(["list", "--user", "--runtime", "--columns=ref"], env)
    if result.returncode:
        raise RuntimeError(f"Cannot list gaming runtimes (exit {result.returncode}): {result.stderr.strip()}")
    return {f"runtime/{line.strip()}" for line in result.stdout.splitlines() if line.strip()}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report missing refs without installing")
    mode.add_argument("--sync", action="store_true", help="install missing exact refs only")
    args = parser.parse_args(argv)
    try:
        if os.geteuid() != 0:
            raise RuntimeError("Run the reviewed root-owned helper as root; it drops to gaming before Flatpak")
        os.chdir("/")
        os.umask(0o022)
        refs = required_refs()
        env = become_gaming()
        present = installed_refs(env)
        missing = [ref for ref in refs if ref not in present]
        if args.check:
            for ref in missing:
                print(f"Missing: {ref}", file=sys.stderr)
            return int(bool(missing))
        failed = False
        for ref in missing:
            print(f"Installing missing gaming runtime: {ref}", flush=True)
            result = flatpak([
                "install", "--user", "--runtime", "--noninteractive", "--assumeyes",
                "--no-related", "--no-deps", "flathub", ref,
            ], env, seconds=180)
            if result.returncode:
                failed = True
                print(f"Failed {ref} (exit {result.returncode}): {result.stderr.strip()} {result.stdout.strip()}", file=sys.stderr)
        if missing:
            remaining = set(refs) - installed_refs(env)
            if failed or remaining:
                raise RuntimeError(f"NVIDIA runtime sync incomplete; missing: {', '.join(sorted(remaining)) or 'none; inspect install errors'}")
        print("gaming NVIDIA GL refs are present; no apps or existing runtimes updated.")
        return 0
    except (OSError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"WARNING: {error}\nHost upgrade is not rolled back. Retry after resolving the error: {RETRY}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
