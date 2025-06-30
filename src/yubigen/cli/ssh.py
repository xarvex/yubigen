from pathlib import Path
from typing import cast
import click
from click.termui import prompt, secho
from click.utils import echo

from yubigen import config
from yubigen.ssh import MODULE, create_key, download_keys, register_device, unregister_device, write_config


@click.group(help="OpenSSH key management")
def ssh():
    pass


@ssh.command(help="Create OpenSSH keys for YubiKeys")
@click.option("--application", type=str, help="Application URL or name")
def create(application: str | None):
    cfg = config.read()

    if application is None:
        application = cast(str, prompt("Application URL or name", type=str))

    echo("Starting key creation process...")

    for device, info in MODULE.iter_devices(True):
        create_key(device, info, application)
        write_config(cast(int, info.serial), cfg.ssh.applications, cfg.ssh.explicit_applications)

    secho("\nComplete!", fg="magenta")


@ssh.command(help="Download OpenSSH resident keys from YubiKeys")
def download():
    cfg = config.read()

    echo("Starting key download process...")

    device_list = MODULE.iter_devices(True)
    for device, info in device_list:
        download_keys(device, info)
        write_config(cast(int, info.serial), cfg.ssh.applications, cfg.ssh.explicit_applications)

    secho("\nComplete!", fg="magenta")


@ssh.command(help="Register device for OpenSSH host configurations")
@click.argument("device_path", type=click.Path(exists=True, dir_okay=False, readable=False, resolve_path=True, path_type=Path))
@click.argument("device_name", type=str)
def register(device_path: Path, device_name: str):
    echo("Registering device...")

    for device, info in MODULE.iter_devices(True, True):
        if device.fingerprint == str(device_path):
            assert info.serial

            register_device(device_name, info.serial)

            cfg = config.read()
            write_config(info.serial, cfg.ssh.applications, cfg.ssh.explicit_applications)

    secho("\nComplete!", fg="magenta")


@ssh.command(help="Unregister device from OpenSSH host configurations")
@click.argument("device_name", type=str)
def unregister(device_name: str):
    echo("Unregistering device...")

    unregister_device(device_name)

    secho("\nComplete!", fg="magenta")
