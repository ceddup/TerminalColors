# TerminalColors pour bash / zsh (Git Bash, WSL, MSYS2)
#
# Variante allegee du module PowerShell : meme resolution de couleur, memes
# couleurs automatiques, mais sans coloration de la bordure de fenetre (qui
# passe par une API Windows).
#
# Installation :
#     mkdir -p ~/.local/share/terminalcolors
#     cp shell/terminalcolors.sh ~/.local/share/terminalcolors/
#     echo 'source ~/.local/share/terminalcolors/terminalcolors.sh' >> ~/.bashrc
#
# Reglages (a definir avant le source) :
#     TERMINALCOLORS_TINT=0.30        intensite de la teinte du fond (0 a 1)
#     TERMINALCOLORS_BASE='#0C0C0C'   couleur de fond de reference
#     TERMINALCOLORS_TITLE=1          mettre a jour le titre de l'onglet
#     TERMINALCOLORS_ICONS=1          prefixer le titre d'un carre colore
#     TERMINALCOLORS_AUTOGIT=1        couleur automatique pour tout depot Git

: "${TERMINALCOLORS_TINT:=0.30}"
: "${TERMINALCOLORS_BASE:=#0C0C0C}"
: "${TERMINALCOLORS_TITLE:=1}"
: "${TERMINALCOLORS_ICONS:=1}"
: "${TERMINALCOLORS_AUTOGIT:=1}"

# Traduction des noms de couleurs (dont les alias de Solution Colors).
_tc_name_to_hex() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        burgundy)   printf '#FF6347' ;;
        pumpkin)    printf '#FF4500' ;;
        volt)       printf '#9ACD32' ;;
        mint)       printf '#66CDAA' ;;
        darkbrown)  printf '#8B4513' ;;
        lavender)   printf '#9370DB' ;;
        red)        printf '#FF0000' ;;
        green)      printf '#008000' ;;
        blue)       printf '#0000FF' ;;
        teal)       printf '#008080' ;;
        cyan)       printf '#00FFFF' ;;
        magenta)    printf '#FF00FF' ;;
        yellow)     printf '#FFFF00' ;;
        orange)     printf '#FFA500' ;;
        purple)     printf '#800080' ;;
        violet)     printf '#EE82EE' ;;
        pink)       printf '#FFC0CB' ;;
        brown)      printf '#A52A2A' ;;
        gray|grey)  printf '#808080' ;;
        gold)       printf '#FFD700' ;;
        olive)      printf '#808000' ;;
        navy)       printf '#000080' ;;
        maroon)     printf '#800000' ;;
        lime)       printf '#00FF00' ;;
        indigo)     printf '#4B0082' ;;
        salmon)     printf '#FA8072' ;;
        tomato)     printf '#FF6347' ;;
        crimson)    printf '#DC143C' ;;
        orangered)  printf '#FF4500' ;;
        steelblue)  printf '#4682B4' ;;
        seagreen)   printf '#2E8B57' ;;
        darkcyan)   printf '#008B8B' ;;
        chocolate)  printf '#D2691E' ;;
        yellowgreen)      printf '#9ACD32' ;;
        mediumaquamarine) printf '#66CDAA' ;;
        saddlebrown)      printf '#8B4513' ;;
        mediumpurple)     printf '#9370DB' ;;
        \#*)        printf '%s' "$1" ;;
        *)          printf '' ;;
    esac
}

_tc_normalize_color() {
    # Sortie toujours en majuscules, comme le module PowerShell.
    case "$1" in
        '#'*) printf '%s' "$1" | tr '[:lower:]' '[:upper:]' ;;
        *)    _tc_name_to_hex "$1" ;;
    esac
}

