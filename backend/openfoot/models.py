"""Modelo de datos principal (PostgreSQL en producción, SQLite en desarrollo y pruebas).

Los favoritos y preferencias NO se guardan aquí: viven en el dispositivo (SQLite local).
"""

from datetime import date, datetime

from sqlalchemy import (
    JSON,
    Boolean,
    Date,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from openfoot.db import Base, UTCDateTime


class ExternalRef(Base):
    """Identificador de una entidad en una fuente externa. Evita duplicar equipos o partidos
    cuando varias fuentes describen la misma entidad."""

    __tablename__ = "external_refs"
    __table_args__ = (UniqueConstraint("source", "entity_type", "external_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(40))
    entity_type: Mapped[str] = mapped_column(String(20))  # competition|team|match|player
    external_id: Mapped[str] = mapped_column(String(64))
    entity_id: Mapped[int] = mapped_column(Integer, index=True)


class Competition(Base):
    __tablename__ = "competitions"

    id: Mapped[int] = mapped_column(primary_key=True)
    code: Mapped[str] = mapped_column(String(20), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    region: Mapped[str] = mapped_column(String(30))  # europe|south_america|international
    area_name: Mapped[str] = mapped_column(String(80))
    area_code: Mapped[str | None] = mapped_column(String(8))
    kind: Mapped[str] = mapped_column(String(20), default="league")  # league|cup|tournament
    gender: Mapped[str] = mapped_column(String(10), default="men")
    # available: hay fuente integrada | unavailable: sin fuente gratuita verificada
    data_status: Mapped[str] = mapped_column(String(20), default="unavailable")
    data_source: Mapped[str | None] = mapped_column(String(40))
    data_note: Mapped[str | None] = mapped_column(Text)
    featured: Mapped[bool] = mapped_column(Boolean, default=False)
    emblem_url: Mapped[str | None] = mapped_column(String(500))

    seasons: Mapped[list["Season"]] = relationship(back_populates="competition")


class Season(Base):
    __tablename__ = "seasons"
    __table_args__ = (UniqueConstraint("competition_id", "start_date"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    competition_id: Mapped[int] = mapped_column(ForeignKey("competitions.id", ondelete="CASCADE"))
    start_date: Mapped[date | None] = mapped_column(Date)
    end_date: Mapped[date | None] = mapped_column(Date)
    current_matchday: Mapped[int | None] = mapped_column(Integer)

    competition: Mapped[Competition] = relationship(back_populates="seasons")


class Team(Base):
    __tablename__ = "teams"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    short_name: Mapped[str | None] = mapped_column(String(80))
    tla: Mapped[str | None] = mapped_column(String(5))
    country: Mapped[str | None] = mapped_column(String(80))
    crest_url: Mapped[str | None] = mapped_column(String(500))


class Player(Base):
    __tablename__ = "players"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120), index=True)
    nationality: Mapped[str | None] = mapped_column(String(80))
    position: Mapped[str | None] = mapped_column(String(40))
    team_id: Mapped[int | None] = mapped_column(ForeignKey("teams.id", ondelete="SET NULL"))

    team: Mapped[Team | None] = relationship()


class Match(Base):
    __tablename__ = "matches"

    id: Mapped[int] = mapped_column(primary_key=True)
    competition_id: Mapped[int] = mapped_column(
        ForeignKey("competitions.id", ondelete="CASCADE"), index=True
    )
    season_id: Mapped[int | None] = mapped_column(ForeignKey("seasons.id", ondelete="SET NULL"))
    utc_date: Mapped[datetime] = mapped_column(UTCDateTime(), index=True)
    # Fecha anterior cuando la fuente cambia el horario (aplazamientos, reprogramaciones).
    previous_utc_date: Mapped[datetime | None] = mapped_column(UTCDateTime())
    # SCHEDULED|TIMED|IN_PLAY|PAUSED|FINISHED|POSTPONED|SUSPENDED|CANCELLED|AWARDED
    status: Mapped[str] = mapped_column(String(20), index=True)
    matchday: Mapped[int | None] = mapped_column(Integer)
    stage: Mapped[str | None] = mapped_column(String(60))
    group_name: Mapped[str | None] = mapped_column(String(60))
    venue: Mapped[str | None] = mapped_column(String(160))
    home_team_id: Mapped[int] = mapped_column(ForeignKey("teams.id"))
    away_team_id: Mapped[int] = mapped_column(ForeignKey("teams.id"))
    home_score: Mapped[int | None] = mapped_column(Integer)
    away_score: Mapped[int | None] = mapped_column(Integer)
    source: Mapped[str] = mapped_column(String(40))
    source_updated_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    fetched_at: Mapped[datetime] = mapped_column(UTCDateTime())

    competition: Mapped[Competition] = relationship()
    home_team: Mapped[Team] = relationship(foreign_keys=[home_team_id])
    away_team: Mapped[Team] = relationship(foreign_keys=[away_team_id])
    events: Mapped[list["MatchEvent"]] = relationship(
        back_populates="match", cascade="all, delete-orphan", order_by="MatchEvent.minute"
    )


class MatchEvent(Base):
    __tablename__ = "match_events"

    id: Mapped[int] = mapped_column(primary_key=True)
    match_id: Mapped[int] = mapped_column(ForeignKey("matches.id", ondelete="CASCADE"), index=True)
    minute: Mapped[int | None] = mapped_column(Integer)
    kind: Mapped[str] = mapped_column(String(20))  # goal|own_goal|penalty_goal
    team_side: Mapped[str | None] = mapped_column(String(4))  # home|away
    player_name: Mapped[str | None] = mapped_column(String(120))
    score_home: Mapped[int | None] = mapped_column(Integer)
    score_away: Mapped[int | None] = mapped_column(Integer)

    match: Mapped[Match] = relationship(back_populates="events")


class Broadcaster(Base):
    """Canal o plataforma audiovisual."""

    __tablename__ = "broadcasters"

    id: Mapped[int] = mapped_column(primary_key=True)
    slug: Mapped[str] = mapped_column(String(60), unique=True)
    name: Mapped[str] = mapped_column(String(120))
    website_url: Mapped[str] = mapped_column(String(500))
    # Dominios que el responsable del catálogo ha confirmado como propios del proveedor.
    official_domains: Mapped[list[str]] = mapped_column(JSON, default=list)
    countries: Mapped[list[str]] = mapped_column(JSON, default=list)
    notes: Mapped[str | None] = mapped_column(Text)


class BroadcastRight(Base):
    """Un proveedor emite una competición en un país durante un periodo.

    Solo se muestra al público si status == "verified", la verificación no ha caducado,
    el periodo cubre la fecha del partido y el último chequeo del enlace no lo marca como roto.
    """

    __tablename__ = "broadcast_rights"
    __table_args__ = (
        UniqueConstraint("broadcaster_id", "competition_id", "country_code", "season_label"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    broadcaster_id: Mapped[int] = mapped_column(ForeignKey("broadcasters.id", ondelete="CASCADE"))
    competition_id: Mapped[int] = mapped_column(ForeignKey("competitions.id", ondelete="CASCADE"))
    country_code: Mapped[str] = mapped_column(String(2), index=True)  # ISO 3166-1 alfa-2
    season_label: Mapped[str] = mapped_column(String(20))
    valid_from: Mapped[date | None] = mapped_column(Date)
    valid_to: Mapped[date | None] = mapped_column(Date)
    access_type: Mapped[str] = mapped_column(String(20))  # free|subscription|ppv|unknown
    price_note: Mapped[str | None] = mapped_column(Text)
    territorial_notes: Mapped[str | None] = mapped_column(Text)
    coverage_note: Mapped[str | None] = mapped_column(Text)
    watch_url: Mapped[str] = mapped_column(String(500))
    embed_allowed: Mapped[bool] = mapped_column(Boolean, default=False)
    # organizer_directory|api|rights_holder|provider|other
    source_type: Mapped[str] = mapped_column(String(30))
    source_url: Mapped[str] = mapped_column(String(500))
    status: Mapped[str] = mapped_column(String(20), default="pending_review")
    verified_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    verified_by: Mapped[str | None] = mapped_column(String(80))
    review_note: Mapped[str | None] = mapped_column(Text)

    broadcaster: Mapped[Broadcaster] = relationship()
    competition: Mapped[Competition] = relationship()


class OfficialDirectory(Base):
    """Página del organizador que lista sus emisoras oficiales por territorio."""

    __tablename__ = "official_directories"

    id: Mapped[int] = mapped_column(primary_key=True)
    competition_id: Mapped[int] = mapped_column(
        ForeignKey("competitions.id", ondelete="CASCADE"), unique=True
    )
    organizer: Mapped[str] = mapped_column(String(80))
    url: Mapped[str] = mapped_column(String(500))
    official_domains: Mapped[list[str]] = mapped_column(JSON, default=list)
    status: Mapped[str] = mapped_column(String(20), default="pending_review")
    verified_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    verified_by: Mapped[str | None] = mapped_column(String(80))
    review_note: Mapped[str | None] = mapped_column(Text)

    competition: Mapped[Competition] = relationship()


class LinkCheck(Base):
    """Resultado técnico de comprobar una URL. No demuestra legalidad ni disponibilidad."""

    __tablename__ = "link_checks"

    id: Mapped[int] = mapped_column(primary_key=True)
    target_type: Mapped[str] = mapped_column(String(20))  # right|directory
    target_id: Mapped[int] = mapped_column(Integer, index=True)
    url: Mapped[str] = mapped_column(String(500))
    checked_at: Mapped[datetime] = mapped_column(UTCDateTime())
    # ok|restricted|broken|error|blocked|offsite_redirect
    outcome: Mapped[str] = mapped_column(String(20))
    status_code: Mapped[int | None] = mapped_column(Integer)
    final_url: Mapped[str | None] = mapped_column(String(500))
    redirect_chain: Mapped[list[str]] = mapped_column(JSON, default=list)
    detail: Mapped[str | None] = mapped_column(Text)


class SyncRun(Base):
    __tablename__ = "sync_runs"

    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(40))
    started_at: Mapped[datetime] = mapped_column(UTCDateTime())
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    ok: Mapped[bool] = mapped_column(Boolean, default=False)
    matches_upserted: Mapped[int] = mapped_column(Integer, default=0)
    detail: Mapped[str | None] = mapped_column(Text)
