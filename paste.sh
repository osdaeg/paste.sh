#!/usr/bin/env bash
# paste — CLI para paste.sh autoalojado
# Config: ~/.config/paste/config

set -euo pipefail

# ── Colores ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  GRN='\033[0;32m'; DIM='\033[2;37m'; CYN='\033[0;36m'
  YLW='\033[0;33m'; RED='\033[0;31m'; BLD='\033[1m'; RST='\033[0m'
else
  GRN=''; DIM=''; CYN=''; YLW=''; RED=''; BLD=''; RST=''
fi

# ── Config ─────────────────────────────────────────────────────────────────────
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/paste"
CONFIG_FILE="$CONFIG_DIR/config"
DEFAULT_HOST="http://localhost:8090"

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
  HOST="${PASTE_HOST:-$DEFAULT_HOST}"
}

cmd_config() {
  mkdir -p "$CONFIG_DIR"
  local host
  echo -e "${DIM}Host actual: ${HOST}${RST}"
  printf "Nuevo host [Enter para mantener]: "
  read -r host
  if [[ -n "$host" ]]; then
    echo "PASTE_HOST=\"$host\"" > "$CONFIG_FILE"
    echo -e "${GRN}✓ Guardado en $CONFIG_FILE${RST}"
  else
    echo -e "${DIM}Sin cambios.${RST}"
  fi
}

# ── Helpers ────────────────────────────────────────────────────────────────────
die()  { echo -e "${RED}error: $*${RST}" >&2; exit 1; }
info() { echo -e "${DIM}$*${RST}"; }

api() {
  local method="$1"; shift
  local path="$1";   shift
  curl -sf -X "$method" \
    -H "Content-Type: application/json" \
    "${HOST}${path}" "$@"
}

# Copia texto al portapapeles (xclip, xsel o wl-copy)
to_clipboard() {
  local text="$1"
  if command -v xclip &>/dev/null; then
    echo -n "$text" | xclip -selection clipboard
  elif command -v xsel &>/dev/null; then
    echo -n "$text" | xsel --clipboard --input
  elif command -v wl-copy &>/dev/null; then
    echo -n "$text" | wl-copy
  else
    return 1
  fi
}

# Formatea timestamp a fecha legible
fmt_time() {
  date -d "@$1" "+%d/%m/%Y %H:%M" 2>/dev/null \
    || date -r "$1" "+%d/%m/%Y %H:%M" 2>/dev/null \
    || echo "$1"
}

# TTL restante legible
fmt_ttl() {
  local exp="$1"
  if [[ -z "$exp" || "$exp" == "null" ]]; then
    echo "nunca"
    return
  fi
  local now diff
  now=$(date +%s)
  diff=$(( exp - now ))
  if (( diff <= 0 )); then
    echo "expirado"
  elif (( diff < 3600 )); then
    echo "$((diff/60))m restantes"
  elif (( diff < 86400 )); then
    echo "$((diff/3600))h restantes"
  else
    echo "$((diff/86400))d restantes"
  fi
}

# Parser JSON mínimo sin jq
json_get() {
  local json="$1" key="$2"
  # Intenta con jq si está disponible
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r ".$key // empty"
    return
  fi
  # Fallback: regex bash
  local val
  val=$(echo "$json" | grep -oP "\"${key}\"\\s*:\\s*\\K(\"[^\"]*\"|[0-9]+|null|true|false)" | head -1)
  val="${val%\"}"
  val="${val#\"}"
  echo "$val"
}

# ── Comandos ───────────────────────────────────────────────────────────────────

