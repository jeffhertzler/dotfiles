"""No root, network, system commands, or gaming-account writes are performed."""
import contextlib
import io
from pathlib import Path
import runpy
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "packages/arch/gaming-flatpak-nvidia.py"
NEW = "runtime/org.freedesktop.Platform.GL.nvidia-580-196-07/x86_64/1.4"
OLD = "runtime/org.freedesktop.Platform.GL.nvidia-580-178-04/x86_64/1.4"


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(SOURCE))
        self.main = self.module["main"]
        self.installed = {OLD}
        self.loaded = "580.178.04\n"
        self.package = "nvidia-580xx-utils 580.196.07-1\n"
        self.calls = []
        self.identities = []
        self.uid = 0
        self.fail_refs = set()
        self.list_fails = False
        self.deploy = True
        self.patches = contextlib.ExitStack()
        self.addCleanup(self.patches.close)
        self.patches.enter_context(patch("os.geteuid", side_effect=lambda: self.uid))
        self.patches.enter_context(patch("os.initgroups", side_effect=lambda *args: self.identities.append(("groups", args))))
        self.patches.enter_context(patch("os.setgid", side_effect=lambda gid: self.identities.append(("gid", gid))))
        self.patches.enter_context(patch("os.setuid", side_effect=self.setuid))
        self.patches.enter_context(patch("os.chdir"))
        self.patches.enter_context(patch("os.umask"))
        self.patches.enter_context(patch("pwd.getpwnam", return_value=SimpleNamespace(pw_name="gaming", pw_uid=1001, pw_gid=1002, pw_dir="/home/gaming")))
        self.patches.enter_context(patch("pathlib.Path.read_text", autospec=True, side_effect=self.read_version))
        self.patches.enter_context(patch("subprocess.run", side_effect=self.run_command))
        self.output = io.StringIO()
        self.patches.enter_context(contextlib.redirect_stdout(self.output))
        self.patches.enter_context(contextlib.redirect_stderr(self.output))

    def setuid(self, uid):
        self.identities.append(("uid", uid))
        self.uid = uid

    def read_version(self, path, *args, **kwargs):
        self.assertEqual(str(path), "/sys/module/nvidia/version")
        if self.loaded is None:
            raise FileNotFoundError()
        return self.loaded

    def run_command(self, argv, **kwargs):
        self.calls.append(argv)
        self.assertEqual(kwargs["stdin"], subprocess.DEVNULL)
        self.assertEqual(kwargs["cwd"], "/")
        env = kwargs["env"]
        self.assertEqual(env["PATH"], "/usr/bin:/bin")
        self.assertNotIn("PYTHONPATH", env)
        self.assertNotIn("LD_PRELOAD", env)
        self.assertNotIn("FLATPAK_GL_DRIVERS", env)
        self.assertNotIn("DBUS_SESSION_BUS_ADDRESS", env)
        if argv[0] == "/usr/bin/pacman":
            self.assertEqual(self.uid, 0)
            self.assertEqual(argv, ["/usr/bin/pacman", "-Q", "nvidia-580xx-utils"])
            return subprocess.CompletedProcess(argv, 0, self.package, "")
        self.assertEqual(self.uid, 1001, "Flatpak must never execute as root")
        self.assertEqual(env["HOME"], "/home/gaming")
        self.assertEqual(env["XDG_DATA_HOME"], "/home/gaming/.local/share")
        self.assertEqual(env["XDG_CONFIG_HOME"], "/home/gaming/.config")
        self.assertEqual(argv[:2], ["/usr/bin/timeout", "--kill-after=10s"])
        self.assertEqual(argv[3], "/usr/bin/flatpak")
        args = argv[4:]
        if args[0] == "list":
            self.assertEqual(args, ["list", "--user", "--runtime", "--columns=ref"])
            # flatpak list omits the runtime/ prefix.
            refs = "\n".join(ref.removeprefix("runtime/") for ref in sorted(self.installed))
            return subprocess.CompletedProcess(argv, int(self.list_fails), refs, "list failed" if self.list_fails else "")
        self.assertEqual(args[:-1], ["install", "--user", "--runtime", "--noninteractive", "--assumeyes", "--no-related", "--no-deps", "flathub"])
        self.assertEqual(argv[2], "180s")
        ref = args[-1]
        if ref in self.fail_refs:
            return subprocess.CompletedProcess(argv, 1, "", "not available/offline")
        if self.deploy:
            self.installed.add(ref)
        return subprocess.CompletedProcess(argv, 0, "installed", "")

    def installs(self):
        return [argv[-1] for argv in self.calls if "install" in argv]

    def test_upgrade_before_reboot_installs_new_keeps_loaded(self):
        self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [NEW])
        self.assertEqual(self.installed, {OLD, NEW})
        self.assertEqual(self.identities, [("groups", ("gaming", 1002)), ("gid", 1002), ("uid", 1001)])

    def test_both_missing_install_both_versions(self):
        self.installed.clear()
        self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [NEW, OLD])

    def test_after_reboot_deduplicates_and_is_idempotent(self):
        self.loaded = "580.196.07\n"
        self.installed.clear()
        self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [NEW])
        self.uid = 0
        self.calls.clear()
        self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [])

    def test_unloaded_module_still_prepares_installed_userspace(self):
        self.loaded = None
        self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [NEW])

    def test_epoch_and_pkgrel_do_not_enter_ref(self):
        self.package = "nvidia-580xx-utils 2:580.196.07-4.1\n"
        self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [NEW])

    def test_downgrade_keeps_both_versions(self):
        self.package = "nvidia-580xx-utils 580.178.04-1\n"
        self.loaded = "580.196.07\n"
        self.installed = {NEW}
        self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [OLD])
        self.assertEqual(self.installed, {OLD, NEW})

    def test_check_reports_missing_without_installing(self):
        self.assertEqual(self.main(["--check"]), 1)
        self.assertIn(NEW, self.output.getvalue())
        self.assertEqual(self.installs(), [])

    def test_check_succeeds_when_both_present(self):
        self.installed.add(NEW)
        self.assertEqual(self.main(["--check"]), 0)
        self.assertEqual(self.installs(), [])

    def test_failure_is_visible_and_does_not_skip_other_version(self):
        self.installed.clear()
        self.fail_refs.add(NEW)
        self.assertEqual(self.main(["--sync"]), 1)
        self.assertEqual(self.installs(), [NEW, OLD])
        self.assertIn("not available/offline", self.output.getvalue())
        self.assertIn("--sync", self.output.getvalue())

    def test_successful_exit_without_deployment_is_not_success(self):
        self.deploy = False
        self.assertEqual(self.main(["--sync"]), 1)
        self.assertIn(NEW, self.output.getvalue())

    def test_unrelated_runtimes_are_untouched(self):
        unrelated = {
            "runtime/org.freedesktop.Platform.GL32.nvidia-580-178-04/x86_64/1.4",
            "runtime/org.freedesktop.Platform.VAAPI.nvidia/x86_64/25.08",
            "runtime/org.gnome.Platform/x86_64/50",
        }
        self.installed.update(unrelated)
        self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [NEW])
        self.assertEqual(self.installed, unrelated | {OLD, NEW})

    def test_inherited_environment_cannot_redirect_commands_or_flatpak(self):
        with patch.dict("os.environ", {
            "PATH": "/tmp/untrusted", "HOME": "/root",
            "XDG_DATA_HOME": "/root/data", "PYTHONPATH": "/tmp/untrusted",
            "LD_PRELOAD": "/tmp/untrusted.so", "FLATPAK_GL_DRIVERS": "bad",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/tmp/untrusted-bus",
        }):
            self.assertEqual(self.main(["--sync"]), 0)
        self.assertEqual(self.installs(), [NEW])

    def test_timeout_exit_is_reported(self):
        original = self.run_command

        def timed_out(argv, **kwargs):
            result = original(argv, **kwargs)
            if "install" in argv:
                return subprocess.CompletedProcess(argv, 124, "", "")
            return result

        with patch("subprocess.run", side_effect=timed_out):
            self.assertEqual(self.main(["--sync"]), 1)
        self.assertIn("exit 124", self.output.getvalue())

    def test_pacman_failure_never_drops_or_installs(self):
        with patch("subprocess.run", return_value=subprocess.CompletedProcess([], 1, "", "package missing")):
            self.assertEqual(self.main(["--sync"]), 1)
        self.assertEqual(self.identities, [])
        self.assertIn("package missing", self.output.getvalue())

    def test_list_failure_does_not_attempt_installs(self):
        self.list_fails = True
        self.assertEqual(self.main(["--sync"]), 1)
        self.assertEqual(self.installs(), [])

    def test_malformed_package_fails_closed(self):
        self.package = "nvidia-580xx-utils bad;version\n"
        self.assertEqual(self.main(["--sync"]), 1)
        self.assertEqual(self.installs(), [])
        self.assertEqual(len(self.calls), 1)

    def test_malformed_loaded_version_fails_closed(self):
        self.loaded = "580.196.07; bad"
        self.assertEqual(self.main(["--sync"]), 1)
        self.assertEqual(self.installs(), [])

    def test_nonroot_refused_before_commands(self):
        self.uid = 1000
        self.assertEqual(self.main(["--sync"]), 1)
        self.assertEqual(self.calls, [])

    def test_privilege_drop_failure_never_runs_flatpak(self):
        with patch("os.setgid", side_effect=PermissionError("drop failed")):
            self.assertEqual(self.main(["--sync"]), 1)
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.installs(), [])

    def test_root_target_account_refused(self):
        with patch("pwd.getpwnam", return_value=SimpleNamespace(pw_name="gaming", pw_uid=0, pw_gid=0, pw_dir="/root")):
            self.assertEqual(self.main(["--sync"]), 1)
        self.assertEqual(self.installs(), [])

    def test_hook_is_narrow_and_executes_only_root_owned_isolated_python(self):
        # Bypass the version-file mock for repository source inspection.
        with open(ROOT / "packages/arch/95-gaming-flatpak-nvidia.hook") as source:
            hook = source.read()
        self.assertIn("Type = Package\nTarget = nvidia-580xx-utils\n", hook)
        self.assertIn("Operation = Install\nOperation = Upgrade\n", hook)
        self.assertNotIn("Operation = Remove", hook)
        self.assertIn("When = PostTransaction", hook)
        self.assertIn("Exec = /usr/bin/python3 -I /usr/local/libexec/gaming-flatpak-nvidia --sync", hook)
        self.assertNotIn("/home/", hook)


if __name__ == "__main__":
    unittest.main()
