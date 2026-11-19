#!/usr/bin/env bash
# prune-executions.sh — retention for LinkedPipes ETL executions.
#
# Replaces remove-old-executions.sh (deleted every finished execution) and
# remove-failed-executions.sh. Per pipeline it keeps:
#   - the newest KEEP executions, whatever their status;
#   - the newest successful and the newest unsuccessful execution, always
#     (so "when did this last work" stays answerable and the Nagios check
#     never falls back to an old failure);
# and deletes the rest once they are older than the retention for their
# status. Queued/running executions and executions without a parseable
# start time are never deleted.
#
# Usage: prune-executions.sh [options]
#   --url URL            LinkedPipes frontend (default http://localhost:8080)
#   --keep N             newest executions kept per pipeline (default 10)
#   --finished-days N    delete finished executions older than N days (30)
#   --failed-days N      delete failed/cancelled/... older than N days (90)
#   --token-file FILE    file holding the Basic auth token (base64 user:pass)
#                        for the nginx in front of LinkedPipes; or set
#                        LP_TOKEN. Not an argument: it would show in ps.
#   --netrc FILE         curl netrc file instead (default: none)
#   --dry-run            print what would be deleted, delete nothing
#   --input FILE         read the execution list from FILE instead of the
#                        server (testing; implies --dry-run)
#
# Exit: 0 ok, 1 usage/dependency error, 2 listing failed, 3 some deletes failed.
set -euo pipefail

URL="http://localhost:8080"
KEEP=10
FINISHED_DAYS=30
FAILED_DAYS=90
NETRC=""
TOKEN_FILE=""
DRY_RUN=0
INPUT=""

usage() { sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 1; }
is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="${2:?}"; shift 2 ;;
    --keep) KEEP="${2:?}"; shift 2 ;;
    --finished-days) FINISHED_DAYS="${2:?}"; shift 2 ;;
    --failed-days) FAILED_DAYS="${2:?}"; shift 2 ;;
    --netrc) NETRC="${2:?}"; shift 2 ;;
    --token-file) TOKEN_FILE="${2:?}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --input) INPUT="${2:?}"; DRY_RUN=1; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
done
for n in "$KEEP" "$FINISHED_DAYS" "$FAILED_DAYS"; do
  is_int "$n" || { echo "not a non-negative integer: $n" >&2; exit 1; }
done
[ "$KEEP" -ge 1 ] || { echo "--keep must be at least 1" >&2; exit 1; }
for cmd in curl jq; do
  command -v "$cmd" >/dev/null || { echo "$cmd is required" >&2; exit 1; }
done

URL="${URL%/}"
CURL=(curl -sS --fail --max-time 60)
[ -n "$NETRC" ] && CURL+=(--netrc-file "$NETRC")
TOKEN="${LP_TOKEN:-}"
if [ -n "$TOKEN_FILE" ]; then
  [ -r "$TOKEN_FILE" ] || { echo "cannot read $TOKEN_FILE" >&2; exit 1; }
  TOKEN=$(tr -d ' \r\n' < "$TOKEN_FILE")
fi
# The header goes to curl through a file descriptor, never through argv.
lp_curl() {
  if [ -n "$TOKEN" ]; then
    "${CURL[@]}" -H @<(printf 'Authorization: Basic %s\n' "$TOKEN") "$@"
  else
    "${CURL[@]}" "$@"
  fi
}

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

if [ -n "$INPUT" ]; then
  JSON=$(cat "$INPUT")
else
  JSON=$(lp_curl -H "Accept: application/ld+json" "$URL/resources/executions") \
    || { log "ERROR cannot list executions from $URL"; exit 2; }
fi