# Couleur stable derivee d'un nom : FNV-1a puis HSL, a l'identique du module
# PowerShell, afin qu'un depot ait la meme couleur partout.
_tc_auto_color() {
    printf '%s' "$1" | awk '
        function fnv(s,   h, i) {
            h = 2166136261
            for (i = 1; i <= length(s); i++) {
                h = xor2(h, ordv(substr(s, i, 1)))
                h = mul32(h, 16777619)
            }
            return h
        }
        function ordv(ch) {
            if (ch in ORD) return ORD[ch]
            return 0
        }
        function xor2(a, b,   r, bit) {
            r = 0; bit = 1
            while (a > 0 || b > 0) {
                if (((a % 2) + (b % 2)) == 1) r += bit
                a = int(a / 2); b = int(b / 2); bit *= 2
            }
            return r
        }
        function mul32(a, b,   r) {
            r = 0
            while (b > 0) {
                if (b % 2 == 1) r = (r + a) % 4294967296
                a = (a * 2) % 4294967296
                b = int(b / 2)
            }
            return r
        }
        function hsl(h, s, l,   c, x, m, r, g, b, seg) {
            c = (1 - abs(2 * l - 1)) * s
            seg = int(h / 60)
            x = c * (1 - abs(((h / 60) % 2) - 1))
            m = l - c / 2
            if (seg == 0)      { r = c; g = x; b = 0 }
            else if (seg == 1) { r = x; g = c; b = 0 }
            else if (seg == 2) { r = 0; g = c; b = x }
            else if (seg == 3) { r = 0; g = x; b = c }
            else if (seg == 4) { r = x; g = 0; b = c }
            else               { r = c; g = 0; b = x }
            printf "#%02X%02X%02X", int((r + m) * 255 + 0.5), int((g + m) * 255 + 0.5), int((b + m) * 255 + 0.5)
        }
        function abs(v) { return v < 0 ? -v : v }
        BEGIN {
            # Codes ASCII imprimables : suffisant pour des noms de depots.
            for (i = 32; i < 127; i++) ORD[sprintf("%c", i)] = i
        }
        {
            name = tolower($0)
            h = fnv(name)
            hue = (h % 24) * 15
            sat = 0.62 + (int(h / 256) % 3) * 0.09
            lig = 0.42 + (int(h / 65536) % 3) * 0.05
            hsl(hue, sat, lig)
        }
    '
}

_tc_emoji() {
    printf '%s' "$1" | awk '
        function abs(v) { return v < 0 ? -v : v }
        # strtonum() est propre a gawk : on decode a la main pour rester
        # compatible avec mawk (Debian/Ubuntu par defaut).
        function hex2(s,   i, d, v) {
            v = 0
            for (i = 1; i <= length(s); i++) {
                d = index("0123456789abcdef", tolower(substr(s, i, 1))) - 1
                if (d < 0) d = 0
                v = v * 16 + d
            }
            return v
        }
        {
            hex = substr($0, 2)
            r = hex2(substr(hex, 1, 2)) / 255
            g = hex2(substr(hex, 3, 2)) / 255
            b = hex2(substr(hex, 5, 2)) / 255
            max = (r > g ? (r > b ? r : b) : (g > b ? g : b))
            min = (r < g ? (r < b ? r : b) : (g < b ? g : b))
            l = (max + min) / 2
            d = max - min
            if (d == 0) { print (l >= 0.5 ? "WHITE" : "BLACK"); exit }
            s = d / (1 - abs(2 * l - 1))
            if (max == r)      h = 60 * ((g - b) / d)
            else if (max == g) h = 60 * ((b - r) / d + 2)
            else               h = 60 * ((r - g) / d + 4)
            if (h < 0) h += 360
            if (s < 0.15) { print (l >= 0.5 ? "WHITE" : "BLACK"); exit }
            if (h >= 15 && h < 45 && l < 0.38) { print "BROWN"; exit }
            if (h < 15 || h >= 340) { print "RED"; exit }
            if (h < 45)  { print "ORANGE"; exit }
            if (h < 70)  { print "YELLOW"; exit }
            if (h < 175) { print "GREEN"; exit }
            if (h < 265) { print "BLUE"; exit }
            print "PURPLE"
        }
    ' | while read -r key; do
        case "$key" in
            RED)    printf '\xF0\x9F\x9F\xA5' ;;
            ORANGE) printf '\xF0\x9F\x9F\xA7' ;;
            YELLOW) printf '\xF0\x9F\x9F\xA8' ;;
            GREEN)  printf '\xF0\x9F\x9F\xA9' ;;
            BLUE)   printf '\xF0\x9F\x9F\xA6' ;;
            PURPLE) printf '\xF0\x9F\x9F\xAA' ;;
            BROWN)  printf '\xF0\x9F\x9F\xAB' ;;
            WHITE)  printf '\xE2\xAC\x9C' ;;
            BLACK)  printf '\xE2\xAC\x9B' ;;
        esac
    done
}

_tc_blend() {
    # $1 = base, $2 = couleur, $3 = intensite
    awk -v base="$1" -v col="$2" -v t="$3" '
        function hex2(s,   i, d, v) {
            v = 0
            for (i = 1; i <= length(s); i++) {
                d = index("0123456789abcdef", tolower(substr(s, i, 1))) - 1
                if (d < 0) d = 0
                v = v * 16 + d
            }
            return v
        }
        function comp(hex, pos) { return hex2(substr(hex, pos, 2)) }
        BEGIN {
            b = substr(base, 2); c = substr(col, 2)
            if (t < 0) t = 0; if (t > 1) t = 1
            printf "#%02X%02X%02X",
                comp(b,1) + (comp(c,1) - comp(b,1)) * t + 0.5,
                comp(b,3) + (comp(c,3) - comp(b,3)) * t + 0.5,
                comp(b,5) + (comp(c,5) - comp(b,5)) * t + 0.5
        }
    '
}

_tc_json_value() {
    # Extrait une valeur textuelle simple : $1 = fichier, $2 = nom de la cle
    sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" 2>/dev/null | head -n 1
}

