"""Configuración por variables de entorno (prefijo OPENFOOT_).

Ningún secreto tiene valor por defecto ni se incluye en el repositorio.
"""

from functools import lru_cache

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="OPENFOOT_", env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./openfoot.db"

    # Fuente principal: football-data.org (requiere registro gratuito).
    football_data_token: SecretStr | None = None
    football_data_base_url: str = "https://api.football-data.org/v4"
    # Plan gratuito documentado por terceros: 10 solicitudes/minuto. Se deja margen.
    football_data_requests_per_minute: int = Field(default=8, ge=1, le=120)
    # Códigos de competición a sincronizar desde football-data.org.
    football_data_competitions: str = "PL,PD,BL1,SA,FL1,CL,DED,PPL,ELC,BSA,WC,EC"

    # Fuente secundaria: OpenLigaDB (sin clave). Ligas separadas por comas.
    openligadb_enabled: bool = True
    openligadb_base_url: str = "https://api.openligadb.de"
    openligadb_leagues: str = "bl1,bl2"

    # Sincronización periódica dentro del proceso del servidor.
    scheduler_enabled: bool = False
    sync_interval_minutes: int = Field(default=15, ge=2)
    sync_days_back: int = Field(default=3, ge=0, le=10)
    sync_days_ahead: int = Field(default=7, ge=0, le=10)

    # Una verificación de derechos deja de considerarse válida pasado este plazo.
    verification_ttl_days: int = Field(default=30, ge=1, le=365)

    # Los escudos son marcas registradas: por defecto no se sirven sus URL.
    serve_crest_urls: bool = False

    # Límite de solicitudes por cliente a la API pública.
    rate_limit_per_minute: int = Field(default=120, ge=1)
    # Activar solo detrás de un proxy inverso de confianza.
    trust_forwarded_for: bool = False

    # Verificador de enlaces.
    link_check_timeout_seconds: float = Field(default=10.0, gt=0, le=60)
    link_check_max_redirects: int = Field(default=5, ge=0, le=10)
    link_check_user_agent: str = "OpenFootLinkChecker/0.1 (+https://github.com/gxxrazn21/tv)"

    def competition_codes(self) -> list[str]:
        return [c.strip().upper() for c in self.football_data_competitions.split(",") if c.strip()]

    def openligadb_league_list(self) -> list[str]:
        return [c.strip().lower() for c in self.openligadb_leagues.split(",") if c.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
