#!/usr/bin/env bash
#
# pull-toys.sh -- regenerate Data/TransmogToys.lua from Blizzard's own client data.
#
# WHERE THE DATA COMES FROM
#   Blizzard ships the game's internal database as .db2 files inside the CASC
#   archives inside your WoW install. wago.tools extracts those every build and
#   publishes them as plain CSV over HTTP -- no account, no API key, no scraping.
#   This script downloads five of those tables and joins them locally:
#
#     Toy              -> every item that is a toy
#     ItemXItemEffect  -> item  -> item-effect link
#     ItemEffect       -> item-effect -> spell
#     SpellEffect      -> spell -> aura type (56 = TRANSFORM, 61 = MOD_SCALE)
#     ItemSparse       -> item  -> display name
#
#   A toy is kept if any of its spells -- or a spell it triggers, up to two hops
#   -- applies aura 56 or 61.
#
# LIMITS (read these before trusting the output)
#   * ~30 well-known appearance toys apply their transform from a server-side
#     script effect (EffectAura = 0). No amount of DB2 joining will find them.
#     They live in tools/curated-extra.txt and are merged in by hand.
#   * The reverse: some aura-56 toys are novelty junk. tools/exclude.txt wins.
#   * wago.tools serves whatever the newest build is, which during a PTR cycle
#     can include unreleased items. Harmless here -- PlayerHasToy() just returns
#     false -- but do not treat a new ID as proof the toy is obtainable.
#
# USAGE
#   bash tools/pull-toys.sh              # use cached CSVs if present
#   bash tools/pull-toys.sh --refresh    # force re-download (do this after a patch)
#   bash tools/pull-toys.sh --dry-run    # report the diff, write nothing
#   bash tools/pull-toys.sh --clean      # delete the ~110 MB CSV cache
#
#   Needs: bash, curl, awk. Cache lives in $TMPDIR, not in the addon folder.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON="$(dirname "$HERE")"
OUT="$ADDON/Data/TransmogToys.lua"

# ~110 MB of CSVs. Kept OUT of the addon folder so it never ends up in a backup
# zip or gets scanned at game launch. Override with $PORTALHUB_DB2CACHE.
CACHE="${PORTALHUB_DB2CACHE:-${TMPDIR:-${TEMP:-/tmp}}/portalhub-db2}"

REFRESH=0
DRYRUN=0
for a in "$@"; do
  case "$a" in
    --refresh) REFRESH=1 ;;
    --dry-run) DRYRUN=1 ;;
    --clean)   rm -rf "$CACHE"; echo "removed $CACHE"; exit 0 ;;
    -h|--help) sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

mkdir -p "$CACHE"

fetch() {
  local table="$1"
  local dest="$CACHE/$table.csv"   # separate statement: $table isn't set yet on the line above
  if [[ $REFRESH -eq 1 || ! -s "$dest" ]]; then
    echo "  downloading $table ..." >&2
    curl -fsSL "https://wago.tools/db2/$table/csv" -o "$dest"
  else
    echo "  using cached $table ($(du -h "$dest" | cut -f1))" >&2
  fi
}

echo "==> fetching DB2 tables from wago.tools" >&2
for t in Toy ItemXItemEffect ItemEffect SpellEffect ItemSparse; do fetch "$t"; done

# Record which build these CSVs came from, so the generated file is traceable.
BUILD="$(curl -fsSI "https://wago.tools/db2/Toy/csv" \
         | sed -n 's/.*filename="Toy\.\([0-9.]*\)\.csv".*/\1/p' | head -1)"
BUILD="${BUILD:-unknown}"

# --- column lookup -----------------------------------------------------------
# Header names are read at runtime so a wago.tools column reorder doesn't
# silently produce garbage.
colidx() { head -1 "$CACHE/$1.csv" | tr -d '\r' | tr ',' '\n' | grep -nx "$2" | cut -d: -f1; }
colcount() { head -1 "$CACHE/$1.csv" | tr -d '\r' | tr ',' '\n' | wc -l; }

TOY_ITEMID=$(colidx Toy ItemID);            TOY_N=$(colcount Toy)
IXIE_EFFID=$(colidx ItemXItemEffect ItemEffectID)
IXIE_ITEMID=$(colidx ItemXItemEffect ItemID)
IE_ID=$(colidx ItemEffect ID);              IE_SPELL=$(colidx ItemEffect SpellID)
SE_AURA=$(colidx SpellEffect EffectAura);   SE_TRIG=$(colidx SpellEffect EffectTriggerSpell)
SE_SPELL=$(colidx SpellEffect SpellID)
IS_NAME=$(colidx ItemSparse Display_lang)

for v in TOY_ITEMID IXIE_EFFID IXIE_ITEMID IE_ID IE_SPELL SE_AURA SE_TRIG SE_SPELL IS_NAME; do
  [[ -n "${!v}" ]] || { echo "FATAL: could not locate column for $v -- wago.tools schema changed" >&2; exit 1; }
done
# Toy.csv's first column is a quoted string that contains commas, so index the
# ItemID column from the END of the row instead of the start.
TOY_FROM_END=$(( TOY_N - TOY_ITEMID ))

echo "==> joining (build $BUILD)" >&2

# --- 1. toys whose spell chain applies aura 56 (TRANSFORM) or 61 (MOD_SCALE) --
awk -F, \
    -v toyend="$TOY_FROM_END" -v ieid="$IE_ID" -v iesp="$IE_SPELL" \
    -v xeff="$IXIE_EFFID" -v xitem="$IXIE_ITEMID" \
    -v aura="$SE_AURA" -v trig="$SE_TRIG" -v spell="$SE_SPELL" '
