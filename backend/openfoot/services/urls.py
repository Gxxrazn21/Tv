"""Normalización y validación estricta de URL de proveedores."""

from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

TRACKING_PARAMS = {"fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "ref_src"}
MAX_URL_LENGTH = 500


class InvalidURL(ValueError):
    pass


def _idna_host(host: str) -> str:
    try:
        return host.encode("idna").decode("ascii").lower()
    except UnicodeError as exc:
        raise InvalidURL(f"Nombre de host no válido: {host!r}") from exc


def normalize_url(raw: str, *, require_https: bool = True) -> str:
    """Devuelve una forma canónica de la URL o lanza InvalidURL.

    - Solo https (salvo require_https=False), sin credenciales embebidas ni puertos no estándar.
    - Host en minúsculas y codificado IDNA; se elimina el punto final.
    - Se eliminan el fragmento y los parámetros de seguimiento; el resto se ordena.
    """
    if not isinstance(raw, str):
        raise InvalidURL("La URL debe ser texto")
    raw = raw.strip()
    if not raw or len(raw) > MAX_URL_LENGTH:
        raise InvalidURL("URL vacía o demasiado larga")
    if any(ord(c) < 0x21 for c in raw):
        raise InvalidURL("La URL contiene espacios o caracteres de control")
    parts = urlsplit(raw)
    scheme = parts.scheme.lower()
    allowed = {"https"} if require_https else {"https", "http"}
    if scheme not in allowed:
        raise InvalidURL(f"Esquema no permitido: {scheme or '(ninguno)'}")
    if parts.username is not None or parts.password is not None:
        raise InvalidURL("No se permiten credenciales en la URL")
    if not parts.hostname:
        raise InvalidURL("La URL no tiene host")
    try:
        port = parts.port
    except ValueError as exc:
        raise InvalidURL("Puerto no válido") from exc
    default_port = 443 if scheme == "https" else 80
    if port not in (None, default_port):
        raise InvalidURL("No se permiten puertos no estándar")
    host = _idna_host(parts.hostname.rstrip("."))
    if "." not in host and ":" not in host:
        raise InvalidURL("Se requiere un nombre de dominio completo")
    if ":" in host:  # literal IPv6
        host = f"[{host}]"
    path = parts.path or "/"
    query = urlencode(
        sorted(
            (k, v)
            for k, v in parse_qsl(parts.query, keep_blank_values=True)
            if not k.lower().startswith("utm_") and k.lower() not in TRACKING_PARAMS
        )
    )
    return urlunsplit((scheme, host, path, query, ""))


def host_of(url: str) -> str:
    return (urlsplit(url).hostname or "").lower()


def host_matches_domains(host: str, domains: list[str]) -> bool:
    """True si host es exactamente uno de los dominios o un subdominio suyo.

    Coincidir con un dominio registrado NO convierte un enlace en oficial: la lista de dominios
    la mantiene manualmente el responsable del catálogo tras revisar la fuente.
    """
    host = host.lower().rstrip(".")
    for domain in domains:
        d = domain.lower().strip().rstrip(".")
        if d and (host == d or host.endswith("." + d)):
            return True
    return False