cmd_crear() {
  local titulo="" lenguaje="plaintext" ttl=0 archivo="" contenido=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--titulo)    titulo="$2";    shift 2 ;;
      -l|--lenguaje)  lenguaje="$2";  shift 2 ;;
      -e|--expira)    ttl="$2";       shift 2 ;;  # en segundos, o: 1h 1d 1w
      -f|--archivo)   archivo="$2";   shift 2 ;;
      -c|--clipboard) _copy_url=1;    shift   ;;
      *) die "opción desconocida: $1" ;;
    esac
  done

  # Convertir TTL legible a segundos
  case "$ttl" in
    *h) ttl=$(( ${ttl%h} * 3600 ))   ;;
    *d) ttl=$(( ${ttl%d} * 86400 ))  ;;
    *w) ttl=$(( ${ttl%w} * 604800 )) ;;
  esac

  # Leer contenido
  if [[ -n "$archivo" ]]; then
    [[ -f "$archivo" ]] || die "archivo no encontrado: $archivo"
    contenido=$(cat "$archivo")
    # Auto-detectar lenguaje por extensión si no se especificó
    if [[ "$lenguaje" == "plaintext" ]]; then
      case "${archivo##*.}" in
        py)   lenguaje="python"     ;;
        js)   lenguaje="javascript" ;;
        ts)   lenguaje="typescript" ;;
        sh)   lenguaje="bash"       ;;
        json) lenguaje="json"       ;;
        yaml|yml) lenguaje="yaml"   ;;
        html) lenguaje="html"       ;;
        css)  lenguaje="css"        ;;
        sql)  lenguaje="sql"        ;;
        go)   lenguaje="go"         ;;
        rs)   lenguaje="rust"       ;;
        md)   lenguaje="markdown"   ;;
        toml) lenguaje="toml"       ;;
      esac
    fi
  elif [[ ! -t 0 ]]; then
    contenido=$(cat)
  else
    die "especificá un archivo (-f) o pasá contenido por stdin"
  fi

  [[ -z "$contenido" ]] && die "el contenido está vacío"

  # Construir JSON a mano (sin jq requerido)
  local ttl_field="null"
  (( ttl > 0 )) && ttl_field="$ttl"

  local titulo_field="null"
  [[ -n "$titulo" ]] && titulo_field="\"$(echo "$titulo" | sed 's/"/\\"/g')\""

  local payload
  payload="{\"title\":${titulo_field},\"content\":$(echo "$contenido" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),\"language\":\"${lenguaje}\",\"ttl_seconds\":${ttl_field}}"

  local resp
  resp=$(curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${HOST}/api/pastes") || die "no se pudo conectar a $HOST"

  local id url
  id=$(json_get "$resp" "id")
  url="${HOST}/p/${id}"

  echo -e "${GRN}${BLD}✓ Paste creado${RST}"
  echo -e "  ${DIM}id:${RST}  ${CYN}${id}${RST}"
  echo -e "  ${DIM}url:${RST} ${BLD}${url}${RST}"

  if [[ "${_copy_url:-0}" == "1" ]]; then
    if to_clipboard "$url"; then
      echo -e "  ${DIM}→ URL copiada al portapapeles${RST}"
    else
      echo -e "  ${YLW}⚠ no se encontró xclip/xsel/wl-copy${RST}"
    fi
  fi
}

cmd_listar() {
  local archivados=0
  [[ "${1:-}" == "--archivados" ]] && archivados=1

  local endpoint="/api/pastes"
  (( archivados )) && endpoint="/api/pastes?archived=true"

  local resp
  resp=$(api GET "$endpoint") || die "no se pudo conectar a $HOST"

  # Contar elementos
  local count
  if command -v jq &>/dev/null; then
    count=$(echo "$resp" | jq 'length')
  else
    count=$(echo "$resp" | grep -o '"id"' | wc -l)
  fi

  if [[ "$count" -eq 0 ]]; then
    (( archivados )) && info "no hay pastes archivados." || info "no hay pastes."
    return
  fi

  local label="activos"
  (( archivados )) && label="archivados"
  echo -e "${DIM}── pastes ${label} (${count}) ─────────────────────────────────${RST}"
  printf "${BLD}%-12s %-30s %-14s %-18s %-16s${RST}\n" "ID" "TÍTULO" "LENGUAJE" "CREADO" "EXPIRA"
  echo -e "${DIM}$(printf '%.0s─' {1..90})${RST}"

  if command -v jq &>/dev/null; then
    echo "$resp" | jq -r '.[] | [.id, (.title // "sin título"), .language, .created_at, (.expires_at // ""), .views] | @tsv' \
    | while IFS=$'\t' read -r id title lang created expires views; do
      local ttl_str fecha
      ttl_str=$(fmt_ttl "$expires")
      fecha=$(fmt_time "$created")
      printf "${CYN}%-12s${RST} %-30s ${DIM}%-14s${RST} %-18s " \
        "$id" "${title:0:29}" "$lang" "$fecha"
      if [[ "$ttl_str" == "expirado" ]]; then
        echo -e "${YLW}${ttl_str}${RST}"
      elif [[ "$ttl_str" == "nunca" ]]; then
        echo -e "${DIM}${ttl_str}${RST}"
      else
        echo -e "${GRN}${ttl_str}${RST}"
      fi
    done
  else
    info "(instalá jq para una lista más detallada)"
    echo "$resp" | grep -oP '"id"\s*:\s*"\K[^"]+' | while read -r id; do
      echo -e "  ${CYN}${id}${RST}  →  ${HOST}/p/${id}"
    done
  fi
}

