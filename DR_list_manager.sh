#!/bin/bash

# ==============================================================================
# CONFIGURAÇÕES INICIAIS E VARIÁVEIS
# ==============================================================================
APP_VERSAO="3.5"
#  Arquivo .csv padrão, sempre que inicia o app é esse arquivo que é carregado
ARQUIVO_CSV="Repeater_list.csv"
ARQUIVO_TEMP="temp_corrigido.csv"
LOCK_FILE="/tmp/dr_list_manager.lock"
exit_to_main=0
SCRIPT_PID=$$

count_records() {
    local n
    n=$(tail -n +2 "$ARQUIVO_CSV" 2>/dev/null | grep -c '[^[:space:]]' 2>/dev/null) || n=0
    echo "$n"
}

verificar_integridade_csv() {
    local arquivo="${1:-$ARQUIVO_CSV}"
    [ -f "$arquivo" ] || return 0
    local linha_errada
    linha_errada=$(awk -F';' 'NR>1 && NF!=17 && NF>0 {print NR; exit}' "$arquivo")
    if [[ -n "$linha_errada" ]]; then
        echo -e "${VERMELHO}⚠ Aviso: O arquivo '$arquivo' está corrompido na linha $linha_errada (espera-se 17 campos, encontrado $(awk -F';' -v l="$linha_errada" 'NR==l{print NF}' "$arquivo")).${NC}"
        echo -e "${AMARELO}Execute a Opção 5 -> Validar Base de Dados para tentar reparar.${NC}"
        return 1
    fi
    return 0
}

limpar_lock() {
    rm -f "$LOCK_FILE"
}

adquirir_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            echo -e "${VERMELHO}Erro: Já existe uma instância rodando (PID $lock_pid). Encerre a outra instância antes de abrir novamente.${NC}"
            return 1
        else
            echo -e "${AMARELO}Lock stale removido (PID $lock_pid não responde mais).${NC}"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo "$SCRIPT_PID" > "$LOCK_FILE"
    trap limpar_lock EXIT INT TERM
    return 0
}

GREEN='\033[38;5;46m'
WHITE='\033[1;37m'
YELLOW='\033[38;5;226m'
ORANGE='\033[38;5;208m'
RED='\033[38;5;196m'
RED_DARK='\033[38;5;124m'
GRAY='\033[38;5;250m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
VERMELHO='\033[0;31m'
BLUE='\033[38;5;39m'
BLUE_BRIGHT='\033[1;34m'
CIANO='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

TONS_VALIDOS=(
    "67,0" "69,3" "71,9" "74,4" "77,0" "79,7" "82,5" "85,4" "88,5" "91,5"
    "94,8" "97,4" "100,0" "103,5" "107,2" "110,9" "114,8" "118,8" "123,0"
    "127,3" "131,8" "136,5" "141,3" "146,2" "151,4" "156,7" "159,8" "162,2"
    "165,5" "167,9" "171,3" "173,8" "177,3" "179,9" "183,5" "186,2" "189,9"
    "192,8" "196,6" "199,5" "203,5" "206,5" "210,7" "218,1" "225,7" "229,1"
    "233,6" "241,8" "250,3" "254,1"
)

