from collections import deque
from os import getenv
from pathlib import Path
import shutil
import subprocess
from typing import Deque, Iterable, Iterator, Optional

from click.termui import confirm, secho
from click.utils import echo
import gpg
from gpg.errors import KeyNotFound
from yubikit.core.smartcard import SmartCardConnection
from yubikit.management import CAPABILITY
from yubigen.module import Module


MODULE = Module("PGP", SmartCardConnection, CAPABILITY.OPENPGP)


class GpgTransferInteraction:
    current = 0
    completed = False

    def __init__(self, subkeys) -> None:
        self.subkeys = subkeys

    def get_subkey(self):
        return self.subkeys[self.current]

    def get_slot(self) -> Optional[str]:
        subkey = self.get_subkey()
        if subkey.can_sign == 1:
            return "1"
        elif subkey.can_encrypt == 1:
            return "2"
        elif subkey.can_authenticate == 1:
            return "3"

    def complete(self) -> None:
        self.completed = True

    def interact_callback(self, keyword: str, args: str) -> Optional[str]:
        if keyword == "GET_LINE":
            if args == "cardedit.genkeys.storekeytype":
                return self.get_slot()
            if args == "keyedit.prompt":
                if self.completed:
                    try:
                        return f"key {next(self)}"
                    except StopIteration:
                        return "quit"

                self.complete()
                return "keytocard"
        if keyword == "GET_BOOL":
            if args == "cardedit.genkeys.replace_key":
                return "y" if confirm(f"Replace existing key in slot {self.get_slot()}?") else "n"
            if args == "keyedit.keytocard.use_primary":
                return "y"
            if args == "keyedit.save.okay":
                return "n"

    def __iter__(self) -> Iterator:
        self.current = 0

        return self

    def __len__(self) -> int:
        return len(self.subkeys)

    def __next__(self) -> int:
        self.completed = False
        self.current += 1

        if self.current < len(self):
            return self.current
        else:
            raise StopIteration


def gen_homedir_path() -> Path:
    return MODULE.runtime_home.joinpath("gnupg")


def setup_temporary_homedir(dir: Path, create: bool = False) -> None:
    if create:
        for parent in reversed(dir.parents):
            parent.mkdir(0o700, exist_ok=True)
        dir.mkdir(0o700, exist_ok=True)

    original = getenv("GNUPGHOME", Path.home().joinpath(".gnupg"))
    if isinstance(original, str):
        original = Path(original)

    for filename in ["gpg.conf", "gpg-agent.conf", "scdaemon.conf"]:
        path = dir.joinpath(f"{filename}.new")
        path.symlink_to(original.joinpath(filename))
        shutil.move(path, path.with_name(filename))


def build_gpg_args(
    args: Optional[Iterable[str]] = None,
    homedir: Optional[Path] = None,
    /,
    bin: str = "gpg",
) -> Deque[str]:
    call = deque([] if args is None else deque(args))

    if homedir is not None:
        call.extendleft(reversed(["--homedir", str(homedir)]))

    call.appendleft(bin)
    return call


def interact_gpg_transfer(key_fingerprint: str, homedir: Optional[Path] = None) -> None:
    with gpg.Context(home_dir=None if homedir is None else bytes(homedir)) as ctx:
        key = ctx.get_key(key_fingerprint)
        interaction = GpgTransferInteraction(key.subkeys)

        ctx.interact(key, interaction.interact_callback)


def create_key(full: bool = True, expert: bool = False) -> str:
    homedir = gen_homedir_path()
    setup_temporary_homedir(homedir, True)

    args = ["--full-generate-key" if full else "--generate-key", "--with-colons"]
    if expert:
        args.append("--expert")

    result = subprocess.run(build_gpg_args(args, homedir), stdout=subprocess.PIPE)
    key = result.stdout.partition(b"\n")[0].split(b":")[4].decode()

    return key


def export_key(key_fingerprint: str) -> None:
    dir = MODULE.runtime_home.joinpath(key_fingerprint)
    for parent in reversed(dir.parents):
        parent.mkdir(0o700, exist_ok=True)
    dir.mkdir(0o700, exist_ok=True)

    subprocess.run(
        build_gpg_args(
            ["--armor", "--output", str(dir.joinpath("public.key")), "--export", key_fingerprint],
            gen_homedir_path(),
        )
    )
    subprocess.run(
        build_gpg_args(
            ["--armor", "--output", str(dir.joinpath("secret.key")), "--export-secret-keys", key_fingerprint],
            gen_homedir_path(),
        )
    )
    subprocess.run(
        build_gpg_args(
            ["--armor", "--output", str(dir.joinpath("secret_sub.key")), "--export-secret-subkeys", key_fingerprint],
            gen_homedir_path(),
        )
    )

    echo(f"Key exported at {str(dir)}")


def transfer_key(key_fingerprint: str) -> None:
    homedir = gen_homedir_path()
    for file in homedir.glob("reader_"):
        file.unlink(missing_ok=True)

    subprocess.run(build_gpg_args(["--kill", "gpg-agent"], bin="gpgconf"))
    try:
        interact_gpg_transfer(key_fingerprint, homedir)
    except KeyNotFound:
        secho(f"Key '{key_fingerprint}' not found.", err=True, fg="red")
        exit(1)
    subprocess.run(build_gpg_args(["--kill", "gpg-agent"], homedir, bin="gpgconf"))


def purge_keys() -> None:
    shutil.rmtree(gen_homedir_path())
