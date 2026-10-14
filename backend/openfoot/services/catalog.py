"""Carga idempotente del catálogo (competiciones, proveedores, derechos y directorios).

El catálogo vive en ficheros YAML revisables en el repositorio: cada cambio pasa por revisión
manual (pull request). El cargador rechaza entradas incoherentes en lugar de corregirlas.
"""

from datetime import date, datetime
from pathlib import Path

import yaml
from sqlalchemy import select
from sqlalchemy.orm import Session

from openfoot.models import Broadcaster, BroadcastRight, Competition, OfficialDirectory
from openfoot.services.urls import host_matches_domains, host_of, normalize_url

ACCESS_TYPES = {"free", "subscription", "ppv", "unknown"}
SOURCE_TYPES = {"organizer_directory", "api", "rights_holder", "provider", "other"}
STATUSES = {"pending_review", "verified", "rejected"}
REGIONS = {"europe", "south_america", "international"}


class CatalogError(ValueError):
    pass


def _dt(value) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        dt = value
    else:
        dt = datetime.fromisoformat(str(value))
    if dt.tzinfo is None:
        raise CatalogError(f"verified_at debe incluir zona horaria: {value}")
    return dt


def _d(value) -> date | None:
    if value is None or isinstance(value, date):
        return value
    return date.fromisoformat(str(value))


def _check_verified(entry: dict, where: str) -> None:
    if entry.get("status", "pending_review") not in STATUSES:
        raise CatalogError(f"{where}: estado no válido")
    if entry.get("status") == "verified":
        for key in ("verified_at", "verified_by", "source_url"):
            if not entry.get(key):
                raise CatalogError(f"{where}: una entrada verificada necesita {key}")


def load_catalog(session: Session, path: Path) -> dict[str, int]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    counts = {"competitions": 0, "broadcasters": 0, "rights": 0, "directories": 0}

    for c in data.get("competitions", []):
        if c.get("region") not in REGIONS:
            raise CatalogError(f"Competición {c.get('code')}: región no válida")
        comp = session.scalar(select(Competition).where(Competition.code == c["code"]))
        if comp is None:
            comp = Competition(code=c["code"])
            session.add(comp)
        comp.name = c["name"]
        comp.region = c["region"]
        comp.area_name = c["area_name"]
        comp.area_code = c.get("area_code")
        comp.kind = c.get("kind", "league")
        comp.gender = c.get("gender", "men")
        comp.data_status = c.get("data_status", "unavailable")
        comp.data_source = c.get("data_source")
        comp.data_note = c.get("data_note")
        comp.featured = bool(c.get("featured", False))
        counts["competitions"] += 1
    session.flush()

    for b in data.get("broadcasters", []):
        domains = [d.lower() for d in b.get("official_domains", [])]
        if not domains:
            raise CatalogError(f"Proveedor {b['slug']}: faltan official_domains")
        website = normalize_url(b["website_url"])
        if not host_matches_domains(host_of(website), domains):
            raise CatalogError(f"Proveedor {b['slug']}: website_url fuera de sus dominios")
        row = session.scalar(select(Broadcaster).where(Broadcaster.slug == b["slug"]))
        if row is None:
            row = Broadcaster(slug=b["slug"])
            session.add(row)
        row.name = b["name"]
        row.website_url = website
        row.official_domains = domains
        row.countries = [c.upper() for c in b.get("countries", [])]
        row.notes = b.get("notes")
        counts["broadcasters"] += 1
    session.flush()

    for r in data.get("rights", []):
        where = f"Derecho {r.get('broadcaster')}/{r.get('competition')}/{r.get('country')}"
        b = session.scalar(select(Broadcaster).where(Broadcaster.slug == r["broadcaster"]))
        comp = session.scalar(select(Competition).where(Competition.code == r["competition"]))
        if b is None or comp is None:
            raise CatalogError(f"{where}: proveedor o competición inexistente")
        if r.get("access_type") not in ACCESS_TYPES:
            raise CatalogError(f"{where}: access_type no válido")
        if r.get("source_type") not in SOURCE_TYPES:
            raise CatalogError(f"{where}: source_type no válido")
        _check_verified(r, where)
        watch_url = normalize_url(r.get("watch_url") or b.website_url)
        if not host_matches_domains(host_of(watch_url), b.official_domains):
            raise CatalogError(f"{where}: watch_url fuera de los dominios del proveedor")
        source_url = normalize_url(r["source_url"])
        country = r["country"].upper()
        if len(country) != 2 or not country.isalpha():
            raise CatalogError(f"{where}: país debe ser ISO 3166-1 alfa-2")
        row = session.scalar(
            select(BroadcastRight).where(
                BroadcastRight.broadcaster_id == b.id,
                BroadcastRight.competition_id == comp.id,
                BroadcastRight.country_code == country,
                BroadcastRight.season_label == str(r["season"]),
            )
        )
        if row is None:
            row = BroadcastRight(
                broadcaster_id=b.id,
                competition_id=comp.id,
                country_code=country,
                season_label=str(r["season"]),
            )
            session.add(row)
        row.valid_from = _d(r.get("valid_from"))
        row.valid_to = _d(r.get("valid_to"))
        row.access_type = r["access_type"]
        row.price_note = r.get("price_note")
        row.territorial_notes = r.get("territorial_notes")
        row.coverage_note = r.get("coverage_note")
        row.watch_url = watch_url
        row.embed_allowed = bool(r.get("embed_allowed", False))
        row.source_type = r["source_type"]
        row.source_url = source_url
        row.status = r.get("status", "pending_review")
        row.verified_at = _dt(r.get("verified_at"))
        row.verified_by = r.get("verified_by")
        row.review_note = r.get("review_note")
        counts["rights"] += 1

    for d in data.get("directories", []):
        where = f"Directorio {d.get('competition')}"
        comp = session.scalar(select(Competition).where(Competition.code == d["competition"]))
        if comp is None:
            raise CatalogError(f"{where}: competición inexistente")
        _check_verified({**d, "source_url": d.get("url")}, where)
        domains = [x.lower() for x in d.get("official_domains", [])]
        url = normalize_url(d["url"])
        if not host_matches_domains(host_of(url), domains):
            raise CatalogError(f"{where}: url fuera de los dominios del organizador")
        row = session.scalar(
            select(OfficialDirectory).where(OfficialDirectory.competition_id == comp.id)
        )
        if row is None:
            row = OfficialDirectory(competition_id=comp.id)
            session.add(row)
        row.organizer = d["organizer"]
        row.url = url
        row.official_domains = domains
        row.status = d.get("status", "pending_review")
        row.verified_at = _dt(d.get("verified_at"))
        row.verified_by = d.get("verified_by")
        row.review_note = d.get("review_note")
        counts["directories"] += 1

    session.commit()
    return counts
