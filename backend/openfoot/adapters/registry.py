"""Registro de fuentes en orden de prioridad.

Si dos fuentes cubren la misma competición, solo se usa la primera que esté configurada,
para no duplicar partidos.
"""

from openfoot.adapters.base import DataSource
from openfoot.adapters.football_data import FootballDataSource
from openfoot.adapters.openligadb import OpenLigaDBSource
from openfoot.config import Settings


def build_sources(settings: Settings) -> list[DataSource]:
    token = (
        settings.football_data_token.get_secret_value() if settings.football_data_token else None
    )
    return [
        FootballDataSource(
            token=token,
            competitions=settings.competition_codes(),
            base_url=settings.football_data_base_url,
            requests_per_minute=settings.football_data_requests_per_minute,
        ),
        OpenLigaDBSource(
            leagues=settings.openligadb_league_list(),
            base_url=settings.openligadb_base_url,
            enabled=settings.openligadb_enabled,
        ),
    ]
