import httpx
import pytest

from openfoot.services.linkcheck import BlockedTarget, LinkChecker, ensure_public

PUBLIC = "93.184.216.34"


@pytest.mark.parametrize(
    "addr",
    [
        "127.0.0.1",
        "10.1.2.3",
        "172.16.0.1",
        "192.168.1.1",
        "169.254.169.254",
        "100.64.0.1",
        "0.0.0.0",
        "224.0.0.1",
        "::1",
        "fd00::1",
        "fe80::1%eth0",
        "::ffff:127.0.0.1",
        "::ffff:169.254.169.254",
        "240.0.0.1",
    ],
)
def test_private_addresses_blocked(addr):
    with pytest.raises(BlockedTarget):
        ensure_public([addr])


def test_one_private_among_public_blocks():
    with pytest.raises(BlockedTarget):
        ensure_public([PUBLIC, "10.0.0.1"])


def make_checker(handler, resolver=None, **kw):
    return LinkChecker(
        resolver=resolver or (lambda h: [PUBLIC]), transport=httpx.MockTransport(handler), **kw
    )


def test_pins_resolved_ip_and_keeps_host_and_sni():
    seen = {}

    def handler(req: httpx.Request):
        seen["url"] = str(req.url)
        seen["host"] = req.headers["host"]
        seen["sni"] = req.extensions.get("sni_hostname")
        return httpx.Response(200)

    res = make_checker(handler).check("https://www.example.com/watch?utm_x=1", ["example.com"])
    assert res.outcome == "ok"
    assert seen["url"] == f"https://{PUBLIC}/watch"
    assert seen["host"] == "www.example.com"
    assert seen["sni"] == "www.example.com"


def test_rejects_domain_not_registered():
    res = make_checker(lambda r: httpx.Response(200)).check(
        "https://evil.example/", ["good.example"]
    )
    assert res.outcome == "blocked"


def test_rejects_ip_literal_and_http():
    checker = make_checker(lambda r: httpx.Response(200))
    assert checker.check("https://93.184.216.34/", ["93.184.216.34"]).outcome == "blocked"
    assert checker.check("http://example.com/", ["example.com"]).outcome == "blocked"


def test_dns_to_private_is_blocked():
    res = make_checker(lambda r: httpx.Response(200), resolver=lambda h: ["169.254.169.254"]).check(
        "https://example.com/", ["example.com"]
    )
    assert res.outcome == "blocked"


def test_redirect_within_domains_followed_and_recorded():
    def handler(req):
        if req.url.path == "/a":
            return httpx.Response(301, headers={"location": "https://watch.example.com/b"})
        return httpx.Response(200)

    res = make_checker(handler).check("https://example.com/a", ["example.com"])
    assert res.outcome == "ok"
    assert res.redirect_chain == ["https://example.com/a"]
    assert res.final_url == "https://watch.example.com/b"


def test_offsite_redirect_not_followed():
    calls = []

    def handler(req):
        calls.append(req)
        return httpx.Response(302, headers={"location": "https://pirate.example/stream"})

    res = make_checker(handler).check("https://example.com/", ["example.com"])
    assert res.outcome == "offsite_redirect"
    assert len(calls) == 1


def test_redirect_to_private_ip_blocked():
    def resolver(host):
        return ["10.0.0.5"] if host == "internal.example.com" else [PUBLIC]

    def handler(req):
        return httpx.Response(302, headers={"location": "https://internal.example.com/"})

    res = make_checker(handler, resolver=resolver).check("https://example.com/", ["example.com"])
    assert res.outcome == "blocked"


def test_redirect_downgrade_to_http_blocked():
    def handler(req):
        return httpx.Response(302, headers={"location": "http://example.com/"})

    assert make_checker(handler).check("https://example.com/", ["example.com"]).outcome == "blocked"


def test_redirect_loop_limited():
    def handler(req):
        return httpx.Response(302, headers={"location": "https://example.com/again"})

    res = make_checker(handler, max_redirects=3).check("https://example.com/", ["example.com"])
    assert res.outcome == "error"
    assert len(res.redirect_chain) == 4


@pytest.mark.parametrize(
    ("code", "outcome"),
    [
        (200, "ok"),
        (204, "ok"),
        (403, "restricted"),
        (451, "restricted"),
        (404, "broken"),
        (410, "broken"),
        (500, "error"),
        (503, "error"),
    ],
)
def test_classification(code, outcome):
    res = make_checker(lambda r: httpx.Response(code)).check(
        "https://example.com/", ["example.com"]
    )
    assert res.outcome == outcome
    assert res.status_code == code


def test_network_error_reported_without_details():
    def handler(req):
        raise httpx.ConnectError("boom")

    res = make_checker(handler).check("https://example.com/", ["example.com"])
    assert res.outcome == "error"
    assert res.detail == "ConnectError"
