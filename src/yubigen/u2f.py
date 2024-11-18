from collections import deque
from typing import Deque, Iterable, Optional
from yubikit.core.fido import FidoConnection
from yubikit.management import CAPABILITY

from yubigen.module import Module


MODULE = Module("U2F", FidoConnection, CAPABILITY.FIDO2)


def build_pamu2fcfg_args(
    args: Optional[Iterable[str]] = None,
    user: bool = False,
    /,
    bin: str = "pamu2fcfg",
) -> Deque[str]:
    call = deque() if args is None else deque(args)

    if not user:
        call.append("--nouser")

    call.appendleft(bin)
    return call
