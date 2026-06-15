#!/usr/bin/env python3
# =============================================================================
# buildserver.py
# Petit serveur HTTP local (stdlib uniquement, aucune dependance) qui pilote
# la toolchain android-build-tools depuis une app Android.
#
# Tourne DANS le proot Ubuntu (ou Termux si la chaine y est). Ecoute sur
# 127.0.0.1:8765 par defaut. L'app Android tape sur ce port via localhost.
#
# Endpoints :
#   GET  /status                 -> etat de la chaine (chain ready ? sdk ? versions)
#   POST /build  {url,branch,...} -> demarre un build, renvoie {job_id}
#   GET  /logs/<job_id>?from=N    -> lignes de log a partir de l'index N (poll)
#   GET  /jobs                    -> historique des builds
#   GET  /job/<job_id>            -> etat d'un job (running/success/failed + apk)
#   GET  /apk/<job_id>            -> telecharge l'APK produit
#   POST /setup                   -> (re)lance setup-aapt2-qemu.sh
#
# Securite : bind sur 127.0.0.1 uniquement (pas exposé au reseau). Un token
# simple peut etre exige via l'entete X-Build-Token (voir TOKEN ci-dessous).
# =============================================================================

import json, os, subprocess, threading, time, uuid, shlex, html
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HOME = os.path.expanduser("~")
TOOLS = os.path.join(HOME, "android-build-tools")
BUILDER = os.path.join(TOOLS, "android-builder.sh")
SETUP = os.path.join(TOOLS, "setup-aapt2-qemu.sh")
SHIM = os.path.join(HOME, "aapt2-shim")
PORT = int(os.environ.get("BUILD_SERVER_PORT", "8765"))
# token optionnel : si defini (env BUILD_SERVER_TOKEN), l'app doit l'envoyer.
TOKEN = os.environ.get("BUILD_SERVER_TOKEN", "")

# --- localisation des messages serveur (EN par defaut, FR si demande) --------
# La langue provient de l'en-tete X-Forge-Lang envoye par l'app APKforge, sinon
# de la variable d'env ABT_LANG, sinon anglais.
def _norm_lang(value):
    v = (value or "").strip().lower()
    return "fr" if v.startswith("fr") else "en"

SERVER_MSG = {
    "launch_error": {"en": "[server] launch error: {e}", "fr": "[serveur] erreur lancement: {e}"},
    "finished":     {"en": "[server] finished: {status}", "fr": "[serveur] termine: {status}"},
}

def srv(key, lang, **kw):
    table = SERVER_MSG.get(key, {})
    txt = table.get(_norm_lang(lang), table.get("en", key))
    return txt.format(**kw)

def _script_env(lang):
    """Environnement passe aux scripts shell, avec ABT_LANG propage."""
    env = dict(os.environ)
    env["ABT_LANG"] = _norm_lang(lang or os.environ.get("ABT_LANG", "en"))
    return env

# --- etat en memoire des jobs ------------------------------------------------
JOBS = {}            # job_id -> dict(status, url, lines[], apk, started, ended)
JOBS_LOCK = threading.Lock()


def new_job(url, branch, subdir, task):
    jid = uuid.uuid4().hex[:12]
    with JOBS_LOCK:
        JOBS[jid] = {
            "id": jid, "url": url, "branch": branch, "subdir": subdir,
            "task": task, "status": "running", "lines": [], "apk": None,
            "started": time.time(), "ended": None,
        }
    return jid


def run_build(jid):
    job = JOBS[jid]
    cmd = ["bash", BUILDER, job["url"]]
    if job["branch"]:
        cmd += ["--branch", job["branch"]]
    if job["subdir"]:
        cmd += ["--subdir", job["subdir"]]
    if job["task"]:
        cmd += ["--task", job["task"]]

    def log(line):
        with JOBS_LOCK:
            job["lines"].append(line.rstrip("\n"))

    log(f"$ {' '.join(shlex.quote(c) for c in cmd)}")
    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1, env=_script_env(job.get("lang")),
        )
        for line in proc.stdout:
            log(line)
        proc.wait()
        rc = proc.returncode
    except Exception as e:
        log(srv("launch_error", job.get("lang"), e=e))
        rc = 1

    # cherche l'APK produit
    apk = None
    repo_dir = os.path.join(HOME, "android-builds", os.path.basename(
        job["url"].rstrip("/")).replace(".git", ""))
    for root, _dirs, files in os.walk(repo_dir):
        if "outputs" in root:
            for f in files:
                if f.endswith(".apk"):
                    apk = os.path.join(root, f)
                    break
        if apk:
            break

    with JOBS_LOCK:
        job["status"] = "success" if rc == 0 else "failed"
        job["apk"] = apk
        job["ended"] = time.time()
    log(srv("finished", job.get("lang"), status=job["status"]) + (f" apk={apk}" if apk else ""))


