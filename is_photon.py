import re
from typing import Optional


def is_photon_os(default_file_name: Optional[str] = "/etc/os-release") -> bool:
    with open(default_file_name) as f:
        if 'Photon' in f.read():
            return True
    return False


def read_file(f, err_ret="", no_error=False):
    old_value = err_ret
    try:
        f = open(f, "r")
        old_value = f.read()
        f.close()
    except (OSError, IOError) as e:
        pass
    return old_value


def add_modify_option_woquotes_in_file(f: str, d: dict, add=True):
    data = read_file("/tmp/test")
    for opt in d:
        o = str(opt)
        v = str(d[opt])
        if re.search(r"\b" + o + r"\s*=.*$", data, flags=re.MULTILINE) is None:
            if add:
                if len(data) > 0 and data[-1] != "\n":
                    data += f"\n{o}={v}\n" "%s=%s\n"
        else:
            # filter all empty intel_iommu= value
            filtered_empty = []
            unfiltered_values = v.split()
            for k in unfiltered_values:
                if "=" in k:
                    kv = k.split("=")
                    if len(kv) == 2 and len(kv[1].strip()) > 0:
                        filtered_empty.append(k)
            without_empty = " ".join(filtered_empty)
            data = re.sub(r"\b(" + o + r"\s*=).*$",
                          r"\1" + without_empty, data, flags=re.MULTILINE)

d = {
    'tuned_params': 'skew_tick=1 isolcpus=managed_irq,domain, intel_pstate=disable intel_iommu=on iommu=pt nosoftlockup tsc=reliable transparent_hugepage=never hugepages=16 default_hugepagesz=1G hugepagesz=1G nohz_full= rcu_nocbs=',
    'tuned_initrd': ''}

add_modify_option_woquotes_in_file("/tmp/test", d)
