#!/usr/bin/env bash
set -euo pipefail

# ===== Trap de errores (para que no quede "mudo") =====
trap 'echo -e "\e[31m[ERROR]\e[0m Falló en la línea $LINENO. Probá: bash -x ~/bootstrap_redops.sh" >&2' ERR

# ===== Opciones =====
BASEDIR="$HOME/RedOps"
export DEBIAN_FRONTEND=noninteractive

# ===== Banner ASCII =====
print_banner(){ cat <<'__BANNER__'
 ________  _______   ________  ________  ________  ________
|\   __  \|\  ___ \ |\   ___ \|\   __  \|\   __  \|\   ____\
\ \  \|\  \ \   __/|\ \  \_|\ \ \  \|\  \ \  \|\  \ \  \___|_
 \ \   _  _\ \  \_|/_\ \  \ \\ \ \  \\\  \ \   ____\ \_____  \
  \ \  \\  \\ \  \_|\ \ \  \_\\ \ \  \\\  \ \  \___|\|____|\  \
   \ \__\\ _\\ \_______\ \_______\ \_______\ \__\     ____\_\  \
    \|__|\|__|\|_______|\|_______|\|_______|\|__|    |\_________\
                                                     \|_________|
__BANNER__
}
print_banner

# ===== Colores y helpers =====
GREEN="\e[32m"; YELLOW="\e[33m"; NC="\e[0m"
log(){ echo -e "${GREEN}[+]${NC} $*"; }
warn(){ echo -e "${YELLOW}[!]${NC} $*"; }

# ===== Preflight =====
log "Probando sudo (puede pedir tu contraseña)…"
sudo -v

# ===== Sistema y paquetes =====
log "Actualizando sistema…"
sudo apt update
sudo apt -y full-upgrade

log "Instalando utilidades base…"
sudo apt -y install git curl wget jq unzip zip whois dnsutils rlwrap \
  build-essential python3 python3-venv python3-pip

log "Instalando herramientas de red y enumeración…"
sudo apt -y install nmap netcat-traditional gobuster ffuf seclists smbclient ldap-utils arp-scan metasploit-framework

# ===== Estructura de trabajo =====
log "Creando estructura en $BASEDIR …"
mkdir -p "$BASEDIR"/{recon,exploits,scripts,notes,loot,wordlists}

# Enlace a Seclists si existe
if [ -d /usr/share/seclists ] && [ ! -e "$BASEDIR/wordlists/seclists" ]; then
  ln -s /usr/share/seclists "$BASEDIR/wordlists/seclists" || true
fi

# ===== Python venv =====
log "Creando entorno Python del curso…"
if [ ! -d "$HOME/rt-venv" ]; then
  python3 -m venv "$HOME/rt-venv"
fi
# shellcheck disable=SC1090
source "$HOME/rt-venv/bin/activate"
python -m pip install --upgrade pip wheel
pip install requests beautifulsoup4 lxml tqdm
deactivate

# ===== healthcheck.sh =====
log "Escribiendo script healthcheck…"
cat > "$BASEDIR/scripts/healthcheck.sh" <<'__HCS__'
#!/usr/bin/env bash
set -euo pipefail
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; NC="\e[0m"
fail=0
ok(){ echo -e "${GREEN}[OK]${NC} $*"; }
ko(){ echo -e "${RED}[FALLO]${NC} $*"; fail=$((fail+1)); }
info(){ echo -e "${YELLOW}[*]${NC} $*"; }

info "Chequeando binarios requeridos…"
for b in nmap ffuf curl python3 arp-scan; do
  if command -v "$b" >/dev/null 2>&1; then ok "Presente: $b ($(command -v $b))"; else ko "No encontrado: $b"; fi
done

info "Versiones:"
command -v nmap     >/dev/null 2>&1 && nmap --version | head -n1 || true
command -v ffuf     >/dev/null 2>&1 && (ffuf -version || ffuf -h | head -n1) || true
command -v arp-scan >/dev/null 2>&1 && arp-scan --version | head -n1 || true
python3 --version || true

info "Red:"
if ping -c1 -W1 1.1.1.1 >/dev/null 2>&1; then ok "Conectividad IP OK (1.1.1.1)"; else ko "Sin conectividad IP"; fi
if getent hosts example.com >/dev/null 2>&1 || dig +short example.com >/dev/null 2>&1; then ok "Resolución DNS OK"; else ko "Problema de DNS (example.com no resuelve)"; fi

info "Python venv y librerías…"
if [ -d "$HOME/rt-venv" ]; then
  # shellcheck disable=SC1090
  source "$HOME/rt-venv/bin/activate"
  pyout=$(python - <<'PY'
mods=["requests","bs4","lxml","tqdm"]
missing=[]
for m in mods:
  try:
    __import__(m)
  except Exception:
    missing.append(m)
print("OK" if not missing else "MISSING:"+",".join(missing))
PY
) || true
  if [[ "$pyout" == "OK" ]]; then ok "Venv OK y libs presentes"; else ko "Faltan libs Python: $pyout"; fi
  deactivate || true
else
  ko "No existe venv en ~/rt-venv"
fi

if [ "$fail" -eq 0 ]; then ok "Healthcheck completado sin errores."; exit 0; else ko "Healthcheck detectó $fail problema(s)."; exit 1; fi
__HCS__
chmod +x "$BASEDIR/scripts/healthcheck.sh"

# ===== Ejecutar healthcheck (solo validación) =====
log "Ejecutando healthcheck…"
set +e
"$BASEDIR/scripts/healthcheck.sh"
hc=$?
set -e

if [ "$hc" -ne 0 ]; then
  warn "Healthcheck reportó problemas. Revisá la salida arriba."
else
  log "Setup finalizado."
fi