cmd_ver() {
  local id="${1:-}" raw=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --raw|-r) raw=1; shift ;;
      *)        id="$1"; shift ;;
    esac
  done
  [[ -z "$id" ]] && die "uso: paste ver <id> [--raw]"

  local resp
  resp=$(api GET "/api/pastes/${id}") || die "paste no encontrado: $id"

  local title lang created expires views content
  if command -v jq &>/dev/null; then
    title=$(echo "$resp"   | jq -r '.title // "sin título"')
    lang=$(echo "$resp"    | jq -r '.language')
    created=$(echo "$resp" | jq -r '.created_at')
    expires=$(echo "$resp" | jq -r '.expires_at // ""')
    views=$(echo "$resp"   | jq -r '.views')
    content=$(echo "$resp" | jq -r '.content')
  else
    content=$(python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('content',''))
" <<< "$resp")
    lang=$(json_get "$resp" "language")
    title=$(json_get "$resp" "title")
    created=$(json_get "$resp" "created_at")
    expires=$(json_get "$resp" "expires_at")
    views=$(json_get "$resp" "views")
  fi

  # Cabecera con metadatos
  if [[ "$raw" -eq 0 ]]; then
    echo -e "${DIM}── ${CYN}${id}${DIM} ── ${title:-sin título} ── ${lang} ── $(fmt_time "$created") ── $(fmt_ttl "$expires") ── ${views} vistas ──${RST}"
    echo
  fi

  # Mostrar contenido: bat > highlight > cat
  if [[ "$raw" -eq 1 ]]; then
    echo "$content"
  elif command -v bat &>/dev/null; then
    local bat_lang="$lang"
    [[ "$bat_lang" == "plaintext" ]] && bat_lang="txt"

    # Paginar automáticamente si el contenido supera la altura del terminal
    local lines term_lines
    lines=$(echo "$content" | wc -l)
    # $LINES es la más confiable en terminales interactivas
    # stty como fallback, tput como último recurso
    if [[ -n "${LINES:-}" ]]; then
      term_lines=$LINES
    else
      term_lines=$(stty size 2>/dev/null | cut -d' ' -f1)
      if [[ -z "$term_lines" || "$term_lines" -lt 10 ]]; then
        term_lines=$(tput lines 2>/dev/null || echo 40)
      fi
      if [[ "$term_lines" -lt 10 ]]; then
        term_lines=40
      fi
    fi

    if (( lines + 4 > term_lines )); then
      echo "$content" | bat --language="$bat_lang" \
        --style="numbers,grid" \
        --color=always \
        --pager="less -RF" \
        --file-name="${title:-$id}.${bat_lang}" 2>/dev/null \
        || echo "$content"
    else
      echo "$content" | bat --language="$bat_lang" \
        --style="numbers,grid" \
        --color=always \
        --pager=never \
        --terminal-width="${COLUMNS:-$(tput cols 2>/dev/null || echo 120)}" \
        --file-name="${title:-$id}.${bat_lang}" 2>/dev/null \
        || echo "$content"
    fi
  elif command -v highlight &>/dev/null; then
    echo "$content" | highlight --syntax="$lang" --out-format=ansi 2>/dev/null \
      || echo "$content"
  else
    echo "$content"
    if [[ -t 1 ]]; then
      echo -e "\n${DIM}tip: instalá 'bat' para syntax highlighting (apt install bat)${RST}"
    fi
  fi
}

cmd_url() {
  local id="${1:-}"
  [[ -z "$id" ]] && die "uso: paste url <id>"

  local url="${HOST}/p/${id}"
  echo "$url"

  if to_clipboard "$url"; then
    echo -e "${GRN}✓ URL copiada al portapapeles${RST}"
  else
    echo -e "${YLW}⚠ no se encontró xclip/xsel/wl-copy${RST}"
  fi
}

cmd_descargar() {
  local id="${1:-}" destino="${2:-.}"
  [[ -z "$id" ]] && die "uso: paste descargar <id> [directorio]"

  api GET "/api/pastes/${id}" > /dev/null || die "paste no encontrado: $id"

  mkdir -p "$destino"

  # Obtener headers con GET (FastAPI no responde Content-Disposition a HEAD)
  local headers filename
  headers=$(curl -sf -D - -o /dev/null "${HOST}/p/${id}/download")
  filename=$(echo "$headers" | tr -d '\r' | grep -i 'content-disposition' \
    | sed 's/.*filename="\([^"]*\)".*/\1/')

  [[ -z "$filename" ]] && filename="${id}.txt"

  local out="${destino}/${filename}"
  curl -sf "${HOST}/p/${id}/download" -o "$out" || die "error al descargar el paste"

  echo -e "${GRN}✓ Guardado:${RST} ${BLD}${out}${RST}"
}

