#!/usr/bin/env python3

import click

from yubigen.cli.pgp import pgp
from yubigen.cli.setup import setup
from yubigen.cli.ssh import ssh


@click.group(help="Credential management helper for YubiKeys")
@click.version_option()
def main():
    pass


main.add_command(pgp)
main.add_command(setup)
main.add_command(ssh)

if __name__ == "__main__":
    main()
