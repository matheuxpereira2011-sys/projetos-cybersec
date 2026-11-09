
#!/usr/bin/env bash

APP="SBLNK"
VERSION="3.1"

BASE="$HOME/.sblnk"
mkdir -p "$BASE"

RESULT="$BASE/results.json"

CYAN='\033[38;5;51m'
GREEN='\033[38;5;82m'
YELLOW='\033[38;5;220m'
RED='\033[38;5;203m'
WHITE='\033[1;97m'
GRAY='\033[38;5;245m'
RESET='\033[0m'

if ! command -v dialog >/dev/null || ! command -v python3 >/dev/null; then
    echo "Instale as dependências:"
    echo "sudo apt install dialog python3 -y"
    exit 1
fi

TARGET=""
DEPTH=2
MAX=100

# MOTOR PYTHON
cat > "$BASE/engine.py" <<'PY'
import sys,json,urllib.request,urllib.parse
from collections import deque
from html.parser import HTMLParser

target=sys.argv[1]
depth_limit=int(sys.argv[2])
page_limit=int(sys.argv[3])
output=sys.argv[4]

p=urllib.parse.urlsplit(target)
if p.scheme not in ("http","https") or not p.netloc:
    sys.exit("URL inválida")

origin=(p.scheme,p.netloc)

class Parser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links=[]

    def handle_starttag(self,tag,attrs):
        for k,v in attrs:
            if k in ("href","src","action","data") and v:
                self.links.append(v)

def normalize(base,value):
    value=urllib.parse.urljoin(base,value)
    p=urllib.parse.urlsplit(value)
    if p.scheme not in ("http","https"):
        return None
    return urllib.parse.urlunsplit((p.scheme,p.netloc,p.path or "/",p.query,""))

def internal(url):
    p=urllib.parse.urlsplit(url)
    return (p.scheme,p.netloc)==origin

queue=deque([(target,0)])
visited=set()
found=set()
errors=[]

while queue and len(visited)<page_limit:
    url,depth=queue.popleft()

    if url in visited:
        continue

    visited.add(url)

    try:
        req=urllib.request.Request(
            url,
            headers={"User-Agent":"SBLNK/3.1"}
        )

        with urllib.request.urlopen(req,timeout=10) as r:
            final=r.geturl()
            content=r.read(1500000).decode("utf-8",errors="replace")
            ctype=r.headers.get_content_type()

    except Exception as e:
        errors.append({"url":url,"error":str(e)})
        continue

    found.add(final)
    links=[]

    if ctype in ("text/html","application/xhtml+xml"):
        parser=Parser()
        parser.feed(content)
        links.extend(parser.links)

    for raw in links:
        if raw.startswith(("javascript:","mailto:","tel:","data:","#")):
            continue

        link=normalize(final,raw)

        if not link:
            continue

        found.add(link)

        if not internal(link) or depth>=depth_limit:
            continue

        path=urllib.parse.urlsplit(link).path.lower()

        if path.endswith((".png",".jpg",".jpeg",".gif",".css",".js",".pdf",".zip")):
            continue

        if link not in visited:
            queue.append((link,depth+1))

data={
    "target":target,
    "visited":len(visited),
    "total":len(found),
    "internal":sorted(x for x in found if internal(x)),
    "external":sorted(x for x in found if not internal(x)),
    "errors":errors
}

with open(output,"w") as f:
    json.dump(data,f,indent=2)

PY

dashboard() {
    if [[ ! -f "$RESULT" ]]; then
        dialog --msgbox "Nenhum scan realizado." 7 40
        return
    fi

    python3 - "$RESULT" "$BASE/dashboard.txt" <<'PY'
import json,sys

d=json.load(open(sys.argv[1]))

text=f"""
SBLNK - SCAN DASHBOARD

TARGET: {d['target']}

PAGES VISITED: {d['visited']}
TOTAL LINKS: {d['total']}
INTERNAL: {len(d['internal'])}
EXTERNAL: {len(d['external'])}
ERRORS: {len(d['errors'])}

LAST RESULTS:
"""

for x in (d["internal"]+d["external"])[:25]:
    text+=x+"\n"

open(sys.argv[2],"w").write(text)
PY

    dialog --title "DASHBOARD" --textbox "$BASE/dashboard.txt" 24 85
}

