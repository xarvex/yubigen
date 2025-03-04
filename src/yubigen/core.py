from collections.abc import Generator
from typing import cast

from click.termui import secho
from click.utils import echo
from platformdirs import PlatformDirs
from ykman.base import YkmanDevice
from ykman.device import list_all_devices
from yubikit import support
from yubikit.core import PID, TRANSPORT, YUBIKEY, Connection
from yubikit.core.fido import FidoConnection
from yubikit.management import CAPABILITY, DeviceInfo


programdirs = PlatformDirs("yubigen", "Xarvex", ensure_exists=True)


def list_devices(
    connection: type[Connection | FidoConnection],
    /,
    abort: bool = False,
    quiet: bool = False,
) -> list[tuple[YkmanDevice, DeviceInfo]]:
    device_list = list_all_devices([cast(type[Connection], connection)])

    if len(device_list) < 1:
        if not quiet:
            secho("No devices found, nothing to do!", err=True, fg="red")
        if abort:
            exit(1)
    elif not quiet:
        echo(f"Operating on {len(device_list)} device{'' if len(device_list) == 1 else 's'}...")

    return device_list


def iter_devices(
    connection: type[Connection | FidoConnection],
    capability: CAPABILITY | None = None,
    /,
    abort: bool = False,
    quiet: bool = False,
) -> Generator[tuple[YkmanDevice, DeviceInfo], None, None]:
    device_list = list_devices(connection, abort, quiet)
    skipped = 0

    for device, info in device_list:
        if not quiet:
            display_name(device, info)

        if info.serial is None:
            if not quiet:
                secho("Skipping device as it has no serial number.", err=True, fg="blue")
            skipped += 1
        elif capability is None or capability_enabled(capability, device, info):
            yield device, info
        else:
            if not quiet:
                secho(f"Skipping device as {capability.display_name} over {device.transport} is disabled.", err=True, fg="blue")
            skipped += 1

    if skipped != 0 and skipped == len(device_list):
        if not quiet:
            secho("No devices left to act on, nothing to do!", err=True, fg="red")
        if abort:
            exit(1)


def capability_enabled(
    capability: CAPABILITY,
    device_or_transport: YkmanDevice | TRANSPORT,
    info: DeviceInfo,
) -> bool:
    enabled = info.config.enabled_capabilities.get(
        device_or_transport.transport if isinstance(device_or_transport, YkmanDevice) else device_or_transport
    )
    return enabled is not None and enabled & capability == capability


def display_name(
    device_or_pid_or_yubikey_type: YkmanDevice | PID | YUBIKEY,
    info: DeviceInfo,
) -> None:
    pid_or_yubikey_type = (
        device_or_pid_or_yubikey_type.pid if isinstance(device_or_pid_or_yubikey_type, YkmanDevice) else device_or_pid_or_yubikey_type
    )
    yubikey_type = pid_or_yubikey_type.yubikey_type if isinstance(pid_or_yubikey_type, PID) else pid_or_yubikey_type

    echo("\nDevice: ", nl=False)
    secho(support.get_name(info, yubikey_type), nl=False, fg="green")
    echo(" (SN: ", nl=False)
    secho("-" if info.serial is None else info.serial, nl=False, fg="red" if info.serial is None else "green")
    echo(")")
