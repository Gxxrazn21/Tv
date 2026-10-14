"""Contrato común para las fuentes de datos deportivos.

Cada adaptador traduce la respuesta de su API a estas estructuras normalizadas. Para añadir una
fuente nueva basta con implementar DataSource y registrarla en adapters.registry.
"""

import threading
import time
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Protocol


class SourceError(Exception):
    """Error al consultar una fuente (red, autenticación, formato o límite de uso)."""


class SourceNotConfigured(SourceError):
    pass


@dataclass
class NTeam:
    external_id: str
    name: str
    short_name: str | None = None
    tla: str | None = None
    crest_url: str | None = None
    country: str | None = None


@dataclass
class NCompetition:
    external_id: str
    code: str
    name: str
    area_name: str | None = None
    area_code: str | None = None
    kind: str | None = None
    emblem_url: str | None = None
    season_start: date | None = None
    season_end: date | None = None
    current_matchday: int | None = None


@dataclass
class NEvent:
    minute: int | None
    kind: str  # goal|own_goal|penalty_goal
    team_side: str | None
    player_name: str | None
    score_home: int | None = None
    score_away: int | None = None


@dataclass
class NMatch:
    external_id: str
    competition_code: str
    utc_date: datetime
    status: str
    home: NTeam
    away: NTeam
    matchday: int | None = None
    stage: str | None = None
    group_name: str | None = None
    venue: str | None = None
    home_score: int | None = None
    away_score: int | None = None
    source_updated_at: datetime | None = None
    season_start: date | None = None
    events: list[NEvent] = field(default_factory=list)
    # True si la fuente informa de goles: permite reemplazar los eventos guardados.
    has_events: bool = False


@dataclass
class NPlayer:
    external_id: str
    name: str
    nationality: str | None
    position: str | None
    team: NTeam | None


class DataSource(Protocol):
    name: str
    attribution: str

    def is_configured(self) -> bool: ...

    def competition_codes(self) -> list[str]: ...

    def fetch_competitions(self) -> list[NCompetition]: ...

    def fetch_matches(self, date_from: date, date_to: date) -> list[NMatch]: ...

    def fetch_scorers(self, competition_code: str) -> list[NPlayer]: ...


class RateLimiter:
    """Ventana deslizante sencilla: como máximo `limit` llamadas cada `period` segundos.

    Se usa para respetar los límites publicados de cada API (nunca para eludirlos).
    """

    def __init__(self, limit: int, period: float = 60.0, clock=time.monotonic, sleep=time.sleep):
        self.limit = limit
        self.period = period
        self._clock = clock
        self._sleep = sleep
        self._calls: list[float] = []
        self._lock = threading.Lock()

    def acquire(self) -> None:
        with self._lock:
            while True:
                now = self._clock()
                self._calls = [t for t in self._calls if now - t < self.period]
                if len(self._calls) < self.limit:
                    self._calls.append(now)
                    return
                self._sleep(self.period - (now - self._calls[0]) + 0.01)
