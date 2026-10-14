import pytest

from openfoot.services.urls import InvalidURL, host_matches_domains, normalize_url


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("HTTPS://WWW.Example.COM", "https://www.example.com/"),
        ("https://example.com:443/a?b=2&a=1#frag", "https://example.com/a?a=1&b=2"),
        ("https://example.com/x?utm_source=x&fbclid=1&id=7", "https://example.com/x?id=7"),
        ("https://example.com./", "https://example.com/"),
        ("https://bücher.example/", "https://xn--bcher-kva.example/"),
    ],
)
def test_normalize(raw, expected):
    assert normalize_url(raw) == expected


@pytest.mark.parametrize(
    "raw",
    [
        "http://example.com/",
        "javascript:alert(1)",
        "ftp://example.com/",
        "https://user:pass@example.com/",
        "https://example.com:8443/",
        "https://localhost/",
        "https:///nohost",
        "https://exa mple.com/",
        "https://example.com/a\nb",
        "https://example.com/" + "a" * 600,
        "",
    ],
)
def test_reject(raw):
    with pytest.raises(InvalidURL):
        normalize_url(raw)


def test_domain_match():
    assert host_matches_domains("www.skysports.com", ["skysports.com"])
    assert host_matches_domains("skysports.com", ["skysports.com"])
    assert not host_matches_domains("skysports.com.evil.example", ["skysports.com"])
    assert not host_matches_domains("fakeskysports.com", ["skysports.com"])
