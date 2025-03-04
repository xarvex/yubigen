import click
from click.termui import confirm, secho
from click.utils import echo

from yubigen.pgp import create_key, export_key, gen_homedir_path, purge_keys, transfer_key


@click.group(help="OpenPGP key management")
def pgp():
    pass


@pgp.command(help="Create OpenPGP key to be transferred YubiKeys")
@click.option("--short", is_flag=True)
@click.option("--expert", is_flag=True)
def create(short: bool, expert: bool):
    secho(
        f"""NOTICE: It is recommended to generate keys on an ephemeral system not connected to the internet, such as a live USB or ISO.
As an additional measure, a separate GNUPG home will be used in your user's runtime directory at {gen_homedir_path()}.""",
        fg="yellow",
    )
    secho("This means the original secret will (or at least should) be LOST after shutdown.", fg="red")
    _ = confirm("\nContinue?", abort=True)

    key = create_key(not short, expert)

    echo("\nCreated key: ", nl=False)
    secho(key, fg="green")

    if confirm("\nExport key now?"):
        echo("Starting key export process...")

        export_key(key)

    if confirm("\nTransfer key now?"):
        echo("Starting key transfer process...")

        transfer_key(key)

        if confirm("\nPurge created GNUPG home now?"):
            _ = confirm(
                f"""Are you sure you want to purge?
This will delete the generated GPG home at {gen_homedir_path()}.""",
                abort=True,
            )

            echo("Purging key information...")

            purge_keys()

    secho("\nComplete!", fg="magenta")


@pgp.command(help="Export OpenPGP key")
@click.argument("key", type=str)
def export(key: str):
    echo("Starting key export process...")

    export_key(key)

    if confirm("\nPurge created GNUPG home now?"):
        _ = confirm(
            f"""Are you sure you want to purge?
This will delete the generated GPG home at {gen_homedir_path()}.""",
            abort=True,
        )

        echo("Purging key information...")

        purge_keys()

    secho("\nComplete!", fg="magenta")


@pgp.command(help="Transfer OpenPGP key to YubiKeys")
@click.argument("key", type=str)
def transfer(key: str):
    echo("Starting key transfer process...")

    transfer_key(key)

    if confirm("\nPurge created GNUPG home now?"):
        _ = confirm(
            f"""Are you sure you want to purge?
This will delete the generated GPG home at {gen_homedir_path()}.""",
            abort=True,
        )

        echo("Purging key information...")

        purge_keys()

    secho("\nComplete!", fg="magenta")


@pgp.command(help="Purge all generated key information")
def purge():
    _ = confirm(
        f"""Are you sure you want to purge?
This will delete the generated GPG home at {gen_homedir_path()}.""",
        abort=True,
    )

    echo("Purging key information...")

    purge_keys()

    secho("\nComplete!", fg="magenta")
