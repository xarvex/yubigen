from collections import deque
from collections.abc import Iterable
from yubikit.core.fido import FidoConnection
from yubikit.management import CAPABILITY

from yubigen.module import Module


MODULE = Module("U2F", FidoConnection, CAPABILITY.FIDO2)


def build_pamu2fcfg_args(
    args: Iterable[str] | None = None,
    user: bool = False,
    /,
    bin: str = "pamu2fcfg",
) -> deque[str]:
    call: deque[str] = deque() if args is None else deque(args)

    if not user:
        call.append("--nouser")

    call.appendleft(bin)
    return call
