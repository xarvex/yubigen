from pathlib import Path
from typing import Generic, TypeVar, cast, override

from ykman.base import YkmanDevice
from yubikit.core import TRANSPORT, Connection
from yubikit.core.fido import FidoConnection
from yubikit.management import CAPABILITY, DeviceInfo

from yubigen.core import capability_enabled, iter_devices, list_devices, programdirs


T = TypeVar("T", bound=Connection | FidoConnection)


class Module(Generic[T]):
    def __init__(
        self,
        label: str,
        connection: type[T],
        capability: CAPABILITY,
    ) -> None:
        self.label: str = label
        self.connection: type[T] = connection
        self.capability: CAPABILITY = capability

    def list_devices(self):
        return list_devices(self.connection)

    def iter_devices(self, /, abort: bool = False, quiet: bool = False):
        return iter_devices(self.connection, self.capability, abort=abort, quiet=quiet)

    def capability_enabled(self, device_or_transport: YkmanDevice | TRANSPORT, info: DeviceInfo):
        return capability_enabled(self.capability, device_or_transport, info)

    def open_connection(self, device: YkmanDevice) -> T:
        return cast(T, device.open_connection(cast(type[Connection], self.connection)))

    @property
    def basename(self) -> str:
        return str(self).lower()

    @property
    def data_home(self) -> Path:
        return programdirs.user_data_path.joinpath(self.basename)

    @property
    def state_home(self) -> Path:
        return programdirs.user_state_path.joinpath(self.basename)

    @property
    def runtime_home(self) -> Path:
        return programdirs.user_runtime_path.joinpath(self.basename)

    def key_home(self, serial: int, create: bool = False) -> Path:
        dir = self.data_home.joinpath(str(serial))
        if create:
            for parent in reversed(dir.parents):
                parent.mkdir(0o700, exist_ok=True)
            dir.mkdir(0o700, exist_ok=True)

        return dir

    def keygen_home(self, serial: int, create: bool = False) -> Path:
        dir = self.runtime_home.joinpath(str(serial))
        if create:
            for parent in reversed(dir.parents):
                parent.mkdir(0o700, exist_ok=True)
            dir.mkdir(0o700, exist_ok=True)

        return dir

    @override
    def __str__(self) -> str:
        return self.label