configure() {
    local values
    values=$(dialog --stdout --title "TARGET CONFIGURATION" \
        --form "Configurar rastreamento" 14 65 3 \
        "URL:" 1 1 "$TARGET" 1 20 40 0 \
        "Profundidade:" 2 1 "$DEPTH" 2 20 10 0 \
        "Max páginas:" 3 1 "$MAX" 3 20 10 0) || return

    local -a fields=()
    mapfile -t fields <<< "$values"

    if [[ ${#fields[@]} -lt 3 ]]; then
        dialog --msgbox "Não foi possível ler os campos." 7 45
        return
    fi

    local new_target="${fields[0]}"
    local new_depth="${fields[1]}"
    local new_max="${fields[2]}"

    if [[ ! "$new_target" =~ ^https?://[^[:space:]]+$ ]]; then
        dialog --msgbox "URL inválida." 7 35
        return
    fi

    if [[ ! "$new_depth" =~ ^[0-9]+$ ]] ||
       [[ ! "$new_max" =~ ^[0-9]+$ ]]; then
        dialog --msgbox "Profundidade e limite precisam ser números." 8 50
        return
    fi

    if (( 10#$new_max < 1 )); then
        dialog --msgbox "O limite precisa ser maior que zero." 7 40
        return
    fi

    TARGET="$new_target"
    DEPTH="$new_depth"
    MAX="$new_max"

    dialog --msgbox "Configurações salvas!" 7 35
}

scan() {
    if [[ -z "$TARGET" ]]; then
        dialog --msgbox "Configure um alvo primeiro." 7 40
        return
    fi

    dialog --title "SCANNING" --infobox \
        "Rastreando site...\nAguarde." 7 40

    if python3 "$BASE/engine.py" "$TARGET" "$DEPTH" "$MAX" "$RESULT" \
        > "$BASE/error.log" 2>&1; then
        dashboard
    else
        dialog --title "SCAN ERROR" --textbox "$BASE/error.log" 15 65
    fi
}

view_links() {
    if [[ ! -f "$RESULT" ]]; then
        dialog --msgbox "Faça um scan primeiro." 7 40
        return
    fi

    local option
    option=$(dialog --stdout --menu "Tipo de link" 12 50 3 \
        1 "Internos" 2 "Externos" 3 "Todos") || return

    python3 - "$RESULT" "$option" "$BASE/links.txt" <<'PY'
import json,sys

d=json.load(open(sys.argv[1]))
mode=sys.argv[2]

links = (
    d["internal"] if mode=="1" else
    d["external"] if mode=="2" else
    d["internal"]+d["external"]
)

open(sys.argv[3],"w").write("\n".join(links) or "Nenhum link encontrado.")
PY

    dialog --title "LINK RESULTS" --textbox "$BASE/links.txt" 25 85
}

export_results() {
    if [[ ! -f "$RESULT" ]]; then
        dialog --msgbox "Nenhum resultado disponível." 7 40
        return
    fi

    python3 - "$RESULT" "$HOME/sblnk-results.txt" <<'PY'
import json,sys

d=json.load(open(sys.argv[1]))

with open(sys.argv[2],"w") as f:
    f.write("SBLNK RESULTS\n")
    f.write("TARGET: "+d["target"]+"\n\n")
    f.write("INTERNAL LINKS\n")
    f.write("\n".join(d["internal"])+"\n\n")
    f.write("EXTERNAL LINKS\n")
    f.write("\n".join(d["external"]))
PY

    dialog --msgbox "Exportado para ~/sblnk-results.txt" 8 50
}

history() {
    if [[ ! -f "$BASE/history.txt" ]]; then
        dialog --msgbox "Histórico vazio." 7 35
    else
        dialog --textbox "$BASE/history.txt" 20 70
    fi
}

while true; do

    option=$(dialog --stdout \
        --backtitle "SBLNK | WEB RECONNAISSANCE" \
        --title "SBLNK v$VERSION" \
        --menu "PAINEL PRINCIPAL\n\nAlvo: ${TARGET:-Não configurado}" \
        20 65 8 \
        1 "Configurar alvo" \
        2 "Iniciar scan" \
        3 "Dashboard" \
        4 "Visualizar links" \
        5 "Exportar resultados" \
        6 "Histórico" \
        7 "Sobre" \
        0 "Sair") || break

    case "$option" in
        1) configure ;;
        2)
            scan
            if [[ -f "$RESULT" ]]; then
                echo "$(date '+%F %T') | $TARGET" >> "$BASE/history.txt"
            fi
            ;;
        3) dashboard ;;
        4) view_links ;;
        5) export_results ;;
        6) history ;;
        7)
            dialog --msgbox \
                "SBLNK v$VERSION\n\nSite Links Explorer\nBash + Python + Dialog\n\nUse somente em sistemas autorizados." \
                10 50
            ;;
        0) break ;;
    esac
done

clear
echo "SBLNK encerrado."