def chain_status():
    sdk = os.path.join(HOME, "android-sdk")
    return {
        "chain_ready": os.path.exists(SHIM) and os.access(SHIM, os.X_OK),
        "builder_present": os.path.exists(BUILDER),
        "sdk_present": os.path.isdir(sdk),
        "shim": SHIM if os.path.exists(SHIM) else None,
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "AndroidBuildServer/1.0"

    # --- helpers -------------------------------------------------------------
    def _auth_ok(self):
        if not TOKEN:
            return True
        return self.headers.get("X-Build-Token", "") == TOKEN

    def _ui_lang(self):
        # Langue de l'UI APKforge, envoyee par l'app via X-Forge-Lang (ex: "fr").
        return _norm_lang(self.headers.get("X-Forge-Lang", ""))

    def _send(self, code, obj, ctype="application/json"):
        body = obj if isinstance(obj, (bytes, bytearray)) else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        if n == 0:
            return {}
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return {}

    def log_message(self, *a):
        pass  # silence

    # --- routes --------------------------------------------------------------
    def do_GET(self):
        if not self._auth_ok():
            return self._send(401, {"error": "unauthorized"})
        u = urlparse(self.path)
        parts = [p for p in u.path.split("/") if p]
        q = parse_qs(u.query)

        if u.path == "/status":
            return self._send(200, chain_status())

        if u.path == "/jobs":
            with JOBS_LOCK:
                out = [{k: j[k] for k in ("id", "url", "status", "started", "ended")}
                       for j in JOBS.values()]
            return self._send(200, {"jobs": out})

        if len(parts) == 2 and parts[0] == "job":
            j = JOBS.get(parts[1])
            if not j:
                return self._send(404, {"error": "no such job"})
            with JOBS_LOCK:
                view = {k: j[k] for k in ("id", "url", "status", "apk", "started", "ended")}
                view["n_lines"] = len(j["lines"])
            return self._send(200, view)

        if len(parts) == 2 and parts[0] == "logs":
            j = JOBS.get(parts[1])
            if not j:
                return self._send(404, {"error": "no such job"})
            frm = int((q.get("from", ["0"])[0]) or 0)
            with JOBS_LOCK:
                lines = j["lines"][frm:]
                total = len(j["lines"])
                status = j["status"]
            return self._send(200, {"from": frm, "next": total,
                                     "status": status, "lines": lines})

        if len(parts) == 2 and parts[0] == "apk":
            j = JOBS.get(parts[1])
            if not j or not j.get("apk") or not os.path.exists(j["apk"]):
                return self._send(404, {"error": "apk not available"})
            with open(j["apk"], "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.android.package-archive")
            self.send_header("Content-Disposition",
                             f'attachment; filename="{os.path.basename(j["apk"])}"')
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        return self._send(404, {"error": "not found"})

    def do_POST(self):
        if not self._auth_ok():
            return self._send(401, {"error": "unauthorized"})
        u = urlparse(self.path)

        if u.path == "/build":
            body = self._read_json()
            url = (body.get("url") or "").strip()
            if not url:
                return self._send(400, {"error": "url required"})
            jid = new_job(url, body.get("branch", ""), body.get("subdir", ""),
                          body.get("task", "assembleDebug"))
            JOBS[jid]["lang"] = self._ui_lang()
            threading.Thread(target=run_build, args=(jid,), daemon=True).start()
            return self._send(200, {"job_id": jid})

        if u.path == "/setup":
            jid = uuid.uuid4().hex[:12]
            with JOBS_LOCK:
                JOBS[jid] = {"id": jid, "url": "(setup)", "status": "running",
                             "lines": [], "apk": None, "started": time.time(),
                             "ended": None, "branch": "", "subdir": "", "task": "",
                             "lang": self._ui_lang()}

            def run_setup():
                job = JOBS[jid]
                try:
                    proc = subprocess.Popen(["bash", SETUP], stdout=subprocess.PIPE,
                                            stderr=subprocess.STDOUT, text=True, bufsize=1,
                                            env=_script_env(job.get("lang")))
                    for line in proc.stdout:
                        with JOBS_LOCK:
                            job["lines"].append(line.rstrip("\n"))
                    proc.wait()
                    rc = proc.returncode
                except Exception as e:
                    with JOBS_LOCK:
                        job["lines"].append(srv("launch_error", job.get("lang"), e=e))
                    rc = 1
                with JOBS_LOCK:
                    job["status"] = "success" if rc == 0 else "failed"
                    job["ended"] = time.time()

            threading.Thread(target=run_setup, daemon=True).start()
            return self._send(200, {"job_id": jid})

        return self._send(404, {"error": "not found"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type,X-Build-Token")
        self.end_headers()


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[build-server] ecoute sur http://127.0.0.1:{PORT}")
    print(f"[build-server] chaine: {chain_status()}")
    if TOKEN:
        print("[build-server] token requis (X-Build-Token)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n[build-server] arret.")


if __name__ == "__main__":
    main()
