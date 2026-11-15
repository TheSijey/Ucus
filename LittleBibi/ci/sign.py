#!/usr/bin/env python3
"""LittleBibi için elle imzalama hazırlığı.

Apple'ın API anahtarı iCloud kapsayıcılarını göremediği için (401) Xcode'un otomatik
bulut imzası iCloud yetkili uygulamada çalışmıyor. Bu betik aynı API anahtarıyla:
  1. bir dağıtım sertifikası bulur ya da (yılda bir kez) oluşturur,
  2. uygulama ve widget için App Store profillerini yeniler,
  3. anahtar, sertifika ve profilleri imzalama adımının kullanacağı yerlere yazar.

Sertifikanın özel anahtarı hiçbir yerde saklanmaz; her çalıştırmada mevcut API
anahtarından aynı şekilde türetilir; sertifika yılda bir kez yenilenir. Yalnızca Python standart kitaplığı ve openssl kullanır.
"""
import base64, hashlib, json, os, subprocess, sys, time, urllib.error, urllib.parse, urllib.request

KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
P8 = sys.argv[1]
OUT = sys.argv[2]
TARGETS = [("com.cengiz.bebek", "LittleBibi CI App"), ("com.cengiz.bebek.widget", "LittleBibi CI Widget")]
API = "https://api.appstoreconnect.apple.com"


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


# ---- Belirlenimli RSA anahtarı ----
class Stream:
    def __init__(self, seed):
        self.seed, self.n = seed, 0

    def take(self, nbytes):
        out = b""
        while len(out) < nbytes:
            out += hashlib.sha256(self.seed + self.n.to_bytes(8, "big")).digest()
            self.n += 1
        return out[:nbytes]


SMALL = [p for p in range(3, 2000, 2) if all(p % q for q in range(3, int(p ** 0.5) + 1, 2))]