FNR==1 { file++; next }
file==1 { n=split($0,a,","); toy[a[n-toyend]]=1; next }
file==2 { effspell[$ieid]=$iesp; next }
file==3 { if ($xitem in toy) { s=effspell[$xeff]; if (s>0) itemspell[$xitem]=itemspell[$xitem] " " s } next }
file==4 {
  if ($aura==56) a56[$spell]=1
  else if ($aura==61) a61[$spell]=1
  if ($trig>0) tr[$spell]=tr[$spell] " " $trig
  next
}
function marks(s) { if (s in a56) hit=1; if (s in a61) scale=1 }
END {
  for (it in itemspell) {
    m=split(itemspell[it],sp," "); hit=0; scale=0
    for (i=1;i<=m;i++) {
      marks(sp[i])
      k=split(tr[sp[i]],t2," ")                    # hop 1: triggered spell
      for (j=1;j<=k;j++) {
        marks(t2[j])
        k2=split(tr[t2[j]],t3," ")                 # hop 2: triggered-triggered
        for (q=1;q<=k2;q++) marks(t3[q])
      }
    }
    if (hit || scale) print it
  }
}' "$CACHE/Toy.csv" "$CACHE/ItemEffect.csv" "$CACHE/ItemXItemEffect.csv" "$CACHE/SpellEffect.csv" \
  | sort -u > "$CACHE/scan.ids"

# --- 2. merge curated additions, drop exclusions ------------------------------
# NB: every set here is sorted LEXICALLY, not numerically -- comm(1) compares
# strings, and a -n sorted file makes it emit "input is not in sorted order"
# and silently produce wrong results. Numeric ordering is applied at the end.
strip() { sed 's/#.*//' "$1" | tr -d ' \t\r' | grep -E '^[0-9]+$' || true; }
strip "$HERE/curated-extra.txt" | sort -u > "$CACHE/extra.ids"
strip "$HERE/exclude.txt"       | sort -u > "$CACHE/exclude.ids"
sort -u "$CACHE/scan.ids" "$CACHE/extra.ids" \
  | comm -23 - "$CACHE/exclude.ids" > "$CACHE/final.ids"

# --- 3. resolve names from ItemSparse (proper quoted-CSV parse) ---------------
awk -v namecol="$IS_NAME" '
function csvfield(line, want,   i,n,f,inq,c,out) {
  n=length(line); f=1; inq=0; out=""
  for (i=1;i<=n;i++) {
    c=substr(line,i,1)
    if (inq) {
      if (c=="\"") { if (substr(line,i+1,1)=="\"") { out=out "\""; i++ } else inq=0 }
      else out=out c
    }
    else if (c=="\"") inq=1
    else if (c==",") { if (f==want) return out; f++; out="" }
    else out=out c
  }
  return (f==want) ? out : ""
}
FNR==NR { want[$1]=1; next }
FNR==1  { next }
{
  id=csvfield($0,1)
  if (id in want) { nm=csvfield($0,namecol); if (nm!="") print id "\t" nm }
}' "$CACHE/final.ids" "$CACHE/ItemSparse.csv" | sort -t$'\t' -k1,1n -u > "$CACHE/final.tsv"

WANT=$(wc -l < "$CACHE/final.ids"); GOT=$(wc -l < "$CACHE/final.tsv")
if [[ "$WANT" -ne "$GOT" ]]; then
  echo "  note: $((WANT-GOT)) id(s) had no name in ItemSparse (unreleased?) and were dropped:" >&2
  comm -23 "$CACHE/final.ids" <(cut -f1 "$CACHE/final.tsv" | sort -u) | sed 's/^/    /' >&2
fi

# A name containing " or \ would break the generated Lua. Fail loudly instead.
if grep -q '["\\]' "$CACHE/final.tsv"; then
  echo "FATAL: an item name contains a quote or backslash; escape it before writing Lua" >&2
  grep -n '["\\]' "$CACHE/final.tsv" >&2
  exit 1
fi

# --- 4. report the diff against what is currently shipped ---------------------
if [[ -f "$OUT" ]]; then
  grep -o 'id = [0-9]*' "$OUT" | grep -o '[0-9]*' | sort -u > "$CACHE/old.ids"
  cut -f1 "$CACHE/final.tsv" | sort -u > "$CACHE/new.ids"
  echo "==> diff vs current $OUT" >&2
  comm -13 "$CACHE/old.ids" "$CACHE/new.ids" | while read -r id; do
    printf '  + %-8s %s\n' "$id" "$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$CACHE/final.tsv")" >&2
  done
  comm -23 "$CACHE/old.ids" "$CACHE/new.ids" | sed 's/^/  - /' >&2
fi

if [[ $DRYRUN -eq 1 ]]; then
  echo "==> --dry-run: $OUT not modified ($GOT entries would be written)" >&2
  exit 0
fi

# --- 5. emit the Lua ---------------------------------------------------------
[[ -f "$OUT" ]] && cp "$OUT" "$OUT.bak"
{
  printf 'local _, PH = ...\n\n'
  printf -- '-- Appearance-changing toys. GENERATED by tools/pull-toys.sh -- do not hand-edit.\n'
  printf -- '-- Source: wago.tools DB2 export, build %s.\n' "$BUILD"
  printf -- '-- Add or remove entries via tools/curated-extra.txt and tools/exclude.txt,\n'
  printf -- '-- then re-run: bash tools/pull-toys.sh --refresh\n\n'
  printf 'PH.TransmogToys = {\n'
  awk -F'\t' '{printf "    { id = %s, name = \"%s\" },\n", $1, $2}' "$CACHE/final.tsv"
  printf '}\n'
} > "$OUT"

echo "==> wrote $OUT ($GOT entries, build $BUILD); previous copy at $OUT.bak" >&2
