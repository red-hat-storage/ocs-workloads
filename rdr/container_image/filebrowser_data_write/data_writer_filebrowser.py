#!/usr/bin/env python3
import subprocess, os, tempfile, time, json, random, sys, signal
from datetime import datetime, timedelta
from faker import Faker

# ─────────────────────────────────────────────
# Global setup
# ─────────────────────────────────────────────
os.environ["PYTHONUNBUFFERED"] = "1"
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

fake = Faker()
CONFIG_PATH = os.getenv("CONFIG_PATH", "/config")
stop_requested = False  # ✅ global stop flag

# ─────────────────────────────────────────────
# Signal handling
# ─────────────────────────────────────────────
def handle_termination(signum, frame):
    global stop_requested
    print(f"[{datetime.utcnow().isoformat()}] 🛑 Received signal {signum} — stopping gracefully...", flush=True)
    stop_requested = True

signal.signal(signal.SIGTERM, handle_termination)
signal.signal(signal.SIGINT, handle_termination)

# ─────────────────────────────────────────────
# Utility functions
# ─────────────────────────────────────────────
def log(msg): print(f"[{datetime.utcnow().isoformat()}] {msg}", flush=True)

def debug(msg):
    if CONFIG.get("DEBUG", False):
        print(f"[DEBUG {datetime.utcnow().isoformat()}] {msg}", flush=True)

