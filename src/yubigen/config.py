from tomllib import load
from typing import Iterable, Mapping

from pydantic import BaseModel, ConfigDict, Field

from yubigen.core import programdirs


class PgpConfig(BaseModel):
    model_config = ConfigDict(strict=True)


class SshConfig(BaseModel):
    model_config = ConfigDict(strict=True)

    explicit_applications: bool = Field(default=False)
    applications: Mapping[str, str | Iterable[str]] = Field(default_factory=lambda: {})


class Config(BaseModel):
    model_config = ConfigDict(strict=True)

    pgp: PgpConfig = Field(default_factory=lambda: PgpConfig.model_validate({}))
    ssh: SshConfig = Field(default_factory=lambda: SshConfig.model_validate({}))


def read():
    try:
        with open(programdirs.user_config_path.joinpath("config.toml"), "rb") as file:
            data = load(file)
    except FileNotFoundError:
        data = {}

    return Config.model_validate(data)
