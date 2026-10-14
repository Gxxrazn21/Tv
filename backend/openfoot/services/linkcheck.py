"""Comprobación técnica de enlaces de proveedores, con protección frente a SSRF.

Garantías:
- Solo https, puerto 443 y nombres de dominio (no se aceptan IP literales).
- Cada host se resuelve y TODAS sus direcciones deben ser públicas (is_global). Se rechazan
  redes privadas, loopback, link-local (incluido 169.254.169.254, metadatos de nube),
  CGNAT, multicast y reservadas, también en IPv6 y en IPv4 mapeada sobre IPv6.
- La conexión se hace a la IP ya validada (evita DNS rebinding) manteniendo SNI y Host,
  de modo que el certificado TLS se valida contra el nombre de dominio.
- Las redirecciones se siguen manualmente, se revalidan en cada salto y no pueden salir de
  los dominios registrados del proveedor.
- No se usan proxies del entorno, cookies ni credenciales, y no se descarga el cuerpo.

Un resultado "ok" solo significa que el servidor respondió 2xx desde aquí: no prueba que la
transmisión sea legal ni que esté disponible para un usuario concreto.
"""

import ipaddress
import socket
from collections.abc import Callable
from dataclasses import dataclass, field
from urllib.parse import urljoin, urlsplit, urlunsplit

import httpx

from openfoot.services.urls import InvalidURL, host_matches_domains, normalize_url

IPAddress = ipaddress.IPv4Address | ipaddress.IPv6Address
Resolver = Callable[[str], list[str]]

REDIRECT_CODES = {301, 302, 303, 307, 308}


class BlockedTarget(Exception):
    pass


@dataclass
class CheckResult:
    url: str
    outcome: str  # ok|restricted|broken|error|blocked|offsite_redirect
    status_code: int | None = None
    final_url: str | None = None
    redirect_chain: list[str] = field(default_factory=list)
    detail: str | None = None


def system_resolver(host: str) -> list[str]:
    infos = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    return sorted({info[4][0] for info in infos})


def ensure_public(addresses: list[str]) -> list[IPAddress]:
    if not addresses:
        raise BlockedTarget("El host no resuelve a ninguna dirección")
    result: list[IPAddress] = []
    for raw in addresses:
        ip = ipaddress.ip_address(raw.split("%", 1)[0])
        candidate = ip
        if isinstance(ip, ipaddress.IPv6Address) and ip.ipv4_mapped is not None:
            candidate = ip.ipv4_mapped
        if not candidate.is_global or candidate.is_multicast or candidate.is_reserved:
            raise BlockedTarget(f"Dirección no pública: {ip}")
        result.append(ip)
    return result


def _is_ip_literal(host: str) -> bool:
    try:
        ipaddress.ip_address(host.strip("[]"))
        return True
    except ValueError:
        return False


class LinkChecker:
    def __init__(
        self,
        *,
        timeout: float = 10.0,
        max_redirects: int = 5,
        user_agent: str = "OpenFootLinkChecker",
        resolver: Resolver = system_resolver,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.max_redirects = max_redirects
        self.resolver = resolver
        self.user_agent = user_agent
        self._client = httpx.Client(
            timeout=timeout,
            follow_redirects=False,
            trust_env=False,
            verify=True,
            transport=transport,
        )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "LinkChecker":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def _request(self, url: str) -> httpx.Response:
        parts = urlsplit(url)
        host = parts.hostname or ""
        if _is_ip_literal(host):
            raise BlockedTarget("No se permiten direcciones IP literales")
        ips = ensure_public(self.resolver(host))
        ip = ips[0]
        ip_host = f"[{ip}]" if isinstance(ip, ipaddress.IPv6Address) else str(ip)
        pinned = urlunsplit(("https", ip_host, parts.path or "/", parts.query, ""))
        request = self._client.build_request(
            "GET",
            pinned,
            headers={"Host": host, "User-Agent": self.user_agent, "Accept": "text/html,*/*"},
            extensions={"sni_hostname": host},
        )
        response = self._client.send(request, stream=True)
        response.close()  # no se descarga el cuerpo
        return response

    def check(self, url: str, allowed_domains: list[str]) -> CheckResult:
        try:
            current = normalize_url(url)
        except InvalidURL as exc:
            return CheckResult(url=url, outcome="blocked", detail=str(exc))
        if not host_matches_domains(urlsplit(current).hostname or "", allowed_domains):
            return CheckResult(
                url=url, outcome="blocked", detail="El dominio no está registrado para el proveedor"
            )
        chain: list[str] = []
        for _ in range(self.max_redirects + 1):
            try:
                response = self._request(current)
            except BlockedTarget as exc:
                return CheckResult(
                    url, "blocked", final_url=current, redirect_chain=chain, detail=str(exc)
                )
            except (httpx.HTTPError, OSError) as exc:
                return CheckResult(
                    url, "error", final_url=current, redirect_chain=chain, detail=type(exc).__name__
                )
            code = response.status_code
            if code in REDIRECT_CODES and "location" in response.headers:
                chain.append(current)
                try:
                    nxt = normalize_url(urljoin(current, response.headers["location"]))
                except InvalidURL as exc:
                    return CheckResult(
                        url, "blocked", code, current, chain, f"Redirección no válida: {exc}"
                    )
                if not host_matches_domains(urlsplit(nxt).hostname or "", allowed_domains):
                    return CheckResult(
                        url,
                        "offsite_redirect",
                        code,
                        nxt,
                        chain,
                        "Redirección fuera de los dominios del proveedor",
                    )
                current = nxt
                continue
            return CheckResult(url, _classify(code), code, current, chain)
        return CheckResult(url, "error", None, current, chain, "Demasiadas redirecciones")


def _classify(code: int) -> str:
    if 200 <= code < 300:
        return "ok"
    if code in (401, 403, 451, 429):
        # Puede ser un bloqueo geográfico, antibot o de suscripción: no se concluye nada.
        return "restricted"
    if code in (404, 410) or 400 <= code < 500:
        return "broken"
    return "error"