def run_curl(cmd):
    """Execute shell command and capture stdout."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout.strip(), result.returncode

# ─────────────────────────────────────────────
# Config loader
# ─────────────────────────────────────────────
def load_config():
    """Load config values from mounted ConfigMap."""
    cfg = {
        "FB_USERNAME": "admin",
        "FB_PASSWORD": "admin123",
        "UPLOAD_MINUTES": "5",
        "COOLDOWN_MINUTES": "5",
        "MIN_FILE_MB": "50",
        "MAX_FILE_MB": "200",
        "UPLOAD_DELAY_SEC": "15",
        "CLEAN_TMP": "true",
        "DEBUG": "false",
        "ITERATIONS": "0"
    }
    for k in cfg.keys():
        f = os.path.join(CONFIG_PATH, k)
        if os.path.exists(f):
            with open(f) as fh:
                cfg[k] = fh.read().strip()
    cfg["DEBUG"] = cfg["DEBUG"].lower() in ("true", "1", "yes")
    cfg["CLEAN_TMP"] = cfg["CLEAN_TMP"].lower() in ("true", "1", "yes")
    cfg["ITERATIONS"] = int(cfg["ITERATIONS"]) if str(cfg["ITERATIONS"]).isdigit() else 0
    return cfg

# ─────────────────────────────────────────────
# FileBrowser communication helpers
# ─────────────────────────────────────────────
service_host = os.getenv("FILEBROWSER_SERVICE_HOST")
service_port = os.getenv("FILEBROWSER_SERVICE_PORT", "80")
BASE_URL = f"http://{service_host}:{service_port}" if service_host else os.getenv("BASE_URL", "http://localhost:8080")

def get_api_token():
    """Authenticate to FileBrowser and return token."""
    cmd = (
        f"curl -s -H 'Content-Type: application/json' "
        f"{BASE_URL}/api/login "
        f"--data '{{\"username\":\"{CONFIG['FB_USERNAME']}\",\"password\":\"{CONFIG['FB_PASSWORD']}\",\"recaptcha\":\"\"}}'"
    )
    out, _ = run_curl(cmd)
    if not out:
        log("⚠️ No response from FileBrowser login — likely down.")
        return None
    if out.count('.') == 2 and len(out) > 100:
        log("✅ Detected raw JWT token (plain text mode).")
        return out
    try:
        return json.loads(out).get("jwt")
    except Exception:
        debug(f"Non-JSON login response: {out[:200]}")
        return None

def check_health():
    """Check FileBrowser health by hitting /api/."""
    cmd = f"curl -s -o /dev/null -w '%{{http_code}}' {BASE_URL}/api/"
    out, _ = run_curl(cmd)
    return out == "200"

def create_folder(folder_name, token):
    folder_name = folder_name.strip("/")
    auth = f"--header X-Auth:{token}" if token else ""
    cmd = (
        f"curl -s -o /dev/null -w '%{{http_code}}' "
        f"{BASE_URL}/api/resources/{folder_name}/?override=false "
        f"--data '{{}}' {auth}"
    )
    code, _ = run_curl(cmd)
    log(f"📁 Folder '{folder_name}' → HTTP {code}")
    return code

def upload_file(local_path, remote_folder, token):
    auth = f"-H 'X-Auth:{token}'" if token else ""
    cmd = (
        f"curl -s -o /dev/null -w '%{{http_code}}' "
        f"-X POST {auth} "
        f"-F 'files=@{local_path}' "
        f"{BASE_URL}/api/resources/{remote_folder}/{os.path.basename(local_path)}?override=false"
    )
    code, _ = run_curl(cmd)
    log(f"📤 Upload {os.path.basename(local_path)} → {remote_folder} [{code}]")
    return code

def create_large_file(file_path, min_mb, max_mb):
    """Generate random binary file of size MB."""
    size_mb = random.randint(min_mb, max_mb)
    log(f"💾 Writing {size_mb} MB → {file_path}")
    with open(file_path, "wb") as f:
        f.write(os.urandom(size_mb * 1024 * 1024))
    return size_mb

# ─────────────────────────────────────────────
# Upload cycle (main work unit)
# ─────────────────────────────────────────────
def upload_cycle(token, iteration, last_upload_time):
    global stop_requested
    CONFIG.update(load_config())

    upload_minutes = int(CONFIG["UPLOAD_MINUTES"])
    cooldown_minutes = int(CONFIG["COOLDOWN_MINUTES"])
    min_mb = int(CONFIG["MIN_FILE_MB"])
    max_mb = int(CONFIG["MAX_FILE_MB"])
    delay_sec = int(CONFIG["UPLOAD_DELAY_SEC"])

    root = f"data_{fake.word()}"
    sub = f"{root}/{fake.word()}_{fake.random_int(1,100)}"
    create_folder(root, token)
    create_folder(sub, token)

    end_time = datetime.utcnow() + timedelta(minutes=upload_minutes)
    outage_start = None

    while datetime.utcnow() < end_time and not stop_requested:
        if not check_health():
            if not outage_start:
                outage_start = datetime.utcnow()
                log(f"[RPO-RTO] ⚠️ FileBrowser UNREACHABLE — pausing uploads (detected at {outage_start.isoformat()})")
            time.sleep(15)
            continue
        elif outage_start:
            recovery_time = datetime.utcnow()
            rto = (recovery_time - outage_start).total_seconds()
            rpo = (recovery_time - last_upload_time).total_seconds() if last_upload_time else 0
            log(f"[RPO-RTO] ✅ FileBrowser RECOVERED at {recovery_time.isoformat()} | 🕓 RTO={rto:.1f}s | 💾 RPO={rpo:.1f}s")
            outage_start = None

        tmp_file = os.path.join(tempfile.gettempdir(), f"{fake.word()}.bin")
        size_mb = create_large_file(tmp_file, min_mb, max_mb)
        code = upload_file(tmp_file, sub, token)
        if code in ("401", "403"):
            log("🔐 Token expired — re-login.")
            token = get_api_token()
        elif code in ("200", "201"):
            last_upload_time = datetime.utcnow()
        else:
            log(f"⚠️ Upload failed (HTTP {code})")
        
        # 🧹 Clean up temp file if enabled
        if CONFIG.get("CLEAN_TMP", True):
            try:
                os.remove(tmp_file)
                debug(f"🧹 Deleted temp file {tmp_file}")
            except Exception as e:
                debug(f"⚠️ Could not delete temp file {tmp_file}: {e}")
        
        time.sleep(delay_sec)

    log(f"🕒 Cooling down {cooldown_minutes} min …")
    time.sleep(cooldown_minutes * 60)
    return token, last_upload_time

# ─────────────────────────────────────────────
# Main loop with config watcher
# ─────────────────────────────────────────────
if __name__ == "__main__":
    log(f"🌐 FileBrowser Client starting | Base URL: {BASE_URL}")
    CONFIG = load_config()
    token = get_api_token()
    iteration = 1
    last_upload_time = None
    total_iters = CONFIG.get("ITERATIONS", 0)
    last_config_snapshot = CONFIG.copy()
    last_auth_attempt = datetime.utcnow()
    retry_delay = 30

    while not stop_requested:
        CONFIG = load_config()
        total_iters = CONFIG.get("ITERATIONS", 0)

        # Detect ConfigMap changes
        if CONFIG != last_config_snapshot:
            changed_keys = [k for k in CONFIG if CONFIG[k] != last_config_snapshot.get(k)]
            log(f"🔁 Detected ConfigMap change — updated: {', '.join(changed_keys)}")
            last_config_snapshot = CONFIG.copy()

        # 🧩 Handle login retry if FileBrowser unreachable
        if not token or not check_health():
            log("[AUTH] ⚠️ FileBrowser unreachable, starting health retry loop...")
            while not stop_requested:
                if check_health():
                    log("[AUTH] ✅ FileBrowser reachable again — logging in...")
                    token = get_api_token()
                    if token:
                        log("[AUTH] 🔓 Login successful — resuming operations.")
                        retry_delay = 30
                        break
                else:
                    log("[AUTH] ⏳ Still unreachable, re-checking in 10 s...")
                time.sleep(10)
            if not token:
                log("💤 Still no token, retrying later...")
                time.sleep(retry_delay)
                retry_delay = min(retry_delay * 2, 300)
                continue

        # 💤 ITERATIONS = -1 → Pause mode
        if total_iters == -1:
            log("💤 Paused (ITERATIONS=-1). Watching for config changes...")
            time.sleep(30)
            continue

        # ♾️ ITERATIONS = 0 → Infinite mode
        if total_iters == 0:
            log("♾️ Infinite mode (ITERATIONS=0) — running continuous uploads.")
            while not stop_requested:
                token, last_upload_time = upload_cycle(token, iteration, last_upload_time)
                iteration += 1
            break

        # 🧪 Finite mode
        log(f"🧪 Starting {total_iters} iteration(s).")
        iteration = 1
        while iteration <= total_iters and not stop_requested:
            log(f"🚀 Starting iteration {iteration}/{total_iters}")
            token, last_upload_time = upload_cycle(token, iteration, last_upload_time)
            iteration += 1

        log(f"✅ Completed {total_iters} iteration(s). Returning to watcher mode.")
        time.sleep(30)

    log("🛑 Graceful shutdown requested. Exiting...")
