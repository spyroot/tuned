import glob
import os.path
import re

import tuned.logs
from tuned.utils.commands import commands
from . import base

log = tuned.logs.get()


class SysfsPlugin(base.Plugin):
    """
    `sysfs`::

    Sets various `sysfs` settings specified by the plug-in options.
    +
    The syntax is `_name_=_value_`, where
    `_name_` is the `sysfs` path to use and `_value_` is
    the value to write. The `sysfs` path supports the shell-style
    wildcard characters (see `man 7 glob` for additional detail).
    +
    Use this plugin in case you need to change some settings that are
    not covered by other plug-ins. Prefer specific plug-ins if they
    cover the required settings.
    +
    .Ignore corrected errors and associated scans that cause latency spikes
    ====
    ----
    [sysfs]
    /sys/devices/system/machinecheck/machinecheck*/ignore_ce=1
    ----
    ====
    """

    # TODO: resolve possible conflicts with sysctl settings from other plugins
    def __init__(self, *args, **kwargs):
        super(SysfsPlugin, self).__init__(*args, **kwargs)
        self.sysfs = None
        self.sysfs_original = None
        self._has_dynamic_options = True
        self._cmd = commands()

    def _instance_init(self, instance):
        instance._has_dynamic_tuning = False
        instance._has_static_tuning = True
        instance.sysfs = dict(
            [(os.path.normpath(key_value[0]), key_value[1])
             for key_value in list(instance.options.items())])
        instance.sysfs_original = {}

    def _instance_cleanup(self, instance):
        pass

    def _instance_apply_static(self, instance):
        for key, value in list(instance.sysfs.items()):
            v = self._variables.expand(value)
            for f in glob.iglob(key):
                if self._check_sysfs(f):
                    instance.sysfs_original[f] = self._read_sysfs(f)
                    self._write_sysfs(f, v)
                else:
                    log.error("rejecting write to '%s' (not inside /sys)" % f)

    def _instance_verify_static(self, instance, ignore_missing, devices):
        ret = True
        for key, value in list(instance.sysfs.items()):
            v = self._variables.expand(value)
            for f in glob.iglob(key):
                if self._check_sysfs(f):
                    curr_val = self._read_sysfs(f)
                    if not self._verify_value(f, v, curr_val, ignore_missing):
                        ret = False
        return ret

    def _instance_unapply_static(self, instance, full_rollback=False):
        for key, value in list(instance.sysfs_original.items()):
            self._write_sysfs(key, value)

    @staticmethod
    def _check_sysfs(sysfs_file):
        return re.match(r"^/sys/.*", sysfs_file)

    def _read_sysfs(self, sysfs_file):
        data = self._cmd.read_file(sysfs_file).strip()
        if len(data) > 0:
            return self._cmd.get_active_option(data, False)
        else:
            return None

    def _write_sysfs(self, sysfs_file, value):
        return self._cmd.write_to_file(sysfs_file, value)

    def _instance_unapply_dynamic(self, instance, device):
        pass

    def _instance_update_dynamic(self, instance, device):
        pass