_tc_git_branch() {
    local dir="$1" head
    if [ -f "$dir/.git/HEAD" ]; then
        head=$(cat "$dir/.git/HEAD" 2>/dev/null)
        case "$head" in
            ref:*refs/heads/*) printf '%s' "${head##*refs/heads/}" ;;
        esac
    fi
}

# Renvoie "couleur|libelle|source" pour le dossier passe en argument, en
# remontant l'arborescence. Chaine vide si aucune couleur.
_tc_resolve() {
    local dir="$1" leaf="$1" color name file branch line

    while [ -n "$dir" ]; do
        for candidate in "$dir/.terminalcolors.json" "$dir/terminalcolors.json"; do
            if [ -f "$candidate" ]; then
                color=$(_tc_json_value "$candidate" 'color')
                name=$(_tc_json_value "$candidate" 'name')
                [ -z "$name" ] && name="${dir##*/}"
                if [ "$color" = "auto" ]; then
                    color=$(_tc_auto_color "$name")
                else
                    color=$(_tc_normalize_color "$color")
                fi
                if [ -n "$color" ]; then
                    printf '%s|%s|%s' "$color" "$name" "Config"
                    return 0
                fi
            fi
        done

        if [ -f "$dir/.vscode/settings.json" ]; then
            color=$(_tc_json_value "$dir/.vscode/settings.json" 'peacock.color')
            [ -z "$color" ] && color=$(_tc_json_value "$dir/.vscode/settings.json" 'titleBar.activeBackground')
            if [ -n "$color" ]; then
                printf '%s|%s|%s' "$(_tc_normalize_color "$color")" "${dir##*/}" "Peacock"
                return 0
            fi
        fi

        if [ -d "$dir/.vs" ]; then
            # Glob plutot que find : aucune dependance externe, et plus rapide.
            file=''
            for candidate in "$dir"/.vs/color.txt "$dir"/.vs/*/color.txt; do
                if [ -f "$candidate" ]; then file="$candidate"; break; fi
            done
            if [ -n "$file" ]; then
                branch=$(_tc_git_branch "$dir")
                line=''
                [ -n "$branch" ] && line=$(grep -m1 "^${branch}:" "$file" 2>/dev/null)
                [ -z "$line" ] && line=$(grep -m1 '^master:' "$file" 2>/dev/null)
                [ -z "$line" ] && line=$(head -n 1 "$file" 2>/dev/null)
                color=$(_tc_normalize_color "${line##*:}")
                if [ -n "$color" ]; then
                    name=$(basename "$(dirname "$file")")
                    [ "$name" = ".vs" ] && name="${dir##*/}"
                    printf '%s|%s|%s' "$color" "$name" "SolutionColors"
                    return 0
                fi
            fi
        fi

        if [ "$TERMINALCOLORS_AUTOGIT" = "1" ] && { [ -d "$dir/.git" ] || [ -f "$dir/.git" ]; }; then
            name="${dir##*/}"
            printf '%s|%s|%s' "$(_tc_auto_color "$name")" "$name" "GitRepository"
            return 0
        fi

        case "$dir" in
            */*) dir="${dir%/*}" ;;
            *)   dir='' ;;
        esac
    done

    return 1
}

_TC_LAST_DIR=''
_TC_LAST_KEY=''

_tc_apply() {
    local resolved color name icon tinted key
    resolved=$(_tc_resolve "$PWD") || resolved=''

    key="$resolved"
    [ "$key" = "$_TC_LAST_KEY" ] && return 0
    _TC_LAST_KEY="$key"

    if [ -z "$resolved" ]; then
        printf '\033]111\a'                         # fond par defaut
        [ "$TERMINALCOLORS_TITLE" = "1" ] && printf '\033]0;%s\a' "${SHELL##*/}"
        return 0
    fi

    color="${resolved%%|*}"
    name="${resolved#*|}"; name="${name%%|*}"

    tinted=$(_tc_blend "$TERMINALCOLORS_BASE" "$color" "$TERMINALCOLORS_TINT")
    printf '\033]11;%s\a' "$tinted"

    if [ "$TERMINALCOLORS_TITLE" = "1" ]; then
        icon=''
        [ "$TERMINALCOLORS_ICONS" = "1" ] && icon="$(_tc_emoji "$color") "
        printf '\033]0;%s%s\a' "$icon" "$name"
    fi
}

# Branchement sur l'invite
case "${ZSH_VERSION:-}" in
    '') # bash
        case "$PROMPT_COMMAND" in
            *_tc_apply*) ;;
            '')          PROMPT_COMMAND='_tc_apply' ;;
            *)           PROMPT_COMMAND="_tc_apply; $PROMPT_COMMAND" ;;
        esac
        ;;
    *)  # zsh
        autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd _tc_apply
        ;;
esac
