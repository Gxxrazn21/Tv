from datetime import datetime

from pydantic import BaseModel

PHASES = {
    "IN_PLAY": "live",
    "PAUSED": "live",
    "SCHEDULED": "upcoming",
    "TIMED": "upcoming",
    "FINISHED": "finished",
    "AWARDED": "finished",
    "POSTPONED": "postponed",
    "SUSPENDED": "postponed",
    "CANCELLED": "cancelled",
}


def phase_of(status: str) -> str:
    return PHASES.get(status, "unknown")


class TeamOut(BaseModel):
    id: int
    name: str
    short_name: str | None
    tla: str | None
    crest_url: str | None


class CompetitionRef(BaseModel):
    code: str
    name: str
    region: str
    area_name: str
    area_code: str | None


class CompetitionOut(CompetitionRef):
    kind: str
    gender: str
    data_status: str
    data_source: str | None
    data_note: str | None
    featured: bool
    emblem_url: str | None
    has_official_directory: bool


class Score(BaseModel):
    home: int | None
    away: int | None


class MatchOut(BaseModel):
    id: int
    competition: CompetitionRef
    utc_date: datetime
    previous_utc_date: datetime | None
    status: str
    phase: str
    matchday: int | None
    stage: str | None
    group: str | None
    venue: str | None
    home: TeamOut
    away: TeamOut
    score: Score
    source: str
    source_updated_at: datetime | None
    fetched_at: datetime


class EventOut(BaseModel):
    minute: int | None
    kind: str
    team_side: str | None
    player_name: str | None
    score_home: int | None
    score_away: int | None


class MatchDetailOut(MatchOut):
    events: list[EventOut]


class LinkCheckOut(BaseModel):
    checked_at: datetime
    outcome: str
    status_code: int | None


class BroadcasterOut(BaseModel):
    slug: str
    name: str
    website_url: str


class WatchOptionOut(BaseModel):
    broadcaster: BroadcasterOut
    access_type: str
    price_note: str | None
    territorial_notes: str | None
    coverage_note: str | None
    watch_url: str
    embed_allowed: bool
    season: str
    source_type: str
    source_url: str
    verified_at: datetime
    verified_by: str
    last_check: LinkCheckOut | None


class DirectoryOut(BaseModel):
    organizer: str
    url: str
    verified_at: datetime
    last_check: LinkCheckOut | None


class WatchOut(BaseModel):
    match_id: int
    country: str
    options: list[WatchOptionOut]
    official_directory: DirectoryOut | None
    message: str | None
    disclaimer: str


class ProviderOut(BroadcasterOut):
    countries: list[str]
    official_domains: list[str]
    verified_rights: int


class SearchHitOut(BaseModel):
    kind: str
    id: str
    label: str
    detail: str | None
    score: float


class SearchOut(BaseModel):
    query: str
    hits: list[SearchHitOut]
    matches_on_date: list[MatchOut]


class SourceStatusOut(BaseModel):
    name: str
    configured: bool
    attribution: str
    competitions: list[str]
    last_sync_at: datetime | None
    last_sync_ok: bool | None
    last_sync_detail: str | None


class Page(BaseModel):
    total: int
    limit: int
    offset: int