def is_prime(n, stream):
    for p in SMALL:
        if n % p == 0:
            return n == p
    d, r = n - 1, 0
    while d % 2 == 0:
        d //= 2
        r += 1
    for _ in range(40):
        a = 2 + int.from_bytes(stream.take(64), "big") % (n - 4)
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def gen_prime(stream, bits=1024):
    while True:
        c = int.from_bytes(stream.take(bits // 8), "big")
        c |= (3 << (bits - 2)) | 1
        if (c - 1) % 65537 and is_prime(c, stream):
            return c


def der_int(v):
    b = v.to_bytes((v.bit_length() + 8) // 8 or 1, "big")
    return b"\x02" + der_len(len(b)) + b


def der_len(n):
    if n < 128:
        return bytes([n])
    b = n.to_bytes((n.bit_length() + 7) // 8, "big")
    return bytes([0x80 | len(b)]) + b


def rsa_pem(seed):
    s = Stream(seed)
    p, q = gen_prime(s), gen_prime(s)
    if p < q:
        p, q = q, p
    n, e = p * q, 65537
    d = pow(e, -1, (p - 1) * (q - 1))
    body = b"".join(der_int(v) for v in (0, n, e, d, p, q, d % (p - 1), d % (q - 1), pow(q, -1, p)))
    der = b"\x30" + der_len(len(body)) + body
    b64 = base64.encodebytes(der).decode()
    return "-----BEGIN RSA PRIVATE KEY-----\n" + b64 + "-----END RSA PRIVATE KEY-----\n", n


# ---- App Store Connect API ----
def token():
    head = b64u(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    now = int(time.time())
    body = b64u(json.dumps({"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}).encode())
    msg = (head + "." + body).encode()
    sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", P8], input=msg, capture_output=True, check=True).stdout
    # DER (SEQUENCE{INTEGER r, INTEGER s}) -> r||s
    i = 2 if sig[1] < 128 else 2 + (sig[1] & 0x7F)
    rl = sig[i + 1]
    r = int.from_bytes(sig[i + 2:i + 2 + rl], "big")
    j = i + 2 + rl
    sl = sig[j + 1]
    s = int.from_bytes(sig[j + 2:j + 2 + sl], "big")
    return head + "." + body + "." + b64u(r.to_bytes(32, "big") + s.to_bytes(32, "big"))


TOKEN = None


def api(method, path, payload=None):
    global TOKEN
    TOKEN = TOKEN or token()
    req = urllib.request.Request(API + path, method=method, data=json.dumps(payload).encode() if payload else None)
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:1500]
        sys.exit(f"API hatası {method} {path.split('?')[0]}: {e.code}\n{detail}")


def q(params):
    return "?" + urllib.parse.urlencode(params)


def modulus_of_cert(der):
    out = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-modulus"], input=der, capture_output=True).stdout.decode()
    return int(out.strip().split("=", 1)[1], 16) if "=" in out else None


def main():
    os.makedirs(OUT, exist_ok=True)
    seed = hashlib.sha256(open(P8, "rb").read().strip() + b"|littlebibi-distribution-v1").digest()
    pem, n = rsa_pem(seed)
    key_path = os.path.join(OUT, "dist.key")
    with open(key_path, "w") as f:
        f.write(pem)
    os.chmod(key_path, 0o600)

    # 1) Sertifika
    cert = None
    listed = api("GET", "/v1/certificates" + q({"limit": 200})).get("data", [])
    mine = hashlib.sha256(str(n).encode()).hexdigest()[:8]
    print("Anahtar parmak izi:", mine, "| listelenen sertifika:", len(listed))
    for c in listed:
        a = c["attributes"]
        m = modulus_of_cert(base64.b64decode(a["certificateContent"]))
        print("  -", a.get("certificateType"), a.get("name"), a.get("expirationDate", "")[:10],
              hashlib.sha256(str(m).encode()).hexdigest()[:8])
    if os.environ.get("LB_DIAG"):
        for identifier, _ in TARGETS[:1]:
            b = [x for x in api("GET", "/v1/bundleIds" + q({"filter[identifier]": identifier})).get("data", []) if x["attributes"]["identifier"] == identifier][0]
            caps = api("GET", "/v1/bundleIds/" + b["id"] + "/bundleIdCapabilities")
            for cap in caps.get("data", []):
                print("  yetenek:", cap["attributes"].get("capabilityType"), json.dumps(cap["attributes"].get("settings"))[:600])
        sys.exit("Tanılama bitti, değişiklik yapılmadı.")
    for c in listed:
        if c["attributes"].get("certificateType") not in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
            continue
        der = base64.b64decode(c["attributes"]["certificateContent"])
        if modulus_of_cert(der) == n:
            exp = c["attributes"].get("expirationDate", "")
            if exp and exp[:10] > time.strftime("%Y-%m-%d", time.gmtime(time.time() + 14 * 86400)):
                cert = c
                print("Mevcut dağıtım sertifikası kullanılıyor, bitiş:", exp[:10])
                break
    if cert is None:
        csr = subprocess.run(["openssl", "req", "-new", "-key", key_path, "-subj", "/CN=LittleBibi CI/C=TR"],
                             capture_output=True, check=True).stdout.decode()
        cert = api("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr}}})["data"]
        print("Yeni dağıtım sertifikası oluşturuldu, bitiş:", cert["attributes"].get("expirationDate", "")[:10])
    with open(os.path.join(OUT, "dist.cer"), "wb") as f:
        f.write(base64.b64decode(cert["attributes"]["certificateContent"]))

    # 2) Profiller
    dirs = [os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles"),
            os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles")]
    for d in dirs:
        os.makedirs(d, exist_ok=True)
    for identifier, name in TARGETS:
        ids = [b for b in api("GET", "/v1/bundleIds" + q({"filter[identifier]": identifier, "limit": 200})).get("data", [])
               if b["attributes"]["identifier"] == identifier]
        if not ids:
            sys.exit(f"Paket kimliği bulunamadı: {identifier}")
        for old in api("GET", "/v1/profiles" + q({"filter[name]": name, "limit": 200})).get("data", []):
            if old["attributes"]["name"] == name:
                api("DELETE", "/v1/profiles/" + old["id"])
        prof = api("POST", "/v1/profiles", {"data": {"type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": ids[0]["id"]}},
                "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})["data"]
        content = base64.b64decode(prof["attributes"]["profileContent"])
        for d in dirs:
            with open(os.path.join(d, prof["attributes"]["uuid"] + ".mobileprovision"), "wb") as f:
                f.write(content)
        with open(os.path.join(OUT, identifier + ".mobileprovision"), "wb") as f:
            f.write(content)
        print("Profil hazır:", name)


main()