cmd_archivar() {
  local id="${1:-}"
  [[ -z "$id" ]] && die "uso: paste archivar <id>"

  api POST "/api/pastes/${id}/archive" > /dev/null || die "paste no encontrado: $id"
  echo -e "${YLW}⬇ Paste ${id} archivado${RST}"
}

cmd_restaurar() {
  local id="${1:-}"
  [[ -z "$id" ]] && die "uso: paste restaurar <id>"

  api POST "/api/pastes/${id}/unarchive" > /dev/null || die "paste no encontrado: $id"
  echo -e "${GRN}↑ Paste ${id} restaurado${RST}"
}

cmd_eliminar() {
  local id="${1:-}"
  [[ -z "$id" ]] && die "uso: paste eliminar <id>"

  printf "${RED}¿Eliminar paste ${id} permanentemente? [s/N]: ${RST}"
  read -r confirm
  [[ "$confirm" =~ ^[sS]$ ]] || { info "Cancelado."; exit 0; }

  curl -sf -X DELETE "${HOST}/api/pastes/${id}" > /dev/null \
    || die "paste no encontrado: $id"
  echo -e "${RED}✕ Paste ${id} eliminado${RST}"
}

cmd_ayuda() {
  echo -e "${BLD}paste${RST} — CLI para paste.sh autoalojado"
  echo -e "${DIM}Config: $CONFIG_FILE${RST}"
  echo
  echo -e "${BLD}Uso:${RST}"
  echo -e "  ${GRN}paste crear${RST} [-f archivo] [-t título] [-l lenguaje] [-e TTL] [-c]"
  echo -e "  ${GRN}paste listar${RST} [--archivados]"
  echo -e "  ${GRN}paste ver${RST} <id> [--raw]"
  echo -e "  ${GRN}paste url${RST} <id>                  — muestra y copia la URL"
  echo -e "  ${GRN}paste descargar${RST} <id> [directorio] — guarda el archivo en disco"
  echo -e "  ${GRN}paste archivar${RST} <id>"
  echo -e "  ${GRN}paste restaurar${RST} <id>"
  echo -e "  ${GRN}paste eliminar${RST} <id>"
  echo -e "  ${GRN}paste config${RST}                    — configurar host"
  echo
  echo -e "${BLD}Opciones de crear:${RST}"
  echo -e "  ${CYN}-f, --archivo${RST}   <ruta>          leer desde archivo"
  echo -e "  ${CYN}-t, --titulo${RST}    <texto>         título del paste"
  echo -e "  ${CYN}-l, --lenguaje${RST}  <lang>          lenguaje (bash, python, json...)"
  echo -e "  ${CYN}-e, --expira${RST}    <1h|1d|1w|Ns>   tiempo de expiración"
  echo -e "  ${CYN}-c, --clipboard${RST}                 copiar URL al portapapeles"
  echo
  echo -e "${BLD}Ejemplos:${RST}"
  echo -e "  ${DIM}cat script.sh | paste crear -t 'mi script' -l bash -c${RST}"
  echo -e "  ${DIM}paste crear -f config.yml -e 1d${RST}"
  echo -e "  ${DIM}paste listar${RST}"
  echo -e "  ${DIM}paste ver abc123${RST}"
  echo -e "  ${DIM}paste url abc123${RST}"
  echo -e "  ${DIM}paste descargar abc123${RST}"
  echo -e "  ${DIM}paste descargar abc123 ~/scripts${RST}"
}

# ── Main ───────────────────────────────────────────────────────────────────────
load_config

cmd="${1:-ayuda}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
  crear|new|c)         cmd_crear "$@"     ;;
  listar|ls|l)         cmd_listar "$@"    ;;
  ver|cat|v)           cmd_ver "$@"       ;;
  url|u)               cmd_url "$@"       ;;
  descargar|dl|d)      cmd_descargar "$@" ;;
  archivar|archive|a)  cmd_archivar "$@"  ;;
  restaurar|restore|r) cmd_restaurar "$@" ;;
  eliminar|rm|del)     cmd_eliminar "$@"  ;;
  config|cfg)          cmd_config         ;;
  ayuda|help|--help|-h) cmd_ayuda         ;;
  *) die "comando desconocido: $cmd. Usá 'paste ayuda'" ;;
esac