# ==============================================================================
# MOTOR INTERATIVO 1: LEITURA DE TEXTO E REGEX (COM AUTO-MAIÚSCULAS)
# ==============================================================================
ler_campo() {
    local prompt="$1" regex="$2" erro_msg="$3" valor_atual="$4" max_len="$5"

    while true; do
        local dica="[X p/ cancelar]"
        if [[ -n "$valor_atual" ]]; then dica="[Enter mantém: ${ORANGE}${valor_atual}${NC} | X p/ cancelar]"; fi

        local input_val
        echo -en ">> $prompt $dica: " >&2
        read input_val < /dev/tty

        if [[ "${input_val,,}" == "x" ]]; then return 1; fi
        if [[ -z "$input_val" && -n "$valor_atual" ]]; then echo "$valor_atual"; return 0; fi

        if [[ "$prompt" == *"Frequency"* || "$prompt" == *"Frequência"* || "$prompt" == *"Offset"* || "$prompt" == *"Latitude"* || "$prompt" == *"Longitude"* || "$prompt" == *"Tone"* ]]; then
            input_val="${input_val//./,}"
        fi

        if [[ "$prompt" == *"Call Sign"* || "$prompt" == *"Gateway"* ]]; then
            input_val="${input_val^^}"
        fi

        if [[ "$input_val" == *";"* ]]; then echo -e "  ${VERMELHO}Erro: O caractere ';' não é permitido.${NC}" >&2; continue; fi
        if [[ -n "$max_len" && ${#input_val} -gt $max_len ]]; then echo -e "  ${VERMELHO}Erro: Máximo de $max_len caracteres permitidos.${NC}" >&2; continue; fi

        if [[ -n "$regex" ]]; then
            if [[ "$input_val" =~ $regex ]]; then echo "$input_val"; return 0; else echo -e "  ${VERMELHO}Erro: $erro_msg${NC}" >&2; fi
        else
            if [[ "$input_val" =~ ^[[:print:]]*$ ]]; then echo "$input_val"; return 0; else echo -e "  ${VERMELHO}Erro: Caracteres não suportados.${NC}" >&2; fi
        fi
    done
}

# ==============================================================================
# MOTOR INTERATIVO 2: MENUS NUMERADOS PARA VALORES PADRONIZADOS
# ==============================================================================
ler_opcao() {
    local prompt="$1" default_val="$2"
    shift 2
    local opcoes=("$@")

    while true; do
        local menu_str=""
        for i in "${!opcoes[@]}"; do
            menu_str+="$((i+1))) ${opcoes[$i]}   "
        done

        local dica="[X p/ cancelar]"
        [[ -n "$default_val" ]] && dica="[Enter mantém: ${ORANGE}${default_val}${NC} | X p/ cancelar]"

        echo -e "  $prompt: ${AMARELO}${menu_str}${NC}" >&2
        local input_val
        echo -en ">> Escolha (1-${#opcoes[@]}) $dica: " >&2
        read input_val < /dev/tty

        [[ "${input_val,,}" == "x" ]] && return 1
        [[ -z "$input_val" && -n "$default_val" ]] && { echo "$default_val"; return 0; }

        if [[ "$input_val" =~ ^[0-9]+$ ]] && [ "$input_val" -ge 1 ] && [ "$input_val" -le "${#opcoes[@]}" ]; then
            echo "${opcoes[$((input_val - 1))]}"
            return 0
        fi
        echo -e "  ${VERMELHO}Erro: Escolha um número entre 1 e ${#opcoes[@]}.${NC}" >&2
    done
}

# ==============================================================================
# MOTOR INTERATIVO 3: TABELA DE TONS CTCSS
# ==============================================================================
ler_tom() {
    local prompt="$1" default_val="${2:-}"

    echo -e "\n  ${CIANO}--- TABELA DE TONS CTCSS PADRÃO ICOM ---${NC}" >&2
    local i col=0
    for ((i = 0; i < ${#TONS_VALIDOS[@]}; i++)); do
        printf "  ${AMARELO}%2d${NC}) %-6s" "$((i+1))" "${TONS_VALIDOS[$i]}" >&2
        ((col++))
        if [[ $((col % 7)) -eq 0 ]]; then echo >&2; fi
    done
    echo >&2

    while true; do
        local dica="[X p/ cancelar]"
        [[ -n "$default_val" ]] && dica="[Enter mantém: ${ORANGE}${default_val}${NC} | X p/ cancelar]"

        local input_val
        echo -en ">> $prompt (1-${#TONS_VALIDOS[@]}) $dica: " >&2
        read input_val < /dev/tty

        [[ "${input_val,,}" == "x" ]] && return 1
        [[ -z "$input_val" && -n "$default_val" ]] && { echo "$default_val"; return 0; }

        if [[ "$input_val" =~ ^[0-9]+$ ]] && [ "$input_val" -ge 1 ] && [ "$input_val" -le "${#TONS_VALIDOS[@]}" ]; then
            echo "${TONS_VALIDOS[$((input_val - 1))]}Hz"
            return 0
        fi
        echo -e "  ${VERMELHO}Erro: Escolha um número entre 1 e ${#TONS_VALIDOS[@]}.${NC}" >&2
    done
}

# ==============================================================================
# FUNÇÃO: CABEÇALHO DINÂMICO (ADAPTA À LARGURA DO TERMINAL)
# ==============================================================================
mostrar_cabecalho() {
    local cor_borda="${BLUE_BRIGHT}"
    if [[ "$1" == "--green" ]]; then cor_borda="${GREEN}"; shift; fi

    local cols
    cols=$(tput cols 2>/dev/null)
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || [[ "$cols" -lt 30 ]]; then cols=53; fi
    [[ "$cols" -gt 80 ]] && cols=80
    local inner=$((cols - 2))
    local borda
    printf -v borda '%*s' "$inner" ''
    borda="${borda// /═}"

    echo -e "${cor_borda}╔${borda}╗"
    for titulo in "$@"; do
        local len=${#titulo}
        local pad=$(( (inner - len) / 2 ))
        local pad_r=$(( inner - len - pad ))
        local titulo_safe="${titulo//%/%%}"
        printf "${cor_borda}║${WHITE}%${pad}s%s%${pad_r}s${cor_borda}║${NC}\n" '' "$titulo_safe" ''
    done
    echo -e "${cor_borda}╚${borda}╝${NC}"
}

imprimir_texto() {
    local cor="${1:-$NC}"; shift
    local cols
    cols=$(tput cols 2>/dev/null)
    [[ ! "$cols" =~ ^[0-9]+$ ]] || [[ "$cols" -lt 30 ]] && cols=53
    [[ "$cols" -gt 80 ]] && cols=80
    local max_char=$((cols - 2))
    local fold_text
    fold_text=$(printf '%s' "$*" | fold -s -w "$max_char")
    while IFS= read -r linha; do
        echo -e "${cor}${linha}${NC}"
    done <<< "$fold_text"
}

# ==============================================================================
# FUNÇÃO: SEPARADOR DINÂMICO (ADAPTA À LARGURA DO TERMINAL, MÁX 80)
# ==============================================================================
separador() {
    local cor="${1:-$VERDE}" char="${2:-═}"
    local cols
    cols=$(tput cols 2>/dev/null)
    if ! [[ "$cols" =~ ^[0-9]+$ ]] || [[ "$cols" -lt 30 ]]; then cols=53; fi
    [[ "$cols" -gt 80 ]] && cols=80
    local linha
    printf -v linha '%*s' "$cols" ''
    linha="${linha// /$char}"
    echo -e "${cor}${linha}${NC}"
}

# ==============================================================================
# FUNÇÃO: EXIBIR MENU PRINCIPAL
# ==============================================================================
mostrar_menu() {
    clear

    local _cols_m
    _cols_m=$(tput cols 2>/dev/null)
    [[ ! "$_cols_m" =~ ^[0-9]+$ ]] || [[ "$_cols_m" -lt 30 ]] && _cols_m=53
    [[ "$_cols_m" -gt 80 ]] && _cols_m=80
    local _inner_m=$(( _cols_m - 2 ))
    local _borda_m
    printf -v _borda_m '%*s' "$_inner_m" ''
    _borda_m="${_borda_m// /═}"

    echo -e "${GREEN}╔${_borda_m}╗"
    # Linha 1: título centralizado
    local _t1="GESTOR DE REPETIDORAS D-Star / FM / FM-N"
    local _len1=${#_t1}
    local _pad1=$(( (_inner_m - _len1) / 2 ))
    local _pad1r=$(( _inner_m - _len1 - _pad1 ))
    printf "${GREEN}║${WHITE}%${_pad1}s%s%${_pad1r}s${GREEN}║${NC}\n" '' "$_t1" ''
    # Linha 2: título centralizado, versão com 2 chars de respiro à direita
    local _t2l="LISTA DR ICOM"
    local _t2r="v${APP_VERSAO}"
    local _len2l=${#_t2l}
    local _pad2=$(( (_inner_m - _len2l) / 2 ))
    local _len2r=${#_t2r}
    # gap = tudo entre título e versão (sem contar 2 chars de respiro)
    local _gap=$(( _inner_m - _pad2 - _len2l - _len2r - 3 ))
    [[ "$_gap" -lt 1 ]] && _gap=1
    local _gap_pad
    printf -v _gap_pad '%*s' "$_gap" ''
    printf "${GREEN}║${WHITE}%${_pad2}s%s${_gap_pad}${GREEN}  ${_t2r} ║${NC}\n" '' "$_t2l"
    echo -e "${GREEN}╚${_borda_m}╝${NC}"
    echo -e "    Arquivo  : ${ORANGE}${ARQUIVO_CSV}${NC}"
    echo -e "    Registros: ${ORANGE}$(count_records)${NC}"

    # Contar grupos únicos
    if [ -f "$ARQUIVO_CSV" ]; then
        local n_grupos
        n_grupos=$(awk -F';' 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}' "$ARQUIVO_CSV" | sort -u | wc -l)
        echo -e "    Grupos   : ${ORANGE}${n_grupos}${NC}"
    fi
    echo
    echo -e "1. Editar Repetidoras ${GRAY}(Listar / Editar / Excluir)${NC}"
    echo    "2. Adicionar Repetidora"
    echo -e "3. Editar Grupos ${GRAY}(Renomear / Remover)${NC}"
    echo -e "4. Consulta Geral ${GRAY}(Filtros Avançados)${NC}"
    echo    "5. Gerenciar Base de Dados"
    echo    "X. Sair do Sistema"
    separador "$VERDE" "═"
    read -p "Escolha uma opção: " opcao < /dev/tty
}

# ==============================================================================
# MOTOR DE VALIDAÇÃO COM CORREÇÃO INTERATIVA ON-THE-FLY
# ==============================================================================
motor_validar_arquivo() {
    local arquivo_alvo="$1"
    > "$ARQUIVO_TEMP"
    local linha_num=1
    local correcoes_auto=0
    local linhas_ignoradas=0

    # Contar total de linhas do arquivo para mostrar progresso
    local total_linhas
    total_linhas=$(wc -l < "$arquivo_alvo")
    local total_dados=$((total_linhas - 1))

    declare -A chaves_vistas
    declare -A callsigns_modos
    declare -A callsigns_bandas
    while IFS=';' read -r group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset || [ -n "$group_no" ]; do
        utc_offset=$(echo "$utc_offset" | tr -d '\r')

        # Mostrar progresso a cada iteração
        if [ "$linha_num" -gt 1 ]; then
            local pct=$(( (linha_num - 2) * 100 / total_dados ))
            [[ "$pct" -gt 100 ]] && pct=100
            printf "\r${ORANGE}Progresso: %d / %d linhas (%d%%)${NC}" "$((linha_num - 1))" "$total_dados" "$pct" >&2
        fi

        if [ "$linha_num" -eq 1 ]; then
            echo "Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset" > "$ARQUIVO_TEMP"
            ((linha_num++)); continue
        fi

        while true; do
            local erros_linha=""

            if [[ "$freq" == *.* ]] || [[ "$offset" == *.* ]] || [[ "$lat" == *.* ]] || [[ "$lon" == *.* ]] || [[ "$rpt_tone" == *.* ]]; then
                freq="${freq//./,}"; offset="${offset//./,}"; lat="${lat//./,}"; lon="${lon//./,}"; rpt_tone="${rpt_tone//./,}"; ((correcoes_auto++))
            fi

            # Corrige Repeater Tone sem sufixo Hz
            if [[ "$mode" == "FM" || "$mode" == "FM-N" || "$mode" == "DV" ]]; then
                if [[ -n "$rpt_tone" ]] && [[ "$rpt_tone" != *Hz ]] && [[ ! "$rpt_tone" =~ [Hh][Zz]$ ]]; then
                    rpt_tone="${rpt_tone}Hz"; ((correcoes_auto++))
                fi
            fi

            if [[ "$dup" == "OFF" && "$offset" != "0,000000" ]]; then
                offset="0,000000"; ((correcoes_auto++))
            fi

            if [[ "$mode" == "DV" ]]; then
                if [[ "$tone" != "OFF" ]]; then tone="OFF"; ((correcoes_auto++)); fi
                if [[ "$rpt_tone" != "88,5Hz" ]]; then rpt_tone="88,5Hz"; ((correcoes_auto++)); fi
            elif [[ "$mode" == "FM" || "$mode" == "FM-N" ]]; then
                if [[ "$tone" == "OFF" && "$rpt_tone" != "88,5Hz" ]]; then
                    rpt_tone="88,5Hz"; ((correcoes_auto++))
                fi
            fi

            local chave_dup="${group_no}_${name}_${freq}"
            if [[ -n "${chaves_vistas[$chave_dup]}" && "${chaves_vistas[$chave_dup]}" != "$linha_num" ]]; then
                erros_linha+="  - Entrada Duplicada: idêntica à linha ${chaves_vistas[$chave_dup]}.\n"
            fi

            # Extração da Banda Atual (Usado no Call Sign)
            local freq_int="${freq//,/}"
            local banda_atual=""
            if [[ 10#$freq_int -ge 144000000 && 10#$freq_int -le 148000000 ]]; then banda_atual="VHF"
            elif [[ 10#$freq_int -ge 430000000 && 10#$freq_int -le 450000000 ]]; then banda_atual="UHF"
            else erros_linha+="  - Frequency: Fora do limite permitido (144-148 / 430-450 MHz).\n"; fi

            # Validação Híbrida do Indicativo (DV vs Banda Cruzada Analógica)
            if [[ -n "$rpt_call" ]]; then
                local res_conflito=""

                # Check 1: CSV Principal (se estivermos importando um externo)
                if [[ "$arquivo_alvo" != "$ARQUIVO_CSV" && -f "$ARQUIVO_CSV" ]]; then
                    res_conflito=$(awk -F';' -v call="$rpt_call" -v mode="$mode" -v band="$banda_atual" '
                    $5==call {
                        if ($10 == "DV" || mode == "DV") { print "DV"; exit }
                        f=$7; gsub(",", "", f); b="";
                        if (f >= 144000000 && f <= 148000000) b="VHF";
                        else if (f >= 430000000 && f <= 450000000) b="UHF";
                        if (b == band) { print "BAND"; exit }
                    }' "$ARQUIVO_CSV")
                fi

                # Check 2: Memória do próprio arquivo em processamento
                if [[ -z "$res_conflito" ]]; then
                    local mem_modo="${callsigns_modos[$rpt_call]}"
                    local mem_bandas="${callsigns_bandas[$rpt_call]}"
                    if [[ -n "$mem_modo" ]]; then
                        if [[ "$mode" == "DV" || "$mem_modo" == "DV" ]]; then res_conflito="DV"
                        elif [[ -n "$banda_atual" && "$mem_bandas" == *"$banda_atual"* ]]; then res_conflito="BAND"
                        fi
                    fi
                fi

                if [[ "$res_conflito" == "DV" ]]; then
                    erros_linha+="  - Indicativo '$rpt_call' conflita com regra DV (exclusividade total).\n"
                elif [[ "$res_conflito" == "BAND" ]]; then
                    erros_linha+="  - Indicativo '$rpt_call' já possui repetidora na banda $banda_atual.\n"
                fi
            fi

            if ! [[ "$group_no" =~ ^([1-9]|[1-4][0-9]|50)$ ]]; then erros_linha+="  - Group No: Inválido ($group_no).\n"; fi
            if [[ ${#group_name} -gt 16 ]] || ! [[ "$group_name" =~ ^[[:print:]]*$ ]]; then erros_linha+="  - Group Name: Inválido ou muito longo.\n"; fi
            if [[ ${#name} -gt 16 ]] || ! [[ "$name" =~ ^[[:print:]]*$ ]]; then erros_linha+="  - Name: Inválido ou muito longo.\n"; fi
            if [[ ${#sub_name} -gt 8 ]] || ! [[ "$sub_name" =~ ^[[:print:]]*$ ]]; then erros_linha+="  - Sub Name: Inválido ou muito longo.\n"; fi
            if ! [[ "$dup" =~ ^(OFF|DUP\+|DUP\-)$ ]]; then erros_linha+="  - Dup: Inválido ($dup).\n"; fi
            if ! [[ "$mode" =~ ^(DV|FM|FM-N)$ ]]; then erros_linha+="  - Mode: Inválido ($mode).\n"; fi

            if [[ "$dup" == "DUP+" || "$dup" == "DUP-" ]]; then
                if [[ "$mode" == "DV" ]]; then
                    if [[ -z "$rpt_call" ]] || [[ ${#rpt_call} -gt 8 ]] || ! [[ "$rpt_call" =~ ^.{7}[A-Z]$ ]]; then erros_linha+="  - Repeater Call: Inválido para DV.\n"; fi
                    if [[ -z "$gw_call" ]] || ! [[ "$gw_call" =~ ^.{7}G$ ]] || [[ "${rpt_call:0:7}" != "${gw_call:0:7}" ]]; then erros_linha+="  - Gateway Call: Inválido para DV.\n"; fi
                else
                    if [[ -n "$rpt_call" && ${#rpt_call} -gt 8 ]]; then erros_linha+="  - Repeater Call: Excede 8 char.\n"; fi
                    if [[ -n "$gw_call" ]]; then erros_linha+="  - Gateway Call: Deve estar vazio para FM/FM-N.\n"; fi
                fi
            else
                if [[ -n "$rpt_call" ]]; then erros_linha+="  - Repeater Call: Deve estar vazio para Simplex.\n"; fi
                if [[ -n "$gw_call" ]]; then erros_linha+="  - Gateway Call: Deve estar vazio para Simplex.\n"; fi
            fi

            if [[ "$dup" == "DUP+" || "$dup" == "DUP-" ]]; then
                if ! [[ "$offset" =~ ^[0-9],[0-9]{6}$ ]]; then erros_linha+="  - Offset: Formato inválido ($offset).\n"; fi
            fi

            if [[ "$mode" == "FM" || "$mode" == "FM-N" ]]; then
                if ! [[ "$tone" =~ ^(OFF|TONE|TSQL)$ ]]; then erros_linha+="  - TONE: Inválido ($tone).\n"; fi
                if [[ -n "$rpt_tone" ]]; then
                    local tom_limpo
                    tom_limpo=$(echo "$rpt_tone" | sed 's/Hz//i')
                    local tom_valido=false
                    for t in "${TONS_VALIDOS[@]}"; do if [[ "$t" == "$tom_limpo" ]]; then tom_valido=true; break; fi; done
                    if [[ "$tom_valido" == false ]]; then erros_linha+="  - Repeater Tone: Fora do padrão Icom ($rpt_tone).\n"; fi
                else
                    erros_linha+="  - Repeater Tone: Não pode estar vazio em FM/FM-N.\n"
                fi
            elif [[ "$mode" == "DV" ]]; then
                if [[ "$tone" != "OFF" ]]; then erros_linha+="  - TONE: Deve ser OFF para DV.\n"; fi
                if [[ "$rpt_tone" != "88,5Hz" ]]; then erros_linha+="  - Repeater Tone: Deve ser 88,5Hz para DV.\n"; fi
            fi

            if ! [[ "$rpt1use" =~ ^(YES|NO)$ ]]; then erros_linha+="  - RPT1USE: Inválido.\n"; fi
            if ! [[ "$position" =~ ^(None|Approximate|Exact)$ ]]; then erros_linha+="  - Position: Inválido.\n"; fi
            if ! [[ "$lat" =~ ^-?[0-9]{1,2},[0-9]{6}$ ]]; then erros_linha+="  - Latitude: Inválido.\n"; fi
            if ! [[ "$lon" =~ ^-?[0-9]{1,3},[0-9]{6}$ ]]; then erros_linha+="  - Longitude: Inválido.\n"; fi
            if ! [[ "$utc_offset" =~ ^([+-]?[0-9]{1,2}:[0-9]{2}|--:--)$ ]]; then erros_linha+="  - UTC Offset: Inválido.\n"; fi

            if [[ -n "$erros_linha" ]]; then
                echo -e "\n${VERMELHO}⚠ Erro(s) encontrado(s) na Linha $linha_num (${name}):${NC}"
                printf '%b\n' "$erros_linha"

                local acao_erro
                while true; do
                    read -p ">> Escolha: [C]orrigir | [I]gnorar linha | [A]bortar processo: " acao_erro < /dev/tty
                    acao_erro="${acao_erro,,}"
                    if [[ "$acao_erro" == "c" || "$acao_erro" == "i" || "$acao_erro" == "a" ]]; then break; fi
                done

                if [[ "$acao_erro" == "a" ]]; then
                    echo -e "${AMARELO}Validação abortada pelo usuário.${NC}"
                    rm -f "$ARQUIVO_TEMP"; return 1
                elif [[ "$acao_erro" == "i" ]]; then
                    echo -e "${AMARELO}Linha $linha_num ignorada e não será importada.${NC}"
                    ((linhas_ignoradas++)); break
                elif [[ "$acao_erro" == "c" ]]; then
                    echo -e "${CIANO}--- MODO CORREÇÃO ---${NC}"

                    group_no=$(ler_campo "Group No (1-50)" "^([1-9]|[1-4][0-9]|50)$" "1-50" "$group_no" "") || return 1
                    group_name=$(ler_campo "Group Name" "" "" "$group_name" 16) || return 1
                    name=$(ler_campo "Name" "" "" "$name" 16) || return 1
                    sub_name=$(ler_campo "Sub Name" "" "" "$sub_name" 8) || return 1
                    mode=$(ler_opcao "Mode" "$mode" "DV" "FM" "FM-N") || return 1
                    dup=$(ler_opcao "Dup" "$dup" "OFF" "DUP-" "DUP+") || return 1

                    if [[ "$dup" == "DUP+" || "$dup" == "DUP-" ]]; then offset=$(ler_campo "Offset" "^[0-9],[0-9]{6}$" "0,000000" "$offset" "") || return 1
                    else offset="0,000000"; fi

                    # No Modo Correção também perguntamos Frequência primeiro
                    while true; do
                        freq=$(ler_campo "Frequency (ex: 439,975000)" "^[0-9]{3},[0-9]{6}$" "Formato 000,000000" "$freq" "") || return 1
                        local f_int="${freq//,/}"
                        if [[ 10#$f_int -ge 144000000 && 10#$f_int -le 148000000 ]]; then banda_atual="VHF"; break;
                        elif [[ 10#$f_int -ge 430000000 && 10#$f_int -le 450000000 ]]; then banda_atual="UHF"; break;
                        else echo -e "  ${VERMELHO}Erro: Fora do limite permitido.${NC}" >&2; fi
                    done

                    while true; do
                        if [[ "$dup" != "OFF" ]]; then
                            if [[ "$mode" == "DV" ]]; then rpt_call=$(ler_campo "Repeater Call Sign" "^.{7}[A-Z]$" "Exige 8 char, final A-Z" "$rpt_call" 8) || return 1
                            else rpt_call=$(ler_campo "Repeater Call Sign (Opcional)" "" "" "$rpt_call" 8) || return 1; fi
                        else rpt_call=""; fi

                        if [[ -n "$rpt_call" ]]; then
                            local invalido=0

                            # Cruza com a Memória Interna da Importação
                            local m_md="${callsigns_modos[$rpt_call]}"
                            local m_bd="${callsigns_bandas[$rpt_call]}"
                            if [[ -n "$m_md" ]]; then
                                if [[ "$mode" == "DV" || "$m_md" == "DV" ]]; then
                                    echo -e "  ${VERMELHO}Erro: O Indicativo '$rpt_call' conflita com regra DV (neste arquivo).${NC}" >&2; invalido=1
                                elif [[ -n "$banda_atual" && "$m_bd" == *"$banda_atual"* ]]; then
                                    echo -e "  ${VERMELHO}Erro: O Indicativo '$rpt_call' já preencheu a banda $banda_atual (neste arquivo).${NC}" >&2; invalido=1
                                fi
                            fi

                            # Cruza com o DB
                            if [[ "$invalido" == "0" && "$arquivo_alvo" != "$ARQUIVO_CSV" && -f "$ARQUIVO_CSV" ]]; then
                                local c_res
                            c_res=$(awk -F';' -v call="$rpt_call" -v mode="$mode" -v band="$banda_atual" '
                                $5==call {
                                    if ($10 == "DV" || mode == "DV") { print "DV"; exit }
                                    f=$7; gsub(",", "", f); b="";
                                    if (f >= 144000000 && f <= 148000000) b="VHF";
                                    else if (f >= 430000000 && f <= 450000000) b="UHF";
                                    if (b == band) { print "BAND"; exit }
                                }' "$ARQUIVO_CSV")

                                if [[ "$c_res" == "DV" ]]; then echo -e "  ${VERMELHO}Erro: O Indicativo '$rpt_call' conflita com regra DV no DB.${NC}" >&2; invalido=1;
                                elif [[ "$c_res" == "BAND" ]]; then echo -e "  ${VERMELHO}Erro: O Indicativo '$rpt_call' já ocupa a banda $banda_atual no DB.${NC}" >&2; invalido=1; fi
                            fi
                            if [ $invalido -eq 1 ]; then continue; fi
                        fi
                        break
                    done

                    if [[ "$dup" != "OFF" && "$mode" == "DV" ]]; then
                        local gw_def="${rpt_call:0:7}G"
                        gw_call=$(ler_campo "Gateway Call Sign" "^.{7}G$" "Exige 8 posições, final G." "$gw_def" 8) || return 1
                    else gw_call=""; fi

                    if [[ "$mode" == "FM" || "$mode" == "FM-N" ]]; then
                        tone=$(ler_opcao "TONE" "$tone" "OFF" "TONE" "TSQL") || return 1
                        if [[ "$tone" != "OFF" ]]; then rpt_tone=$(ler_tom "Escolha o Repeater Tone" "${rpt_tone//Hz/}") || return 1
                        else rpt_tone="88,5Hz"; fi
                    elif [[ "$mode" == "DV" ]]; then
                        tone="OFF"; rpt_tone="88,5Hz"
                    fi

                    rpt1use=$(ler_opcao "RPT1USE" "$rpt1use" "YES" "NO") || return 1
                    position=$(ler_opcao "Position" "$position" "None" "Approximate" "Exact") || return 1

                    if [[ "$position" != "None" ]]; then
                        lat=$(ler_campo "Latitude" "^-?[0-9]{1,2},[0-9]{6}$" "Formato -00,000000" "$lat" "") || return 1
                        lon=$(ler_campo "Longitude" "^-?[0-9]{1,3},[0-9]{6}$" "Formato -000,000000" "$lon" "") || return 1
                    else lat="0,000000"; lon="0,000000"; fi

                    utc_offset=$(ler_campo "UTC Offset" "^([+-]?[0-9]{1,2}:[0-9]{2}|--:--)$" "-3:00 ou --:--" "$utc_offset" "") || return 1
                    continue
                fi
            else
                chaves_vistas[$chave_dup]=$linha_num

                # Registra na memória o Sucesso desta linha (para validar as seguintes no mesmo arquivo)
                if [[ -n "$rpt_call" ]]; then
                    callsigns_modos[$rpt_call]="$mode"
                    if [[ -z "${callsigns_bandas[$rpt_call]}" ]]; then
                        callsigns_bandas[$rpt_call]="$banda_atual"
                    elif [[ "${callsigns_bandas[$rpt_call]}" != *"$banda_atual"* ]]; then
                        callsigns_bandas[$rpt_call]+=",$banda_atual"
                    fi
                fi

                echo "$group_no;$group_name;$name;$sub_name;$rpt_call;$gw_call;$freq;$dup;$offset;$mode;$tone;$rpt_tone;$rpt1use;$position;$lat;$lon;$utc_offset" >> "$ARQUIVO_TEMP"
                break
            fi
        done
        ((linha_num++))
    done < "$arquivo_alvo"

    # Mostra 100% no final
    printf "\r${ORANGE}Progresso: %d / %d linhas (100%%)${NC}\n" "$total_dados" "$total_dados" >&2
    echo -e "\n${VERDE}Validação finalizada. Linhas válidas processadas: $((linha_num - 2 - linhas_ignoradas))${NC}"
    if [ $linhas_ignoradas -gt 0 ]; then echo -e "${AMARELO}Linhas ignoradas por conterem erros: $linhas_ignoradas${NC}"; fi
    if [ $correcoes_auto -gt 0 ]; then echo -e "${CIANO}Correções automáticas aplicadas: $correcoes_auto${NC}"; fi
    return 0
}

# ==============================================================================
# FUNÇÕES DE GERENCIAMENTO DE ARQUIVO (SELECIONAR E EXPORTAR)
# ==============================================================================
selecionar_base() {
    echo -e "\n${CIANO}--- SELECIONAR BASE DE DADOS ---${NC}"
    local backup_antes="${ARQUIVO_CSV}.backup"
    if [ -f "$ARQUIVO_CSV" ]; then
        cp "$ARQUIVO_CSV" "$backup_antes"
        echo -e "${AMARELO}Backup automático salvo: $backup_antes${NC}"
    fi
    echo -e "Base atual: ${AMARELO}$ARQUIVO_CSV${NC}"

    local arquivos_csv=()
    for f in *.csv; do
        if [[ -f "$f" && "$f" != "$ARQUIVO_TEMP" ]]; then arquivos_csv+=("$f"); fi
    done

    local input_val="" criar=""
    if [ ${#arquivos_csv[@]} -gt 0 ]; then
        echo -e "\n${AMARELO}--- ARQUIVOS CSV ENCONTRADOS ---${NC}"
        for i in "${!arquivos_csv[@]}"; do
            if [[ "${arquivos_csv[$i]}" == "$ARQUIVO_CSV" ]]; then
                printf " [%02d] - %s ${ORANGE}(Base Atual)${NC}\n" "$((i+1))" "${arquivos_csv[$i]}"
            else
                printf " [%02d] - %s\n" "$((i+1))" "${arquivos_csv[$i]}"
            fi
        done
        separador "$AMARELO"
        read -p ">> Escolha o número, digite um novo nome, ou X para cancelar: " input_val < /dev/tty
    else
        read -p ">> Digite o nome do novo arquivo CSV (ou X para cancelar): " input_val < /dev/tty
    fi

    if [[ "${input_val,,}" == "x" || -z "$input_val" ]]; then return; fi

    local nova_base=""
    # Verifica se o usuário digitou um número válido da lista
    if [[ "$input_val" =~ ^[0-9]+$ ]] && [ "$input_val" -ge 1 ] && [ "$input_val" -le "${#arquivos_csv[@]}" ]; then
        nova_base="${arquivos_csv[$((input_val-1))]}"
    else
        nova_base="$input_val"
    fi

    # Adiciona a extensão .csv automaticamente se o usuário esquecer
    if [[ "$nova_base" != *".csv" ]]; then
        nova_base="${nova_base}.csv"
    fi

    if [ ! -f "$nova_base" ]; then
        echo -e "${AMARELO}Aviso: O arquivo '$nova_base' não existe no diretório atual.${NC}"
        read -p "Deseja criar uma nova base vazia com este nome? (s/N): " criar < /dev/tty
        if [[ "${criar,,}" == "s" ]]; then
            echo "Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset" > "$nova_base"
            ARQUIVO_CSV="$nova_base"
            echo -e "${VERDE}Nova base '$ARQUIVO_CSV' criada e selecionada com sucesso!${NC}"
        else
            echo -e "${VERMELHO}Operação cancelada.${NC}"
        fi
    else
        ARQUIVO_CSV="$nova_base"
        registrar_operacao "SELECAO_BASE" "Base selecionada: $ARQUIVO_CSV"
        echo -e "${VERDE}Base alterada com sucesso para: '$ARQUIVO_CSV'${NC}"
    fi
    sleep 2
}

exportar_base() {
    echo -e "\n${CIANO}--- EXPORTAR BASE DE DADOS ---${NC}"
    if [ ! -f "$ARQUIVO_CSV" ]; then
        echo -e "${VERMELHO}Erro: A base atual '$ARQUIVO_CSV' não foi encontrada.${NC}"
        sleep 2; return
    fi

    local data_atual
    data_atual=$(date +%Y%m%d)
    local seq=1
    local nome_export=""

    # Loop para encontrar o próximo número de sequência disponível (01, 02, 03...)
    while true; do
        nome_export=$(printf "Rpt%s_%02d.csv" "$data_atual" "$seq")
        if [ ! -f "$nome_export" ]; then
            break
        fi
        ((seq++))
    done

    # Copia a base atual para o novo arquivo exportado
    if cp "$ARQUIVO_CSV" "$nome_export"; then
        registrar_operacao "EXPORT" "Base exportada como $nome_export"
        echo -e "${VERDE}Exportação concluída com sucesso!${NC}"
        echo -e "Arquivo gerado: ${AMARELO}$nome_export${NC}"
    else
        echo -e "${VERMELHO}Erro: Falha ao exportar. Verifique o espaço em disco.${NC}"
        rm -f "$nome_export"
    fi
    sleep 2
}

# ==============================================================================
# OPÇÃO 5: GERENCIAR BASE DE DADOS (Importar / Validar / Limpar / Exportar)
# ==============================================================================
gerenciar_base_menu() {
    clear
    mostrar_cabecalho "GERENCIAR BASE DE DADOS"
    echo -e "    Base atual selecionada: ${ORANGE}$ARQUIVO_CSV${NC}"
    echo -e "    Padrão do csv: ${ORANGE}Separador [ ; ], Decimal [ , ]${NC}\n"

    echo    "1. Selecionar Arquivo CSV Base"
    echo    "2. Importar CSV"
    echo -e "3. Exportar DR_list.csv ${GRAY}(RptYYYYMMDD_XX.csv)${NC}"
    echo    "4. Validar Base de Dados"
    echo -e "5. Limpar Base de Dados ${GRAY}(Mantém apenas cabeçalho)${NC}"
    echo    "X. Retornar"
    separador "$VERDE"
    read -p ">> Opção: " sub_opt < /dev/tty

    case $sub_opt in
        1) selecionar_base ;;
        2) importar_csv ;;
        3) exportar_base ;;
        4)
            if [ ! -f "$ARQUIVO_CSV" ]; then
                echo -e "${VERMELHO}Erro: O arquivo '$ARQUIVO_CSV' não foi encontrado.${NC}"
                sleep 2; return
            fi
            validar_base_dados
            ;;
        5)
            if [ ! -f "$ARQUIVO_CSV" ]; then
                echo -e "${VERMELHO}Erro: O arquivo '$ARQUIVO_CSV' não foi encontrado.${NC}"
                sleep 2; return
            fi
            limpar_base_dados
            ;;
        *) return ;;
    esac
}

validar_base_dados() {
    echo -e "\n${ORANGE}VERIFICANDO A BASE DE DADOS...${NC}"
    if motor_validar_arquivo "$ARQUIVO_CSV"; then
        mv "$ARQUIVO_TEMP" "$ARQUIVO_CSV"
        echo -e "${VERDE}A base de dados está padronizada.${NC}"
    fi
    read -p $'\nPressione [Enter] para voltar...' < /dev/tty
}

limpar_base_dados() {
    echo -e "\n${VERMELHO}⚠️  ATENÇÃO: Você está prestes a APAGAR TODOS os registros!${NC}"
    imprimir_texto "${GRAY}" "Esta ação não pode ser desfeita, a base ficará vazia."
    read -p "Tem certeza absoluta que deseja ZERAR o arquivo CSV? (s/N): " conf < /dev/tty

    if [[ "${conf,,}" == "s" ]]; then
        # Recria o arquivo CSV contendo apenas a primeira linha (cabeçalho oficial)
        echo "Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset" > "$ARQUIVO_CSV"
        registrar_operacao "LIMPEZA" "Base de dados zerada pelo usuário"
        limpar_backups_antigos 7
        echo -e "${VERDE}Base de dados zerada com sucesso! Apenas o cabeçalho foi mantido.${NC}"
    else
        echo -e "${CIANO}Operação cancelada. A base de dados foi mantida intacta.${NC}"
    fi
    sleep 2
}

# ==============================================================================
# OPÇÃO 5: IMPORTAR CSV
# ==============================================================================
importar_csv() {
    clear
    mostrar_cabecalho "IMPORTAR CSV"

    local arquivos_csv=()
    for f in *.csv; do
        if [[ -f "$f" && "$f" != "$ARQUIVO_TEMP" ]]; then arquivos_csv+=("$f"); fi
    done

    local input_val=""
    if [ ${#arquivos_csv[@]} -gt 0 ]; then
        echo -e "${AMARELO}--- ARQUIVOS CSV DISPONÍVEIS ---${NC}"
        for i in "${!arquivos_csv[@]}"; do
            if [[ "${arquivos_csv[$i]}" == "$ARQUIVO_CSV" ]]; then
                printf " [%02d] - %s ${ORANGE}(Base Atual - Não Importar)${NC}\n" "$((i+1))" "${arquivos_csv[$i]}"
            else
                printf " [%02d] - %s\n" "$((i+1))" "${arquivos_csv[$i]}"
            fi
        done
        separador "$AMARELO"
        read -p ">> Escolha o número do arquivo, digite o nome, ou X para cancelar: " input_val < /dev/tty
    else
        read -p ">> Digite o nome do arquivo (ex: arquivo.csv) ou X para cancelar: " input_val < /dev/tty
    fi

    if [[ "${input_val,,}" == "x" || -z "$input_val" ]]; then return; fi

    local file_import=""
    if [[ "$input_val" =~ ^[0-9]+$ ]] && [ "$input_val" -ge 1 ] && [ "$input_val" -le "${#arquivos_csv[@]}" ]; then
        file_import="${arquivos_csv[$((input_val-1))]}"
    else
        file_import="$input_val"
    fi

    if [[ "$file_import" != *".csv" ]]; then
        file_import="${file_import}.csv"
    fi

    if [ ! -f "$file_import" ]; then echo -e "${VERMELHO}Erro: Arquivo '$file_import' não encontrado!${NC}"; sleep 2; return; fi

    if [[ "$file_import" == "$ARQUIVO_CSV" ]]; then
        echo -e "${VERMELHO}Erro crítico: Você não pode importar a base atual para dentro dela mesma!${NC}"
        sleep 3; return
    fi

    echo -e "\n${ORANGE}--- Auditando o arquivo a importar ---${NC}"

    if motor_validar_arquivo "$file_import"; then
        echo -e "\n${AMARELO}Como deseja integrar estes dados na sua base?${NC}"
        echo "  [S] - SUBSTITUIR a base atual inteira por este arquivo"
        echo "  [A] - ADICIONAR (Append) estes dados ao final da base atual"
        echo "  [X] - CANCELAR importação"
        read -p ">> Opção: " acao_import < /dev/tty

        if [[ "${acao_import,,}" == "s" ]]; then
            mv "$ARQUIVO_TEMP" "$ARQUIVO_CSV"
            registrar_operacao "IMPORT" "Base substituída por: $ARQUIVO_TEMP"
            echo -e "${VERDE}Base Substituída com sucesso!${NC}"
        elif [[ "${acao_import,,}" == "a" ]]; then
            if [ ! -f "$ARQUIVO_CSV" ]; then
                mv "$ARQUIVO_TEMP" "$ARQUIVO_CSV"
            else
                # Sincronização Inteligente de Nomes de Grupos
                declare -A grupos_base
                while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
                    if [[ "$g_no" =~ ^[0-9]+$ ]]; then grupos_base["$g_no"]="$g_name"; fi
                done < "$ARQUIVO_CSV"

                declare -A grupos_import
                while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
                    if [[ "$g_no" =~ ^[0-9]+$ ]]; then grupos_import["$g_no"]="$g_name"; fi
                done < "$ARQUIVO_TEMP"

                for g in "${!grupos_import[@]}"; do
                    if [[ -n "${grupos_base[$g]}" && "${grupos_base[$g]}" != "${grupos_import[$g]}" ]]; then
                        echo -e "\n${AMARELO}⚠ Conflito no Grupo $g detetado!${NC}"
                        echo -e "  Base atual: ${VERDE}${grupos_base[$g]}${NC}"
                        echo -e "  Importação: ${CIANO}${grupos_import[$g]}${NC}"
                        echo "  [1] Manter o nome da Base Atual"
                        echo "  [2] Atualizar para o nome da Importação"

                        while true; do
                            read -p ">> Qual nome deseja unificar? (1/2): " conflito_opt < /dev/tty
                            if [[ "$conflito_opt" == "2" ]]; then
                                local tmp_gi; tmp_gi=$(mktemp)
                                awk -F';' -v OFS=';' -v gno="$g" -v gname="${grupos_import[$g]}" \
                                    'NR==1 {print; next} $1==gno {$2=gname} {print}' "$ARQUIVO_CSV" > "$tmp_gi" && mv "$tmp_gi" "$ARQUIVO_CSV"
                                break
                            elif [[ "$conflito_opt" == "1" ]]; then
                                local tmp_gb; tmp_gb=$(mktemp)
                                awk -F';' -v OFS=';' -v gno="$g" -v gname="${grupos_base[$g]}" \
                                    'NR==1 {print; next} $1==gno {$2=gname} {print}' "$ARQUIVO_TEMP" > "$tmp_gb" && mv "$tmp_gb" "$ARQUIVO_TEMP"
                                break
                            else
                                echo -e "${VERMELHO}Escolha 1 ou 2.${NC}"
                            fi
                        done
                    fi
                done

                tail -n +2 "$ARQUIVO_TEMP" >> "$ARQUIVO_CSV"
            fi
            rm -f "$ARQUIVO_TEMP"
            registrar_operacao "IMPORT" "Dados adicionados por append à base atual"
            echo -e "${VERDE}Dados adicionados à base existente com sucesso!${NC}"
        else
            rm -f "$ARQUIVO_TEMP"
            echo -e "${AMARELO}Importação cancelada.${NC}"
        fi
    fi
    read -p $'\nPressione [Enter] para voltar ao menu...' < /dev/tty
}

# ==============================================================================
# OPÇÃO 4: CONSULTA GERAL COM FILTROS AVANÇADOS E NAVEGAÇÃO
# ==============================================================================
consulta_geral() {
    exit_to_main=0
    unset map_grupos

    while true; do
        clear
        mostrar_cabecalho "CONSULTA BASE DE DADOS"
        if [ ! -f "$ARQUIVO_CSV" ]; then echo -e "${VERMELHO}Base vazia.${NC}"; sleep 2; return; fi

        local filtros_col=()
        local filtros_val=()
        local filtros_tipo=()

        imprimir_texto "$GRAY" "Permite combinar filtros por ate 3 campos chave."
        imprimir_texto "$GRAY" "Escolha um ou mais campos e entre com um valor, ao finalizar pressione [Enter] para pesquisar."

        for i in {1..3}; do
            echo -e "\n${CIANO}--- Filtro $i ---${NC}"
            echo "1) Grupo    2) Modo    3) RPT1USE    4) Call Sign    5) Frequência"
            read -p "Escolha o campo pelo número (ou [Enter] / X para cancelar): " escolha_campo < /dev/tty

            if [[ "${escolha_campo,,}" == "x" ]]; then return; fi
            if [[ -z "$escolha_campo" ]]; then break; fi

            local col_idx=0
            local termo_busca=""
            local tipo_match="parcial"

            case "$escolha_campo" in
                1)
                    echo -e "\n${AMARELO}--- GRUPOS DISPONÍVEIS ---${NC}"
                    unset map_grupos
                    declare -A map_grupos
                    while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
                        if [[ "$g_no" =~ ^[0-9]+$ ]]; then map_grupos["$g_no"]="$g_name"; fi
                    done < "$ARQUIVO_CSV"

                    for k in $(printf "%s\n" "${!map_grupos[@]}" | sort -n); do
                        printf " [%02d] - %s\n" "$k" "${map_grupos[$k]}"
                    done
                    separador "$AMARELO"

                    termo_busca=$(ler_campo "Número do Grupo" "^([1-9]|[1-4][0-9]|50)$" "Deve ser entre 1 e 50" "" "") || return
                    termo_busca=$((10#$termo_busca))
                    col_idx=1; tipo_match="exato"
                    ;;
                2)
                    termo_busca=$(ler_opcao "Modo" "" "DV" "FM" "FM-N") || return
                    col_idx=10; tipo_match="exato"
                    ;;
                3)
                    termo_busca=$(ler_opcao "RPT1USE" "" "YES" "NO") || return
                    col_idx=13; tipo_match="exato"
                    ;;
                4)
                    termo_busca=$(ler_campo "Call Sign (ou parte dele)" "" "" "" 8) || return
                    col_idx=5; tipo_match="parcial"
                    ;;
                5)
                    termo_busca=$(ler_campo "Frequência (ou parte dela)" "" "" "" "") || return
                    col_idx=7; tipo_match="parcial"
                    ;;
                *)
                    echo -e "${VERMELHO}Opção inválida, ignorada.${NC}"; continue
                    ;;
            esac

            if [[ -n "$termo_busca" ]]; then
                filtros_col+=("$col_idx")
                filtros_val+=("${termo_busca,,}")
                filtros_tipo+=("$tipo_match")
            fi
        done

        if [ ${#filtros_col[@]} -eq 0 ]; then
            echo -e "${AMARELO}Nenhum filtro aplicado. Retornando ao menu...${NC}"
            sleep 1; return
        fi

        # Coletar resultados primeiro
        unset dados_resultados dados_resultados_ordenados
        declare -a dados_resultados=()
        declare -a linhas_resultados=()
        local linha_csv=1
        while IFS=';' read -ra COLUNAS || [ -n "${COLUNAS[0]}" ]; do
            if [ "$linha_csv" -eq 1 ]; then ((linha_csv++)); continue; fi

            local match_all=true
            for j in "${!filtros_col[@]}"; do
                local idx=$((${filtros_col[$j]} - 1))
                local valor_coluna="${COLUNAS[$idx],,}"
                local valor_filtro="${filtros_val[$j]}"
                local tipo="${filtros_tipo[$j]}"

                if [[ "$tipo" == "exato" ]]; then
                    if [[ "$valor_coluna" != "$valor_filtro" ]]; then match_all=false; break; fi
                else
                    if [[ "$valor_coluna" != *"$valor_filtro"* ]]; then match_all=false; break; fi
                fi
            done

            if $match_all; then
                dados_resultados+=("${COLUNAS[1]};${COLUNAS[2]};${COLUNAS[4]};${COLUNAS[9]};${COLUNAS[6]};${linha_csv}")
            fi
            ((linha_csv++))
        done < "$ARQUIVO_CSV"

        if [ ${#dados_resultados[@]} -eq 0 ]; then
            echo -e "${VERMELHO}Nenhum resultado encontrado para os filtros informados.${NC}"
            read -p $'\nPressione [Enter]...' < /dev/tty
            break
        fi

        # Ordenar resultados por grupo (campo 1) e depois nome (campo 2)
        declare -a dados_resultados_ordenados=()
        while IFS= read -r linha_ord; do
            dados_resultados_ordenados+=("$linha_ord")
        done < <(printf '%s\n' "${dados_resultados[@]}" | sort -t';' -k1,1f -k2,2f)
        dados_resultados=("${dados_resultados_ordenados[@]}")
        unset dados_resultados_ordenados

        # Paginação de resultados
        local pagina=1
        local total_itens=${#dados_resultados[@]}

        while true; do
            clear
            local _cols_r; _cols_r=$(tput cols 2>/dev/null)
            [[ ! "$_cols_r" =~ ^[0-9]+$ ]] && _cols_r=53
            [[ "$_cols_r" -gt 80 ]] && _cols_r=80
            local _lines_r; _lines_r=$(tput lines 2>/dev/null)
            [[ ! "$_lines_r" =~ ^[0-9]+$ ]] || [[ "$_lines_r" -lt 15 ]] && _lines_r=24
            local itens_por_pagina=$(( _lines_r - 12 ))
            [[ "$itens_por_pagina" -lt 5 ]] && itens_por_pagina=5
            local total_paginas=$(( (total_itens + itens_por_pagina - 1) / itens_por_pagina ))
            local _label=" RESULTADOS "
            local _lado=$(( (_cols_r - ${#_label}) / 2 ))
            local _lado_r=$(( _cols_r - ${#_label} - _lado ))
            local _esq _dir
            printf -v _esq '%*s' "$_lado" ''; _esq="${_esq// /═}"
            printf -v _dir '%*s' "$_lado_r" ''; _dir="${_dir// /═}"
            echo -e "\n${VERDE}${_esq}${_label}${_dir}${NC}"
            printf "${AMARELO}%-3s | %-16s | %-16s | %-10s | %-4s | %-10s${NC}\n" " Nº " "GRUPO" "REPETIDORA" "INDICATIVO" "MODO" "FREQUENCIA"
            separador "$VERDE"

            local inicio=$(( (pagina - 1) * itens_por_pagina ))
            local fim=$(( inicio + itens_por_pagina ))
            [ "$fim" -gt "$total_itens" ] && fim=$total_itens
            declare -A mapa_linhas=()
            local contador_tela=1

            for ((i=inicio; i<fim; i++)); do
                IFS=';' read -r gn nm rc md fr lorig <<< "${dados_resultados[$i]}"
                mapa_linhas[$((contador_tela+inicio))]="$lorig"
                printf " %-3s | %-16.16s | %-16.16s | %-10.10s | %-4.4s | %-10.10s\n" \
                    "$((contador_tela+inicio))" "$gn" "$nm" "$rc" "$md" "$fr"
                ((contador_tela++))
            done

            separador "$VERDE"
            echo -e "${AMARELO}Página $pagina de $total_paginas ($total_itens itens)${NC}"
            echo -e "${CIANO}[P] Próx pg | [A] Pág anterior | [V] Nova Busca | [X] Menu Principal${NC}"
            read -p ">> Nº para detalhar (ou tecla indicada): " rep_escolhida < /dev/tty
            if [[ "${rep_escolhida,,}" == "x" ]]; then exit_to_main=1; return; fi
            if [[ "${rep_escolhida,,}" == "v" || -z "$rep_escolhida" ]]; then break; fi
            if [[ "${rep_escolhida,,}" == "p" ]]; then
                if [[ "$pagina" -lt "$total_paginas" ]]; then ((pagina++)); fi
                unset mapa_linhas
                continue
            fi
            if [[ "${rep_escolhida,,}" == "a" ]]; then
                if [[ "$pagina" -gt 1 ]]; then ((pagina--)); fi
                unset mapa_linhas
                continue
            fi

            if ! [[ "$rep_escolhida" =~ ^[0-9]+$ ]]; then
                echo -e "${VERMELHO}Erro: Insira apenas números ou [P/A] para navegar páginas.${NC}"; sleep 1; continue
            fi

            local linha_real=${mapa_linhas[$rep_escolhida]}
            if [[ -z "$linha_real" ]]; then echo -e "${VERMELHO}Opção inválida.${NC}"; sleep 1; continue; fi

            detalhar_repetidora "$linha_real"
            if [[ "$exit_to_main" == "1" ]]; then return; fi
        done
    done
}

# ==============================================================================
# OPÇÃO 1: LISTAR E DETALHAR REPETIDORAS COM NAVEGAÇÃO "VOLTAR"
# ==============================================================================
listar_repetidoras() {
    exit_to_main=0
    while true; do
        clear
        mostrar_cabecalho "RELAÇÃO DE GRUPOS CADASTRADOS"
        if [ ! -f "$ARQUIVO_CSV" ]; then echo -e "${VERMELHO}Aviso: Base vazia.${NC}"; sleep 2; return; fi
        unset map_grupos count_grupos
        declare -A map_grupos; declare -A count_grupos; local tem_grupos=0
        while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
            if [[ "$g_no" =~ ^[0-9]+$ ]]; then
                map_grupos["$g_no"]="$g_name"; count_grupos["$g_no"]=$((count_grupos["$g_no"] + 1)); tem_grupos=1
            fi
        done < "$ARQUIVO_CSV"

        if [ $tem_grupos -eq 0 ]; then echo -e "${VERMELHO}Nenhum grupo encontrado.${NC}"; read -p "Pressione [Enter]..." < /dev/tty; return; fi

        for k in $(printf "%s\n" "${!map_grupos[@]}" | sort -n); do
            printf " ${AMARELO}[%02d]${NC} - %-22.22s ${CIANO}( %02d estações cadastradas )${NC}\n" "$k" "${map_grupos[$k]}" "${count_grupos[$k]}"
        done

        separador "$VERDE"
        read -p "Digite o número do grupo (ou [X] Menu Principal): " num_grupo < /dev/tty
        if [[ "${num_grupo,,}" == "x" || -z "$num_grupo" ]]; then return; fi

        if ! [[ "$num_grupo" =~ ^[0-9]+$ ]]; then
            echo -e "${VERMELHO}Erro: Insira apenas números.${NC}"; sleep 1; continue
        fi

        num_grupo=$((10#$num_grupo))

        if [[ -z "${map_grupos[$num_grupo]}" ]]; then echo -e "${VERMELHO}Grupo inválido.${NC}"; sleep 1; continue; fi

        listar_repetidoras_do_grupo "$num_grupo" "${map_grupos[$num_grupo]}"
        if [[ "$exit_to_main" == "1" ]]; then return; fi
    done
}

listar_repetidoras_do_grupo() {
    local num_grupo=$1; local nome_grupo=$2
    local pagina=1

    while true; do
        # Calcular itens por página baseado na altura do terminal
        local term_lines
        term_lines=$(tput lines 2>/dev/null)
        [[ ! "$term_lines" =~ ^[0-9]+$ ]] || [[ "$term_lines" -lt 15 ]] && term_lines=24
        # Desconta: cabeçalho (~6 linhas), tabela header (2), separadores (2),
        # info de paginação (1), prompt de input (1)
        local itens_por_pagina=$(( term_lines - 12 ))
        [[ "$itens_por_pagina" -lt 5 ]] && itens_por_pagina=5
        clear
        mostrar_cabecalho "LISTANDO AS REPETIDORAS DO GRUPO $num_grupo — $nome_grupo"

        printf "${AMARELO}%-3s | %-16s | %-16s | %-10s | %-4s | %-10s${NC}\n" " Nº " "GRUPO" "REPETIDORA" "INDICATIVO" "MODO" "FREQUENCIA"
        separador "$VERDE"

        # Coletar todas as linhas do grupo e ordenar por nome da repetidora
        local dados_cru=()
        local linha_csv=1
        while IFS=';' read -r group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset || [ -n "$group_no" ]; do
            if [ "$linha_csv" -eq 1 ]; then ((linha_csv++)); continue; fi
            if [ "$group_no" == "$num_grupo" ]; then
                dados_cru+=("$(printf '%-16s|%-16s|%-10s|%-4s|%-10s|%s' "$group_name" "$name" "$rpt_call" "$mode" "$freq" "$linha_csv")")
            fi
            ((linha_csv++))
        done < "$ARQUIVO_CSV"

        # Ordenar por nome da repetidora (2º campo)
        local dados_grupo=()
        if [ ${#dados_cru[@]} -gt 0 ]; then
            while IFS= read -r linha_ordenada; do
                dados_grupo+=("$linha_ordenada")
            done < <(printf '%s\n' "${dados_cru[@]}" | sort -t'|' -k2,2f)
        fi

        # Reconstruir dados no formato usado e mapa de linhas
        declare -a dados_finais=()
        declare -a linhas_origem=()
        for dado in "${dados_grupo[@]}"; do
            IFS='|' read -r gn nm rc md fr lorig <<< "$dado"
            dados_finais+=("${gn};${nm};${rc};${md};${fr}")
            linhas_origem+=("$lorig")
        done

        local total_itens=${#dados_finais[@]}
        if [ "$total_itens" -eq 0 ]; then
            echo -e "${VERMELHO}Nenhuma repetidora encontrada.${NC}"
            unset dados_grupo dados_cru dados_finais linhas_origem
            read -p $'\nPressione [Enter]...' < /dev/tty
            return
        fi

        local total_paginas=$(( (total_itens + itens_por_pagina - 1) / itens_por_pagina ))
        local inicio=$(( (pagina - 1) * itens_por_pagina ))
        local fim=$(( inicio + itens_por_pagina ))
        [ "$fim" -gt "$total_itens" ] && fim=$total_itens

        local contador_tela=1; declare -A mapa_linhas=()
        for ((i=inicio; i<fim; i++)); do
            IFS=';' read -r gn nm rc md fr <<< "${dados_finais[$i]}"
            mapa_linhas[$((contador_tela+inicio))]="${linhas_origem[$i]}"
            printf " %-3s | %-16.16s | %-16.16s | %-10.10s | %-4.4s | %-10.10s\n" \
                "$((contador_tela+inicio))" "$gn" "$nm" "$rc" "$md" "$fr"
            ((contador_tela++))
        done

        separador "$VERDE"
        echo -e "${AMARELO}Página $pagina de $total_paginas ($total_itens itens)${NC}"
        unset dados_grupo dados_cru dados_finais linhas_origem

        echo -e "${CIANO}[P] Próx pg | [A] Pág anterior | [V] Voltar Grupos | [X] Menu Principal${NC}"
        read -p ">> Nº para detalhar (ou tecla indicada): " rep_escolhida < /dev/tty

        if [[ "${rep_escolhida,,}" == "x" ]]; then exit_to_main=1; return; fi
        if [[ "${rep_escolhida,,}" == "v" || -z "$rep_escolhida" ]]; then return; fi
        if [[ "${rep_escolhida,,}" == "p" ]]; then
            if [[ "$pagina" -lt "$total_paginas" ]]; then ((pagina++)); fi
            unset mapa_linhas
            continue
        fi
        if [[ "${rep_escolhida,,}" == "a" ]]; then
            if [[ "$pagina" -gt 1 ]]; then ((pagina--)); fi
            unset mapa_linhas
            continue
        fi

        if ! [[ "$rep_escolhida" =~ ^[0-9]+$ ]]; then
            echo -e "${VERMELHO}Erro: Insira apenas números ou [P/A] para navegar páginas.${NC}"; sleep 1; continue
        fi

        local linha_real=${mapa_linhas[$rep_escolhida]}
        if [[ -z "$linha_real" ]]; then echo -e "${VERMELHO}Opção inválida.${NC}"; sleep 1; continue; fi

        detalhar_repetidora "$linha_real"
        if [[ "$exit_to_main" == "1" ]]; then return; fi
    done
}

detalhar_repetidora() {
    local linha_alvo=$1; local linha_atual=1; local dados_rep=""
    while IFS= read -r linha; do
        if [ "$linha_atual" -eq "$linha_alvo" ]; then dados_rep="$linha"; break; fi
        ((linha_atual++))
    done < "$ARQUIVO_CSV"

    IFS=';' read -r group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset <<< "$dados_rep"

    clear
    mostrar_cabecalho "DETALHES DA REPETIDORA"

    echo -e " ${VERDE}1.  Número do Grupo:${NC}              $group_no"
    echo -e " ${VERDE}2.  Nome do Grupo:${NC}                $group_name"
    echo -e " ${VERDE}3.  Nome da Repetidora:${NC}           $name"
    echo -e " ${VERDE}4.  Nome Adicional (Sub Name):${NC}    $sub_name"
    echo -e " ${VERDE}5.  Indicativo:${NC}                   $rpt_call"
    echo -e " ${VERDE}6.  Indicativo do Gateway:${NC}        $gw_call"
    echo -e " ${VERDE}7.  Frequência:${NC}                   $freq"
    echo -e " ${VERDE}8.  Duplex (DUP):${NC}                 $dup"
    echo -e " ${VERDE}9.  Offset Freq.:${NC}                 $offset"
    echo -e " ${VERDE}10. Modo de Operação:${NC}             $mode"
    echo -e " ${VERDE}11. Tipo de subtom:${NC}               $tone"
    echo -e " ${VERDE}12. Frequência do subtom:${NC}         $rpt_tone"
    echo -e " ${VERDE}13. USE (From):${NC}                   $rpt1use"
    echo -e " ${VERDE}14. Localização:${NC}                  $position"
    echo -e " ${VERDE}15. Latitude:${NC}                     $lat"
    echo -e " ${VERDE}16. Longitude:${NC}                    $lon"
    echo -e " ${VERDE}17. UTC Offset:${NC}                   $utc_offset"
    separador "$VERDE" "═"

    echo -e "${CIANO}[E] Editar | [D] Excluir | [V] Voltar | [X] Menu Principal${NC}"
    read -p ">> Opção: " acao_detalhe < /dev/tty

    case "${acao_detalhe,,}" in
        e) formulario_repetidora "edit" "$linha_alvo" "$dados_rep" ;;
        d)
            read -p "Tem certeza que deseja EXCLUIR esta repetidora? (s/N): " conf < /dev/tty
            if [[ "${conf,,}" == "s" ]]; then
                local backup_del
                cp "$ARQUIVO_CSV" "${ARQUIVO_CSV}.backup"
                local linha_content
                linha_content=$(sed -n "${linha_alvo}p" "$ARQUIVO_CSV")
                if [[ "$linha_content" == "$dados_rep" ]]; then
                    local tmp_del_file
                    tmp_del_file=$(mktemp)
                    awk -v tgt="$linha_alvo" 'NR!=tgt' "$ARQUIVO_CSV" > "$tmp_del_file" && mv "$tmp_del_file" "$ARQUIVO_CSV"
                    registrar_operacao "EXCLUSAO" "Repetidora '$name' removida da base"
                    echo -e "${VERDE}Repetidora excluída com sucesso!${NC}"
                else
                    echo -e "${VERMELHO}Erro: A linha foi alterada desde a leitura. Exclusão abortada por segurança.${NC}"
                    echo -e "${AMARELO}Backup disponível: ${ARQUIVO_CSV}.backup${NC}"
                fi
                sleep 2
            fi
            ;;
        v) return ;;
        x) exit_to_main=1; return ;;
        *) return ;;
    esac
}

# ==============================================================================
# OPÇÃO 2: FORMULÁRIO DE INSERÇÃO E EDIÇÃO
# ==============================================================================
formulario_repetidora() {
    local acao=$1; local linha_alvo=${2:-}; local dados_antigos=${3:-}
    local group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset
    unset map_grupos

    clear
    if [[ "$acao" == "edit" ]]; then
        IFS=';' read -r group_no group_name name sub_name rpt_call gw_call freq dup offset mode tone rpt_tone rpt1use position lat lon utc_offset <<< "$dados_antigos"
        mostrar_cabecalho "EDITANDO REPETIDORA: $name"
    else
        mostrar_cabecalho "ADICIONANDO NOVA REPETIDORA"
        dup="OFF"; offset="0,000000"; mode="FM"; tone="OFF"; rpt_tone=""; rpt1use="YES"
        position="None"; lat="0,000000"; lon="0,000000"; utc_offset="-3:00"
    fi

    declare -A map_grupos
    if [ -f "$ARQUIVO_CSV" ]; then
        while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
            if [[ "$g_no" =~ ^[0-9]+$ ]]; then map_grupos["$g_no"]="$g_name"; fi
        done < "$ARQUIVO_CSV"
    fi

    echo -e "\n${AMARELO}--- GRUPOS DISPONÍVEIS ---${NC}"
    if [ ${#map_grupos[@]} -gt 0 ]; then
        for k in $(printf "%s\n" "${!map_grupos[@]}" | sort -n); do printf " [%02d] - %s\n" "$k" "${map_grupos[$k]}"; done
    else echo " Nenhum grupo cadastrado."; fi
    separador "$AMARELO"
    echo

    group_no=$(ler_campo "Group No (1-50)" "^([1-9]|[1-4][0-9]|50)$" "Deve ser entre 1 e 50" "$group_no" "") || return

    if [[ -n "${map_grupos[$group_no]}" ]]; then
        group_name="${map_grupos[$group_no]}"
        echo -e "  ${VERDE}>> Group Name associado automaticamente: $group_name${NC}"
    else
        group_name=$(ler_campo "Novo Group Name" "" "" "$group_name" 16) || return
    fi

    name=$(ler_campo "Name" "" "" "$name" 16) || return
    sub_name=$(ler_campo "Sub Name" "" "" "$sub_name" 8) || return

    mode=$(ler_opcao "Mode" "$mode" "DV" "FM" "FM-N") || return
    dup=$(ler_opcao "Dup" "$dup" "OFF" "DUP-" "DUP+") || return

    if [[ "$dup" == "DUP+" || "$dup" == "DUP-" ]]; then offset=$(ler_campo "Offset (ex: 5,000000)" "^[0-9],[0-9]{6}$" "Formato 0,000000" "$offset" "") || return
    else offset="0,000000"; fi

    # Lógica Dinâmica da Frequência
    local banda_atual=""
    while true; do
        freq=$(ler_campo "Frequency (ex: 439,975000)" "^[0-9]{3},[0-9]{6}$" "Formato 000,000000" "$freq" "") || return
        local freq_int="${freq//,/}"
        if [[ 10#$freq_int -ge 144000000 && 10#$freq_int -le 148000000 ]]; then
            banda_atual="VHF"
            break
        elif [[ 10#$freq_int -ge 430000000 && 10#$freq_int -le 450000000 ]]; then
            banda_atual="UHF"
            break
        else
            echo -e "  ${VERMELHO}Erro: A frequência deve estar entre 144-148 MHz ou 430-450 MHz.${NC}" >&2
        fi
    done

    # Lógica Híbrida do Call Sign (Dependente de Modo e Banda)
    while true; do
        if [[ "$dup" != "OFF" ]]; then
            if [[ "$mode" == "DV" ]]; then
                rpt_call=$(ler_campo "Repeater Call Sign" "^.{7}[A-Z]$" "DV exige 8 posições, final A-Z." "$rpt_call" 8) || return
            else
                rpt_call=$(ler_campo "Repeater Call Sign (Opcional)" "" "" "$rpt_call" 8) || return
            fi
        else
            rpt_call=""
        fi

        if [[ -n "$rpt_call" ]]; then
            local res_conflito=""
            if [ -f "$ARQUIVO_CSV" ]; then
                res_conflito=$(awk -F';' -v call="$rpt_call" -v mode="$mode" -v band="$banda_atual" -v ln="${linha_alvo:-0}" '
                NR!=ln && $5==call {
                    if ($10 == "DV" || mode == "DV") { print "DV"; exit }
                    f=$7; gsub(",", "", f); b="";
                    if (f >= 144000000 && f <= 148000000) b="VHF";
                    else if (f >= 430000000 && f <= 450000000) b="UHF";
                    if (b == band) { print "BAND"; exit }
                }' "$ARQUIVO_CSV")
            fi

            if [[ "$res_conflito" == "DV" ]]; then
                echo -e "  ${VERMELHO}Erro: O Indicativo '$rpt_call' conflita com a regra DV (exige/possui exclusividade absoluta).${NC}" >&2
                continue
            elif [[ "$res_conflito" == "BAND" ]]; then
                echo -e "  ${VERMELHO}Erro: O Indicativo '$rpt_call' já possui repetidora analógica operando na banda $banda_atual.${NC}" >&2
                continue
            fi
        fi
        break
    done

    # Gateway apenas gerado/exigido em Digital com Duplex
    if [[ "$dup" != "OFF" && "$mode" == "DV" ]]; then
        local gw_def="${rpt_call:0:7}G"
        gw_call=$(ler_campo "Gateway Call Sign" "^.{7}G$" "Exige 8 posições, final G." "${gw_call:-$gw_def}" 8) || return
    else
        gw_call=""
    fi

    if [[ "$mode" == "FM" || "$mode" == "FM-N" ]]; then
        tone=$(ler_opcao "TONE" "$tone" "OFF" "TONE" "TSQL") || return
        if [[ "$tone" != "OFF" ]]; then
            rpt_tone=$(ler_tom "Escolha o Repeater Tone" "${rpt_tone//Hz/}") || return
        else rpt_tone="88,5Hz"; fi
    elif [[ "$mode" == "DV" ]]; then
        tone="OFF"; rpt_tone="88,5Hz"
    fi

    rpt1use=$(ler_opcao "RPT1USE" "$rpt1use" "YES" "NO") || return
    position=$(ler_opcao "Position" "$position" "None" "Approximate" "Exact") || return

    if [[ "$position" != "None" ]]; then
        lat=$(ler_campo "Latitude (ex: -26,149167)" "^-?[0-9]{1,2},[0-9]{6}$" "Formato -00,000000" "$lat" "") || return
        lon=$(ler_campo "Longitude (ex: -49,812167)" "^-?[0-9]{1,3},[0-9]{6}$" "Formato -000,000000" "$lon" "") || return
    else lat="0,000000"; lon="0,000000"; fi

    utc_offset=$(ler_campo "UTC Offset (ex: -3:00)" "^([+-]?[0-9]{1,2}:[0-9]{2}|--:--)$" "Formato -3:00 ou --:--" "$utc_offset" "") || return

    local nova_linha="$group_no;$group_name;$name;$sub_name;$rpt_call;$gw_call;$freq;$dup;$offset;$mode;$tone;$rpt_tone;$rpt1use;$position;$lat;$lon;$utc_offset"

    echo
    if [[ "$acao" == "edit" ]]; then
        local tmp_file
        tmp_file=$(mktemp)
        awk -F';' -v target="$linha_alvo" -v newline="$nova_linha" 'NR==target {print newline; next} {print}' "$ARQUIVO_CSV" > "$tmp_file" && mv "$tmp_file" "$ARQUIVO_CSV"
        registrar_operacao "EDICAO" "Repetidora '$name' atualizada no CSV (linha $linha_alvo)"
        echo -e "${VERDE}Repetidora atualizada com sucesso no CSV!${NC}"
    else
        if [ ! -f "$ARQUIVO_CSV" ]; then echo "Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset" > "$ARQUIVO_CSV"; fi
        echo "$nova_linha" >> "$ARQUIVO_CSV"
        registrar_operacao "ADICAO" "Nova repetitora '$name' adicionada ao CSV"
        echo -e "${VERDE}Nova repetitora adicionada ao CSV!${NC}"
    fi
    sleep 2
}

# ==============================================================================
# OPÇÃO 3: EDITAR NOME DO GRUPO
# ==============================================================================
editar_grupos_menu() {
    clear
    mostrar_cabecalho "EDITAR GRUPOS"
    if [ ! -f "$ARQUIVO_CSV" ]; then echo -e "${VERMELHO}Aviso: Base vazia.${NC}"; sleep 2; return; fi

    echo    "1. Renomear Grupo"
    echo -e "2. Remover Grupo ${GRAY}(Move repetidoras vinculadas)${NC}"
    echo    "X. Voltar"
    separador "$VERDE"
    read -p ">> Opção: " sub_opt < /dev/tty

    case $sub_opt in
        1) renomear_grupo ;;
        2) remover_grupo ;;
        *) return ;;
    esac
}

renomear_grupo() {
    declare -A map_grupos; local tem_grupos=0
    while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
        if [[ "$g_no" =~ ^[0-9]+$ ]]; then map_grupos["$g_no"]="$g_name"; tem_grupos=1; fi
    done < "$ARQUIVO_CSV"

    if [ $tem_grupos -eq 0 ]; then echo -e "${VERMELHO}Nenhum grupo encontrado.${NC}"; sleep 2; return; fi

    echo -e "\n${AMARELO}--- GRUPOS DISPONÍVEIS ---${NC}"
    for k in $(printf "%s\n" "${!map_grupos[@]}" | sort -n); do printf " [%02d] - %s\n" "$k" "${map_grupos[$k]}"; done

    read -p "Número do grupo que deseja renomear (ou X para cancelar): " num_grupo < /dev/tty
    if [[ "${num_grupo,,}" == "x" || -z "$num_grupo" ]]; then return; fi
    if ! [[ "$num_grupo" =~ ^[0-9]+$ ]]; then echo -e "${VERMELHO}Erro: Insira apenas números.${NC}"; sleep 2; return; fi
    num_grupo=$((10#$num_grupo))

    if [[ -z "${map_grupos[$num_grupo]}" ]]; then echo -e "${VERMELHO}Grupo inválido.${NC}"; sleep 2; return; fi

    local nome_atual="${map_grupos[$num_grupo]}"
    echo -e "\nNome atual do Grupo $num_grupo: ${AMARELO}$nome_atual${NC}"

    local novo_nome
    novo_nome=$(ler_campo "Novo Nome do Grupo" "" "" "$nome_atual" 16) || return

    if [[ "$novo_nome" == "$nome_atual" ]]; then echo -e "\n${AMARELO}Cancelado.${NC}"; sleep 2; return; fi

    local tmp_file
    tmp_file=$(mktemp)
    awk -F';' -v tgt="$num_grupo" -v nname="$novo_nome" 'BEGIN {OFS=";"} NR==1 {print; next} $1==tgt {$2=nname; print; next} {print}' "$ARQUIVO_CSV" > "$tmp_file" && mv "$tmp_file" "$ARQUIVO_CSV"
    registrar_operacao "RENOMEAR_GRUPO" "Grupo $num_grupo renomeado de '$nome_atual' para '$novo_nome'"
    echo -e "\n${VERDE}Nome atualizado em todas as repetidoras vinculadas!${NC}"
    sleep 2
}

remover_grupo() {
    declare -A map_grupos
    while IFS=';' read -r g_no g_name rest || [ -n "$g_no" ]; do
        if [[ "$g_no" =~ ^[0-9]+$ ]]; then map_grupos["$g_no"]="$g_name"; fi
    done < "$ARQUIVO_CSV"

    echo -e "\n${AMARELO}--- GRUPOS DISPONÍVEIS ---${NC}"
    for k in $(printf "%s\n" "${!map_grupos[@]}" | sort -n); do printf " [%02d] - %s\n" "$k" "${map_grupos[$k]}"; done

    read -p "Número do grupo que deseja REMOVER (ou X): " num_g < /dev/tty
    if [[ "${num_g,,}" == "x" || -z "$num_g" ]]; then return; fi
    if ! [[ "$num_g" =~ ^[0-9]+$ ]]; then echo -e "${VERMELHO}Erro: Insira apenas números.${NC}"; sleep 2; return; fi
    num_g=$((10#$num_g))

    if [[ -z "${map_grupos[$num_g]}" ]]; then echo -e "${VERMELHO}Grupo inválido.${NC}"; sleep 2; return; fi

    echo -e "\n${VERMELHO}O que deseja fazer com as repetidoras do grupo ${map_grupos[$num_g]}?${NC}"
    echo "1. Mover todas para outro grupo existente"
    echo "2. Excluir todas as repetidoras deste grupo"
    echo "X. Cancelar"
    read -p ">> Opção: " acao_g < /dev/tty

    if [[ "$acao_g" == "2" ]]; then
        read -p "Tem certeza que deseja EXCLUIR todas as repetidoras do grupo ${map_grupos[$num_g]}? (s/N): " conf_del < /dev/tty
        if [[ "${conf_del,,}" != "s" ]]; then
            echo -e "${CIANO}Operação cancelada. Grupo mantido.${NC}"
            sleep 2; return
        fi
        cp "$ARQUIVO_CSV" "${ARQUIVO_CSV}.backup"
        local tmp_del
        tmp_del=$(mktemp)
        awk -F';' -v g="$num_g" 'NR==1 || $1 != g' "$ARQUIVO_CSV" > "$tmp_del" && mv "$tmp_del" "$ARQUIVO_CSV"
        registrar_operacao "EXCLUSAO_GRUPO" "Grupo $num_g e suas repetidoras removidos"
        echo -e "${VERDE}Grupo e respectivas repetidoras removidos com sucesso!${NC}"
    elif [[ "$acao_g" == "1" ]]; then
        read -p "Para qual número de grupo deseja mover? (1-50): " alvo_g < /dev/tty
        if ! [[ "$alvo_g" =~ ^([1-9]|[1-4][0-9]|50)$ ]]; then echo -e "${VERMELHO}Grupo destino inválido.${NC}"; sleep 2; return; fi

        local alvo_nome
        alvo_nome=$(awk -F';' -v g="$alvo_g" '$1==g {print $2; exit}' "$ARQUIVO_CSV")
        if [[ -z "$alvo_nome" ]]; then
            alvo_nome=$(ler_campo "Nome do Novo Grupo de Destino" "" "" "" 16) || return
        fi
        cp "$ARQUIVO_CSV" "${ARQUIVO_CSV}.backup"
        local tmp_mv
        tmp_mv=$(mktemp)
        awk -F';' -v OFS=';' -v src="$num_g" -v dst="$alvo_g" -v dname="$alvo_nome" \
            'NR==1 {print; next} $1==src {$1=dst; $2=dname} {print}' "$ARQUIVO_CSV" > "$tmp_mv" && mv "$tmp_mv" "$ARQUIVO_CSV"
        registrar_operacao "MOVER_GRUPO" "Registros do grupo $num_g movidos para grupo $alvo_g"
        echo -e "${VERDE}Registros movidos para o grupo $alvo_g com sucesso!${NC}"
    fi
    sleep 2
}

# ==============================================================================
# LOG DE OPERACOES
# ==============================================================================
LOG_FILE="./dr_manager.log"

registrar_operacao() {
    local operacao="$1"; local detalhe="${2:-}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $operacao: $detalhe" >> "$LOG_FILE"
}

limpar_backups_antigos() {
    local dias_retencion="${1:-7}"
    local encontrados=0
    for backup in "${ARQUIVO_CSV}".backup*; do
        [ -f "$backup" ] || continue
        local modificado
        modificado=$(find "$backup" -mtime +"$dias_retencion" 2>/dev/null)
        if [[ -n "$modificado" ]]; then
            rm -f "$backup"
            ((encontrados++))
        fi
    done
    [[ "$encontrados" -gt 0 ]] && registrar_operacao "LIMPEZA" "$encontrados backup(s) antigo(s) removido(s)"
}

# ==============================================================================
# LOOP PRINCIPAL
# ==============================================================================
if ! adquirir_lock; then exit 1; fi

registrar_operacao "INICIO" "Sistema iniciado com base: $ARQUIVO_CSV"

limpar_backups_antigos 7

while true; do
    verificar_integridade_csv
    mostrar_menu
    case $opcao in
        1) listar_repetidoras ;;
        2) formulario_repetidora "add" ;;
        3) editar_grupos_menu ;;
        4) consulta_geral ;;
        5) gerenciar_base_menu ;;
        x|X) registrar_operacao "FIM" "Sistema encerrado pelo usuário"; echo -e "\nSaindo do sistema. 73!\n"; exit 0 ;;
        *) echo -e "\n${VERMELHO}Opção inválida! Tente novamente.${NC}"; sleep 1 ;;
    esac
done