# One TSV line per execution to delete: iri, pipeline, status, start, age.
PLAN=$(printf '%s' "$JSON" | jq -r \
  --argjson keep "$KEEP" \
  --argjson fdays "$FINISHED_DAYS" \
  --argjson xdays "$FAILED_DAYS" '
  def NS: "http://etl.linkedpipes.com/ontology";
  def epoch:
    (try capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<tz>Z|[+-][0-9]{2}:?[0-9]{2})?$") catch null) as $m
    | if $m == null then null else
        (($m.d + "Z") | fromdateiso8601) as $local
        | (if ($m.tz // "Z") == "Z" then 0 else
             ($m.tz | sub(":"; "")) as $z
             | ($z[0:1] | if . == "-" then -1 else 1 end)
               * (($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60)
           end) as $off
        | $local - $off
      end;

  [ .[]["@graph"][]? ] as $nodes
  | ($nodes | map(select(.["@id"] == "http://etl.linkedpipes.com/metadata"))
     | .[0][NS + "/serverTime"][0]["@value"] // null) as $server_ms
  | (if $server_ms == null then now else ($server_ms | tonumber) / 1000 end) as $now
  | $nodes
  | map(select(.["@type"][]? == (NS + "/Execution"))
        | { iri: .["@id"],
            pipeline: (.[NS + "/pipeline"][0]["@id"] // "unknown"),
            status: ((.[NS + "/status"][0]["@id"] // "") | split("/") | last),
            start: (.[NS + "/execution/start"][0]["@value"] // "") }
        | .t = (.start | epoch)
        | .class = (if .status == "finished" then "ok"
                    elif (.status | IN("failed", "cancelled", "dangling",
                                       "unresponsive", "invalid")) then "bad"
                    else "live" end))
  | group_by(.pipeline)
  | map(
      sort_by(.t // 0) | reverse              # newest first; undated last
      | (map(select(.class == "ok"  and .t != null)) | .[0].iri) as $last_ok
      | (map(select(.class == "bad" and .t != null)) | .[0].iri) as $last_bad
      | to_entries
      | map(.value + { rank: .key })
      | map(select(
          .class != "live"                    # never queued/running
          and .t != null                      # never undated
          and .rank >= $keep                  # outside the newest N
          and .iri != $last_ok and .iri != $last_bad
          and ($now - .t) > (if .class == "ok" then $fdays else $xdays end) * 86400)
        | . + { age_days: ((($now - .t) / 86400) | floor) }))
  | add // []
  | .[]
  | [.iri, .pipeline, .status, .start, "\(.age_days)d"] | @tsv
') || { log "ERROR cannot parse the execution list"; exit 2; }

TOTAL=$(printf '%s' "$JSON" | jq '[.[]["@graph"][]? | select(.["@type"][]? == "http://etl.linkedpipes.com/ontology/Execution")] | length')
COUNT=0; [ -n "$PLAN" ] && COUNT=$(printf '%s\n' "$PLAN" | wc -l | tr -d ' ')
log "executions: $TOTAL; to delete: $COUNT (keep $KEEP per pipeline, finished > ${FINISHED_DAYS}d, failed > ${FAILED_DAYS}d)$([ "$DRY_RUN" -eq 1 ] && echo ' [dry run]')"
[ "$COUNT" -eq 0 ] && exit 0

ERRORS=0
while IFS=$'\t' read -r iri pipeline status start age; do
  if [ "$DRY_RUN" -eq 1 ]; then
    log "would delete $iri ($status, $start, $age, pipeline ${pipeline##*/})"
    continue
  fi
  # The frontend only routes execution deletes via /api/v1 (monitor
  # DELETE /executions/?iri=); a DELETE on the execution IRI itself 404s.
  if lp_curl -o /dev/null -X DELETE -G --data-urlencode "iri=$iri" "$URL/api/v1/executions"; then
    log "deleted $iri ($status, $age)"
  else
    log "ERROR delete failed: $iri"
    ERRORS=$((ERRORS + 1))
  fi
done <<< "$PLAN"

[ "$ERRORS" -eq 0 ] || { log "$ERRORS delete(s) failed"; exit 3; }
