from click.termui import prompt
from fido2.ctap2.base import Ctap2
from fido2.ctap2.pin import ClientPin
from yubikit.core.fido import FidoConnection
from yubikit.core.smartcard import SmartCardConnection
from yubikit.openpgp import OpenPgpSession


def change_openpgp_admin_pin(connection_or_session: SmartCardConnection | OpenPgpSession):
    session = OpenPgpSession(connection_or_session) if isinstance(connection_or_session, SmartCardConnection) else connection_or_session

    session.change_admin(
        prompt("Enter Admin PIN", "12345678", hide_input=True),  # pyright: ignore[reportAny]
        prompt("New Admin PIN", hide_input=True, confirmation_prompt=True),  # pyright: ignore[reportAny]
    )


def change_openpgp_pin(connection_or_session: SmartCardConnection | OpenPgpSession):
    session = OpenPgpSession(connection_or_session) if isinstance(connection_or_session, SmartCardConnection) else connection_or_session

    session.change_pin(
        prompt("Enter PIN", "123456", hide_input=True),  # pyright: ignore[reportAny]
        prompt("New PIN", hide_input=True, confirmation_prompt=True),  # pyright: ignore[reportAny]
    )


def change_fido_pin(client_pin_or_ctap2_or_connection: FidoConnection | Ctap2 | ClientPin):
    client_pin_or_ctap2 = (
        Ctap2(client_pin_or_ctap2_or_connection)
        if isinstance(client_pin_or_ctap2_or_connection, FidoConnection)
        else client_pin_or_ctap2_or_connection
    )
    client_pin = ClientPin(client_pin_or_ctap2) if isinstance(client_pin_or_ctap2, Ctap2) else client_pin_or_ctap2

    client_pin.change_pin(
        prompt("Enter PIN", "123456", hide_input=True),  # pyright: ignore[reportAny]
        prompt("New PIN", hide_input=True, confirmation_prompt=True),  # pyright: ignore[reportAny]
    )
