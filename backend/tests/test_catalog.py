import pytest
from sqlalchemy import func, select

from openfoot.models import BroadcastRight, Competition
from openfoot.services.catalog import CatalogError, load_catalog
from tests.conftest import CATALOG


def test_repository_catalog_loads_and_is_idempotent(session):
    first = load_catalog(session, CATALOG)
    second = load_catalog(session, CATALOG)
    assert first == second
    assert session.scalar(select(func.count(Competition.id))) == first["competitions"]
    verified = session.scalars(select(BroadcastRight).where(BroadcastRight.status == "verified"))
    for r in verified:
        assert r.source_url.startswith("https://") and r.verified_by and r.verified_at


def write(tmp_path, text):
    p = tmp_path / "c.yaml"
    p.write_text(text, encoding="utf-8")
    return p


BASE = """
competitions:
  - {code: PL, name: Premier League, region: europe, area_name: Inglaterra}
broadcasters:
  - {slug: b, name: B, website_url: "https://www.b.example/", official_domains: [b.example]}
"""


def test_verified_requires_evidence(session, tmp_path):
    p = write(
        tmp_path,
        BASE
        + """
rights:
  - {broadcaster: b, competition: PL, country: GB, season: "1", access_type: free,
     source_type: other, source_url: "https://x.example/", status: verified}
""",
    )
    with pytest.raises(CatalogError, match="verified_at"):
        load_catalog(session, p)


def test_watch_url_must_belong_to_provider(session, tmp_path):
    p = write(
        tmp_path,
        BASE
        + """
rights:
  - {broadcaster: b, competition: PL, country: GB, season: "1", access_type: free,
     source_type: other, source_url: "https://x.example/", watch_url: "https://b.example.evil.com/"}
""",
    )
    with pytest.raises(CatalogError, match="dominios"):
        load_catalog(session, p)


def test_invalid_country_and_access(session, tmp_path):
    bad_country = (
        BASE
        + """
rights:
  - {broadcaster: b, competition: PL, country: GBR, season: "1", access_type: free,
     source_type: other, source_url: "https://x.example/"}
"""
    )
    with pytest.raises(CatalogError):
        load_catalog(session, write(tmp_path, bad_country))
    session.rollback()
    with pytest.raises(CatalogError):
        load_catalog(
            session,
            write(
                tmp_path,
                bad_country.replace("GBR", "GB").replace(
                    "access_type: free", "access_type: gratis"
                ),
            ),
        )
