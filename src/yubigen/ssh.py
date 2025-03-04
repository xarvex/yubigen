from collections import deque
from collections.abc import Iterable, Mapping
from pathlib import Path
import re
import shutil
import subprocess
from typing import TYPE_CHECKING, Any

from ykman.base import YkmanDevice
from yubikit.core.fido import FidoConnection
from yubikit.management import CAPABILITY, DeviceInfo

from yubigen.module import Module

StrOrBytesPath = Any
if TYPE_CHECKING:
    from _typeshed import StrOrBytesPath


MODULE = Module("SSH", FidoConnection, CAPABILITY.FIDO2)
key_reg = re.compile(r"id_[^_]+_sk(?:_rk)?(?:_(.+))?(?<!\.pub)")


def write_config(
    serial: int,
    applications: Mapping[str, str | Iterable[str]] | None = None,
    explicit_applications: bool = False,
) -> None:
    host_keys: dict[str, list[Path]] = {}
    dir = MODULE.key_home(serial, True)
    try:
        for path in dir.iterdir():
            match = key_reg.fullmatch(path.name)
            if match is not None:
                groups = match.groups()
                if len(groups) > 0:
                    application = "" if groups[0] is None else groups[0]
                    hosts: Iterable[str] = []
                    if applications is not None and application in applications:
                        entry = applications[application]
                        hosts = [entry] if isinstance(entry, str) else entry
                    elif not explicit_applications and len(application) > 1:
                        hosts = [application]

                    for host in hosts:
                        if host not in host_keys:
                            host_keys[host] = []
                        host_keys[host].append(path)
    except FileNotFoundError:
        pass

    path = dir.joinpath("ssh_config.new")
    with open(path, "w+") as file:
        for host, paths in host_keys.items():
            _ = file.write(f"Host {host}\n")
            file.writelines(map(lambda path: f"  IdentityFile {str(path)}\n", paths))
    shutil.move(path, path.with_name("ssh_config"))


def register_device(device_name: str, serial: int) -> None:
    path = MODULE.state_home.joinpath(f"config_{device_name}.new")
    for parent in reversed(path.parents):
        parent.mkdir(0o700, exist_ok=True)

    path.symlink_to(MODULE.key_home(serial, True).joinpath("ssh_config"))
    shutil.move(path, path.with_name(f"config_{device_name}"))


def unregister_device(device_name: str) -> None:
    MODULE.state_home.joinpath(f"config_{device_name}").unlink(missing_ok=True)


def build_ssh_keygen_args(
    args: Iterable[str] | None = None,
    options: Iterable[str] | None = None,
    device_or_device_path: YkmanDevice | StrOrBytesPath | None = None,
    /,
    bin: str = "ssh-keygen",
) -> deque[str]:
    call: deque[str] = deque() if args is None else deque(args)

    if options is not None:
        for option in options:
            call.extend(["-O", option])
    if device_or_device_path is not None:
        device_path = device_or_device_path.fingerprint if isinstance(device_or_device_path, YkmanDevice) else device_or_device_path
        call.extend(["-O", f"device={device_path}"])

    call.appendleft(bin)
    return call


def create_key(device: YkmanDevice, info: DeviceInfo, application: str | None) -> None:
    assert info.serial is not None

    options = ["resident", "verify-required"]

    algorithm = "ed25519-sk"
    if application is None:
        application = ""
    else:
        options.append(f"application=ssh:{application}")
    filename = (
        f"id_{algorithm.rstrip('-sk')}"
        + ("_sk" if algorithm.endswith("-sk") else "")
        + ("_rk" if "resident" in options else "")
        + (f"_{application}" if len(application) > 0 else "")
    )
    comment = f"ssh:{application}"

    dir = MODULE.key_home(info.serial, True)
    _ = subprocess.run(
        build_ssh_keygen_args(["-t", algorithm, "-f", filename, "-C", comment], options, device),
        cwd=dir,
    )


def download_keys(device: YkmanDevice, info: DeviceInfo) -> None:
    assert info.serial is not None

    gen_dir = MODULE.keygen_home(info.serial, True)
    for path in gen_dir.iterdir():
        path.unlink(missing_ok=True)

    _ = subprocess.run(build_ssh_keygen_args(["-K"], None, device), cwd=gen_dir)

    dir = MODULE.key_home(info.serial, True)
    for path in dir.iterdir():
        path.unlink(missing_ok=True)
    for path in gen_dir.iterdir():
        shutil.move(path, dir.joinpath(path.name))
