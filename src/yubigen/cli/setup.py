from typing import Type, cast

import click
from click.termui import secho
from yubikit.core import Connection
from yubikit.core.fido import FidoConnection
from yubikit.core.smartcard import SmartCardConnection
from yubikit.openpgp import OpenPgpSession

from yubigen.core import iter_devices
from yubigen.setup import change_fido_pin, change_openpgp_admin_pin, change_openpgp_pin


@click.group(help="YubiKey setup helpers")
def setup():
    pass


@setup.command(help="Setup FIDO PIN")
def fido():
    for device, _ in iter_devices(FidoConnection):
        with cast(FidoConnection, device.open_connection(cast(Type[Connection], FidoConnection))) as conn:
            change_fido_pin(conn)

    secho("\nComplete!", fg="magenta")


@setup.command(help="Setup OpenPGP PINs")
def openpgp():
    for device, _ in iter_devices(SmartCardConnection):
        with device.open_connection(SmartCardConnection) as conn:
            session = OpenPgpSession(conn)

            change_openpgp_pin(session)
            change_openpgp_admin_pin(session)

    secho("\nComplete!", fg="magenta")
