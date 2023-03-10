from typing import Optional


def is_photon_os(default_file_name: Optional[str] = "/etc/os-release") -> bool:
    with open(default_file_name) as f:
        if 'Photon' in f.read():
            return True
    return False


print(is_photon_os())
