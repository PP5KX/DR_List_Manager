# ✨ ICOM DR List Manager

<div align="center">

![Version](https://img.shields.io/badge/Version-v3.5-blue)
![Linux](https://img.shields.io/badge/Debian-13%2B-red)
![License](https://img.shields.io/badge/License-GNU-yellow)
![Maintained](https://img.shields.io/badge/Maintained-yes-green)

**A utility for managing Digital Repeater (DR) lists compatible with any ICOM transceiver that has ***DR mode*****  
Manage • Validate • Import • Export                                                                                                

[Features](#features) • [Requirements](#requirements) • [Installation](#installation) • [CSV Format](#csv-format) • [Menu Structure](#menu-structure) • [Field Reference](#field-reference) • [Validation Rules](#validation-rules) • [Usage Tips](#usage-tips) • [Logging](#logging)

</div>

---

## Overview

Any ICOM transceiver equipped with **DR mode** (ID-31, ID-51, ID-52, ID-5100, IC-9700, and similar models) can load a structured repeater list through the respective **CS** programming software. `DR_list_manager.sh` provides a fully interactive, menu-driven TUI (Text User Interface) to build and maintain that list directly in the terminal — no GUI tools required. Entries are stored in a plain CSV file that can be exported and imported directly into the ICOM programming software. Designed for the Amateur Radio community, with locale-aware formatting can be easily applied in any scenario.

---

## Features

- **Interactive TUI** — dynamic headers and separators that adapt to any terminal width (up to 80 columns)
- **Three operating modes** — DV (D-Star), FM, and FM-N, each with mode-specific field logic
- **Group management** — organize repeaters into up to 50 named groups; rename or remove groups with automatic cascading updates
- **Full CRUD** — add, edit, and delete repeaters through guided prompts
- **Advanced search** — query the database using up to 3 combined filters (Group, Mode, RPT1USE, Call Sign, Frequency) with paginated results
- **Field validation** — per-field rules enforce correct callsigns, frequencies, offsets, CTCSS tones, and text length limits
- **Duplicate detection** — catches repeated entries (same group + name + frequency) before they cause issues in the radio
- **Callsign conflict detection** — prevents a DV callsign from being reused in any other mode, and blocks the same FM/FM-N callsign from appearing in the same band twice
- **Automatic corrections** — decimal separators (`.` → `,`), missing `Hz` suffix on tones, and mismatched offset values are fixed automatically during validation
- **CSV import with merge** — import an external CSV and choose to replace or append to the current database; group name conflicts are resolved interactively
- **Export with sequential naming** — exports are saved as `RptYYYYMMDD_XX.csv` with auto-incrementing sequence numbers
- **Instance locking** — a PID-based lock file (`/tmp/dr_list_manager.lock`) prevents multiple simultaneous instances
- **Operation log** — all add, edit, delete, import, and export actions are timestamped in `dr_manager.log`
- **Universal cancel** — press `X` at any prompt to abort the current operation and return to the previous menu
- **Colorized prompts** — default values highlighted in orange for quick visual reference
- **Locale-aware formatting** — uses `;` as the column separator and `,` as the decimal separator

---

## Requirements

| Dependency | Notes |
|---|---|
| Bash 4.0+ | Associative arrays required |
| `awk` | Field parsing and in-place updates |
| `grep` | Pattern matching |
| `sed` | Text substitution |
| `tput` | Terminal width/height detection |
| `mktemp` | Safe temporary file creation |
| `date` | Log timestamps and export filenames |

No external packages or internet access required. Runs entirely offline.

---

## Installation

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/DR_list_manager.git
cd DR_list_manager

# Make the script executable
chmod +x DR_list_manager.sh

# Run
./DR_list_manager.sh
```

On startup, the script automatically loads `Repeater_list.csv` from the current directory if it exists. A different base file can be selected at runtime from the **Manage Database** menu (Option 5 → Option 1).

---

## CSV Format

> ⚠️ **Locale formatting — important**
>
> This application uses the following conventions, matching Brazilian system locale and the ICOM CS programming software behavior under `pt_BR`:
>
> - **Column separator:** `;` (semicolon)
> - **Decimal separator:** `,` (comma)
>
> Files using `.` (period) as a decimal separator or `,` (comma) as a column separator **will not parse correctly**. The validator can auto-correct period-based decimals during import.

### Column structure

The CSV contains **17 columns** in the following order:

| # | Column | Description | Example |
|---|---|---|---|
| 1 | `Group No` | Group number (1–50) | `4` |
| 2 | `Group Name` | Display name of the group (max 16 chars) | `Santa Catarina` |
| 3 | `Name` | Repeater display name (max 16 chars) | `Florianopolis` |
| 4 | `Sub Name` | Secondary label (max 8 chars) | `Centro` |
| 5 | `Repeater Call Sign` | Local repeater callsign (max 8 chars) | `PP5ZFP B` |
| 6 | `Gateway Call Sign` | D-Star gateway callsign (DV only, max 8 chars) | `PP5ZFP G` |
| 7 | `Frequency` | Receive frequency in MHz | `439,975000` |
| 8 | `Dup` | Duplex direction | `DUP-` |
| 9 | `Offset` | Frequency offset in MHz | `5,000000` |
| 10 | `Mode` | Operating mode | `DV` |
| 11 | `TONE` | Subtone type | `OFF` |
| 12 | `Repeater Tone` | CTCSS tone with Hz suffix | `88,5Hz` |
| 13 | `RPT1USE` | Whether RPT1 slot is used | `YES` |
| 14 | `Position` | Coordinate precision level | `Approximate` |
| 15 | `Latitude` | Geographic latitude | `-27,597222` |
| 16 | `Longitude` | Geographic longitude | `-48,549167` |
| 17 | `UTC Offset` | Time zone offset | `-3:00` |

### Example rows

```
Group No;Group Name;Name;Sub Name;Repeater Call Sign;Gateway Call Sign;Frequency;Dup;Offset;Mode;TONE;Repeater Tone;RPT1USE;Position;Latitude;Longitude;UTC Offset
4;Santa Catarina;Florianopolis;Centro;PP5ZFP B;PP5ZFP G;439,975000;DUP-;5,000000;DV;OFF;88,5Hz;YES;Approximate;-27,597222;-48,549167;-3:00
4;Santa Catarina;Florianopolis;;PP5ZFP;;147,075000;DUP+;0,600000;FM;TSQL;88,5Hz;YES;Approximate;-27,597222;-48,549167;-3:00
5;Parana;Curitiba Simplex;;;;146,520000;OFF;0,000000;FM;OFF;88,5Hz;YES;None;0,000000;0,000000;-3:00
```

### Organizational conventions (Brazilian reference list)

The bundled `Repeater_list.csv` follows a geographic convention suited to Brazil, though the structure is flexible enough to be adapted to any country or region:

- **Group No / Group Name** — each group represents a Brazilian **state** (e.g. Group 4 = Santa Catarina, Group 5 = Paraná). For other regions, groups could represent countries, provinces, counties, or any other logical division.
- **Name** — identifies the **city** or locality where the repeater is located (e.g. `Florianopolis`, `Curitiba`).
- **Sub Name** — an 8-character secondary label. Use it to add context when a city has multiple repeaters of the same mode, to indicate a club callsign abbreviation, a site name, or any other distinguishing detail (e.g. `Centro`, `Serra`, `146MHz`).

---

## Menu Structure

### Menu Map

The diagram below shows the full navigation structure of the application. Every branch can be cancelled at any prompt by pressing `X`.

```mermaid
flowchart TD
    START([▶ Start]) --> MAIN

    MAIN["🏠 MAIN MENU
    ──────────────────
    1 · Edit Repeaters
    2 · Add Repeater
    3 · Edit Groups
    4 · Advanced Query
    5 · Manage Database
    X · Exit"]

    MAIN -->|1| OPT1
    MAIN -->|2| OPT2
    MAIN -->|3| OPT3
    MAIN -->|4| OPT4
    MAIN -->|5| OPT5
    MAIN -->|X| EXIT([🔴 Exit])

    OPT1["📋 GROUP LIST
    ─────────────────────
    Lists all groups
    with station count"]
    OPT1 --> GRPLIST["📄 REPEATER LIST
    ─────────────────────
    Paginated list
    sorted by name
    ─────────────────────
    P · Next page
    A · Prev page
    V · Back to groups
    X · Main menu"]
    GRPLIST -->|Select №| DETAIL

    DETAIL["🔍 REPEATER DETAIL
    ─────────────────────
    Shows all 17 fields
    ─────────────────────
    E · Edit
    D · Delete
    V · Back
    X · Main menu"]
    DETAIL -->|E| OPT2
    DETAIL -->|D| CONFIRM_DEL{{"Confirm\ndelete?"}}
    CONFIRM_DEL -->|s| DEL_OK(["✅ Deleted"])
    CONFIRM_DEL -->|N| DETAIL

    OPT2["✏️ ADD / EDIT FORM
    ─────────────────────
    Group No → Name
    Sub Name → Mode
    Dup → Offset
    Frequency → Call Sign
    Gateway → TONE
    RPT1USE → Position
    Lat / Lon → UTC Offset
    ─────────────────────
    Enter · keep default
    X · cancel anytime"]
    OPT2 --> SAVED(["✅ Saved to CSV"])

    OPT3["👥 EDIT GROUPS
    ─────────────────────
    1 · Rename Group
    2 · Remove Group
    X · Back"]
    OPT3 -->|1| RENAME["Rename → updates\nall linked entries"]
    OPT3 -->|2| REMOVE["Remove →
    Move to other group
    or delete all entries"]

    OPT4["🔎 ADVANCED QUERY
    ─────────────────────
    Up to 3 filters:
    · Group (exact)
    · Mode (exact)
    · RPT1USE (exact)
    · Call Sign (partial)
    · Frequency (partial)"]
    OPT4 --> RESULTS["📊 PAGINATED RESULTS
    ─────────────────────
    Sorted by group / name
    ─────────────────────
    P · Next page
    A · Prev page
    V · New search
    X · Main menu"]
    RESULTS -->|Select №| DETAIL

    OPT5["💾 MANAGE DATABASE
    ─────────────────────
    1 · Select CSV file
    2 · Import CSV
    3 · Export CSV
    4 · Validate database
    5 · Clear database
    X · Back"]
    OPT5 -->|1| SEL["Select or create\na CSV base file"]
    OPT5 -->|2| IMP["Validate external CSV
    → Replace or Append
    → Resolve group conflicts"]
    OPT5 -->|3| EXP["Save as\nRptYYYYMMDD_XX.csv"]
    OPT5 -->|4| VAL["Validate active DB
    Per-line: Correct /
    Skip / Abort"]
    OPT5 -->|5| CLR{{"Confirm\nclear?"}}
    CLR -->|s| CLEARED(["✅ Header only kept"])
    CLR -->|N| OPT5
```

### Main Menu

```
╔══════════════════════════════════════════════════════╗
║                        GESTOR DE REPETIDORAS D-Star / FM / FM-N                          ║
║                                    LISTA DR ICOM                                   v3.5  ║
╚══════════════════════════════════════════════════════╝
    Arquivo  : Repeater_list.csv
    Registros: 142
    Grupos   : 27

1. Editar Repetidoras  (Listar / Editar / Excluir)
2. Adicionar Repetidora
3. Editar Grupos  (Renomear / Remover)
4. Consulta Geral  (Filtros Avançados)
5. Gerenciar Base de Dados
X. Sair do Sistema
```

---

### Option 1 — Edit Repeaters *(List / Edit / Delete)*

Displays all groups with their station count. Selecting a group opens a paginated list of its repeaters, sorted alphabetically by name.

```
╔══════════════════════════════════════════════════════╗
║                               RELAÇÃO DE GRUPOS CADASTRADOS                              ║
╚══════════════════════════════════════════════════════╝

 [01] - Acre                     ( 01 estações cadastradas )
 [02] - Alagoas                  ( 01 estações cadastradas )
 [04] - Santa Catarina           ( 18 estações cadastradas )
 ...

>> Digite o número do grupo (ou [X] Menu Principal):
```

**Inside a group — repeater list:**

```
╔══════════════════════════════════════════════════════╗
║                   LISTANDO AS REPETIDORAS DO GRUPO 4 — Santa Catarina                    ║
╚══════════════════════════════════════════════════════╝

 Nº  | GRUPO            | REPETIDORA       | INDICATIVO | MODO | FREQUENCIA
════════════════════════════════════════════════════════
 1   | Santa Catarina   | Blumenau         | PP5BLU B   | DV   | 439,950000
 2   | Santa Catarina   | Chapeco          | PP5CHP     | FM   | 147,150000
 ...

Página 1 de 2 (18 itens)
[P] Próx pg | [A] Pág anterior | [V] Voltar Grupos | [X] Menu Principal
>> Nº para detalhar (ou tecla indicada):
```

**Detail view of a selected repeater:**

```
╔══════════════════════════════════════════════════════╗
║                                 DETALHES DA REPETIDORA                                   ║
╚══════════════════════════════════════════════════════╝

 1.  Número do Grupo:              4
 2.  Nome do Grupo:                Santa Catarina
 3.  Nome da Repetidora:           Blumenau
 4.  Nome Adicional (Sub Name):    Sul
 5.  Indicativo:                   PP5BLU B
 6.  Indicativo do Gateway:        PP5BLU G
 7.  Frequência:                   439,950000
 8.  Duplex (DUP):                 DUP-
 9.  Offset Freq.:                 5,000000
 10. Modo de Operação:             DV
 11. Tipo de subtom:               OFF
 12. Frequência do subtom:         88,5Hz
 13. USE (From):                   YES
 14. Localização:                  Approximate
 15. Latitude:                     -26,919444
 16. Longitude:                    -49,065556
 17. UTC Offset:                   -3:00

[E] Editar | [D] Excluir | [V] Voltar | [X] Menu Principal
```

---

### Option 2 — Add Repeater

A guided sequential form that collects all 17 fields for a new entry. The group name is auto-filled if the group number already exists in the database. For FM/FM-N modes, a numbered CTCSS tone table is displayed inline for easy selection.

**Field entry flow:**

```
>> Group No (1-50) [Enter mantém: 4 | X p/ cancelar]: _
  >> Group Name associado automaticamente: Santa Catarina
>> Name [X p/ cancelar]: _
>> Sub Name [X p/ cancelar]: _
  Mode: 1) DV   2) FM   3) FM-N
>> Escolha (1-3) [X p/ cancelar]: _
  Dup: 1) OFF   2) DUP-   3) DUP+
>> Escolha (1-3) [X p/ cancelar]: _
>> Offset (ex: 5,000000) [X p/ cancelar]: _
>> Frequency (ex: 439,975000) [X p/ cancelar]: _
>> Repeater Call Sign [X p/ cancelar]: _
>> Gateway Call Sign [X p/ cancelar]: _       ← DV duplex only
  (CTCSS table shown for FM/FM-N)
  RPT1USE: 1) YES   2) NO
>> Escolha (1-2) [X p/ cancelar]: _
  Position: 1) None   2) Approximate   3) Exact
>> Escolha (1-3) [X p/ cancelar]: _
>> Latitude (ex: -26,149167) [X p/ cancelar]: _
>> Longitude (ex: -49,812167) [X p/ cancelar]: _
>> UTC Offset (ex: -3:00) [X p/ cancelar]: _
```

> The same form is reused for **editing** an existing repeater (reached from Option 1 → detail view → `[E]`), pre-populated with all current values.

---

### Option 3 — Edit Groups

```
╔══════════════════════════════════════════════════════╗
║                                    EDITAR GRUPOS                                         ║
╚══════════════════════════════════════════════════════╝

1. Renomear Grupo
2. Remover Grupo  (Move repetidoras vinculadas)
X. Voltar
```

- **Rename** — updates the group name across every repeater entry that belongs to that group.
- **Remove** — offers two options: move all repeaters in the group to another group (existing or new), or delete all of them permanently. Both paths create an automatic `.backup` file before modifying the database.

---

### Option 4 — Advanced Query

Allows filtering the entire database using up to **3 combined criteria**:

```
╔══════════════════════════════════════════════════════╗
║                                CONSULTA BASE DE DADOS                                    ║
╚══════════════════════════════════════════════════════╝

--- Filtro 1 ---
1) Grupo    2) Modo    3) RPT1USE    4) Call Sign    5) Frequência
Escolha o campo pelo número (ou [Enter] / X para cancelar):
```

| Filter | Match type | Description |
|---|---|---|
| **Grupo** | Exact | Select from a numbered list of available groups |
| **Modo** | Exact | Choose DV, FM, or FM-N |
| **RPT1USE** | Exact | Choose YES or NO |
| **Call Sign** | Partial | Text search against the Repeater Call Sign field |
| **Frequência** | Partial | Text search against the Frequency field |

Results are sorted by group name then repeater name, displayed in a paginated table. Selecting an entry number opens the full detail view, from which the entry can also be edited or deleted directly.

```
[P] Próx pg | [A] Pág anterior | [V] Nova Busca | [X] Menu Principal
```

---

### Option 5 — Manage Database

```
╔══════════════════════════════════════════════════════╗
║                                 GERENCIAR BASE DE DADOS                                  ║
╚══════════════════════════════════════════════════════╝
    Base atual selecionada: Repeater_list.csv
    Padrão do csv: Separador [ ; ], Decimal [ , ]

1. Selecionar Arquivo CSV Base
2. Importar CSV
3. Exportar DR_list.csv  (RptYYYYMMDD_XX.csv)
4. Validar Base de Dados
5. Limpar Base de Dados  (Mantém apenas cabeçalho)
X. Retornar
```

| Option | Description |
|---|---|
| **1 — Select CSV** | Switch the active database file. Lists all `.csv` files in the current directory. Can create a new empty base on the fly. |
| **2 — Import CSV** | Validate and import an external CSV. After validation, choose to **replace** the current database or **append** records to it. Group name conflicts between source and target are detected and resolved interactively. |
| **3 — Export** | Save a copy of the current database as `RptYYYYMMDD_XX.csv`, where `XX` is an auto-incrementing sequence number to avoid overwriting previous exports from the same day. |
| **4 — Validate** | Run the full validation engine on the active database. Errors are shown line by line with the options to **Correct** interactively, **Skip** the offending line, or **Abort** the process. Silent automatic fixes are also applied (decimal separators, tone suffixes, offset normalization). |
| **5 — Clear** | Erase all records, retaining only the CSV header row. Requires explicit confirmation. Also removes backup files older than 7 days. |

---

## Field Reference

### Accepted values per field

| Field | Accepted values |
|---|---|
| `Group No` | Integer 1–50 |
| `Group Name` | Printable characters, max 16 chars |
| `Name` | Printable characters, max 16 chars |
| `Sub Name` | Printable characters, max 8 chars |
| `Repeater Call Sign` | Max 8 chars; DV requires exactly 8, last char A–Z; must be empty for simplex (`Dup=OFF`) |
| `Gateway Call Sign` | Exactly 8 chars, last char `G`, first 7 chars must match RPT1 call sign; required for DV duplex only |
| `Frequency` | Format `NNN,NNNNNN`; must fall within 144–148 MHz (VHF) or 430–450 MHz (UHF) |
| `Dup` | `OFF`, `DUP-`, `DUP+` |
| `Offset` | Format `N,NNNNNN`; must be `0,000000` when `Dup=OFF` |
| `Mode` | `DV`, `FM`, `FM-N` |
| `TONE` | `OFF`, `TONE`, `TSQL` — FM/FM-N only; must be `OFF` for DV |
| `Repeater Tone` | Standard CTCSS value with `Hz` suffix (e.g. `88,5Hz`); must be `88,5Hz` for DV entries |
| `RPT1USE` | `YES`, `NO` |
| `Position` | `None`, `Approximate`, `Exact` |
| `Latitude` | Format `-?NN,NNNNNN` (e.g. `-27,597222`) |
| `Longitude` | Format `-?NNN,NNNNNN` (e.g. `-48,549167`) |
| `UTC Offset` | Format `±HH:MM` or `--:--` (e.g. `-3:00`) |

### Supported CTCSS tones

The following 50 standard ICOM tones are accepted (Hz, comma-decimal):

```
 67,0   69,3   71,9   74,4   77,0   79,7   82,5
 85,4   88,5   91,5   94,8   97,4  100,0  103,5
107,2  110,9  114,8  118,8  123,0  127,3  131,8
136,5  141,3  146,2  151,4  156,7  159,8  162,2
165,5  167,9  171,3  173,8  177,3  179,9  183,5
186,2  189,9  192,8  196,6  199,5  203,5  206,5
210,7  218,1  225,7  229,1  233,6  241,8  250,3  254,1
```

---

## Validation Rules

The validation engine (shared by both the manual add/edit form and the CSV import process) enforces the following rules:

- **Frequency range** — only VHF (144–148 MHz) and UHF (430–450 MHz) amateur bands are accepted.
- **DV callsign exclusivity** — a callsign used as a DV repeater cannot appear under any other mode in the database, and vice versa.
- **FM/FM-N band exclusivity** — the same callsign cannot serve as a repeater in the same band (VHF or UHF) more than once; dual-band operation with the same callsign requires separate entries on different bands.
- **Duplicate entries** — records sharing the same Group No + Name + Frequency combination are flagged as duplicates.
- **Mode-field consistency** — DV entries must have `TONE=OFF` and `Repeater Tone=88,5Hz`; FM/FM-N entries must have a valid non-empty CTCSS tone.
- **Simplex entries** — both `Repeater Call Sign` and `Gateway Call Sign` must be empty when `Dup=OFF`.
- **Automatic silent corrections** — the following are fixed without user interaction: period-based decimal separators (`.` → `,`), missing `Hz` suffix on Repeater Tone values, and non-zero Offset values on simplex entries.

---

## Usage Tips

- **Cancel anywhere** — press `X` at any prompt (including mid-form) to abort cleanly and return to the previous menu without saving partial data.
- **Accept defaults** — press `Enter` at any prompt to keep the value shown in orange brackets.
- **Automatic backup** — a `.backup` file is created automatically before any destructive operation (delete repeater, remove group, switch database).
- **Export before bulk changes** — use Option 5 → 3 to save a timestamped snapshot before making large edits.
- **Locale in spreadsheet apps** — when opening the CSV in LibreOffice Calc or Excel, configure the import dialog for `;` as the column delimiter and `,` as the decimal separator to avoid data corruption.
- **ICOM programming software** — import the exported CSV through the CS software (CS-51, CS-52, CS-5100, etc.) using the memory channel CSV import function.
- **The `;` character is forbidden** in all text fields and will be rejected with an error at entry time.
- **Single instance** — the script uses a PID lock file at `/tmp/dr_list_manager.lock`. If a previous session crashed and left a stale lock, the script detects and removes it automatically on next launch.

---

## Logging

All significant operations are appended to `dr_manager.log` in the script's working directory:

```
[2025-04-10 14:32:01] INICIO: Sistema iniciado com base: Repeater_list.csv
[2025-04-10 14:33:45] ADICAO: Nova repetidora 'Joinville' adicionada ao CSV
[2025-04-10 14:35:12] EDICAO: Repetidora 'Blumenau' atualizada no CSV (linha 23)
[2025-04-10 14:38:00] RENOMEAR_GRUPO: Grupo 4 renomeado de 'SC' para 'Santa Catarina'
[2025-04-10 14:40:00] EXPORT: Base exportada como Rpt20250410_01.csv
[2025-04-10 14:41:30] FIM: Sistema encerrado pelo usuário
```

Logged event types: `INICIO`, `FIM`, `ADICAO`, `EDICAO`, `EXCLUSAO`, `EXCLUSAO_GRUPO`, `RENOMEAR_GRUPO`, `MOVER_GRUPO`, `SELECAO_BASE`, `IMPORT`, `EXPORT`, `LIMPEZA`.

---

## Versioning

This project follows **semantic versioning**:

- **Decimal increments** (e.g. `3.4` → `3.5`) — bug fixes, minor UX improvements, or small feature additions.
- **Whole-number increments** (e.g. `3.x` → `4.0`) — significant new features or structural changes.

The current version (**3.5**) is displayed in the application header on every startup.

---

## License

This project is released under the **MIT License**. See [`LICENSE`](LICENSE) for details.

---

## Author

Developed by **Daniel — PP5KX**  
Amateur radio operator based in Mafra, Santa Catarina, Brazil  
🌐 [pp5kx.net](https://pp5kx.net) · [dvbr.net](https://dvbr.net)

Part of the [dvbr.net](https://dvbr.net) open infrastructure project for the Brazilian amateur radio community.

*73 de PP5KX*
