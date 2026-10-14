"""Resolución de "Dónde ver" para un partido y un país."""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from openfoot.models import BroadcastRight, LinkCheck, Match, OfficialDirectory

NO_VERIFIED_MESSAGE = "No se encontró una transmisión oficial verificada para esta región"
DISQUALIFYING_CHECKS = {"broken", "offsite_redirect", "blocked"}


@dataclass
class WatchResult:
    rights: list[tuple[BroadcastRight, LinkCheck | None]]
    directory: OfficialDirectory | None
    directory_check: LinkCheck | None
    message: str | None


def latest_check(session: Session, target_type: str, target_id: int) -> LinkCheck | None:
    return session.scalar(
        select(LinkCheck)
        .where(LinkCheck.target_type == target_type, LinkCheck.target_id == target_id)
        .order_by(LinkCheck.checked_at.desc(), LinkCheck.id.desc())
        .limit(1)
    )


def is_verification_current(verified_at: datetime | None, ttl_days: int, now: datetime) -> bool:
    return verified_at is not None and now - verified_at <= timedelta(days=ttl_days)


def resolve_watch(
    session: Session, match: Match, country: str, ttl_days: int, now: datetime | None = None
) -> WatchResult:
    now = now or datetime.now(UTC)
    match_day = match.utc_date.date()
    candidates = session.scalars(
        select(BroadcastRight)
        .options(joinedload(BroadcastRight.broadcaster))
        .where(
            BroadcastRight.competition_id == match.competition_id,
            BroadcastRight.country_code == country.upper(),
            BroadcastRight.status == "verified",
        )
    ).all()
    rights = []
    for r in candidates:
        if not is_verification_current(r.verified_at, ttl_days, now):
            continue
        if r.valid_from and match_day < r.valid_from:
            continue
        if r.valid_to and match_day > r.valid_to:
            continue
        check = latest_check(session, "right", r.id)
        if check and check.outcome in DISQUALIFYING_CHECKS:
            continue
        rights.append((r, check))
    order = {"free": 0, "subscription": 1, "ppv": 2, "unknown": 3}
    rights.sort(key=lambda rc: (order.get(rc[0].access_type, 9), rc[0].broadcaster.name))

    directory = session.scalar(
        select(OfficialDirectory).where(
            OfficialDirectory.competition_id == match.competition_id,
            OfficialDirectory.status == "verified",
        )
    )
    dir_check = None
    if directory is not None:
        dir_check = latest_check(session, "directory", directory.id)
        if not is_verification_current(directory.verified_at, ttl_days, now) or (
            dir_check and dir_check.outcome in DISQUALIFYING_CHECKS
        ):
            directory, dir_check = None, None
    return WatchResult(
        rights=rights,
        directory=directory,
        directory_check=dir_check,
        message=None if rights else NO_VERIFIED_MESSAGE,
    )
