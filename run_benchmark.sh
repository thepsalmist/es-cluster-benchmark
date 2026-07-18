#!/bin/bash
# Runs the cluster-acceptance track via the elastic/rally Docker image.
#
#   ./run_benchmark.sh                                  # indexing-throughput vs local ES
#   CHALLENGE=query-ladder ./run_benchmark.sh
#   CHALLENGE=mixed-workload ./run_benchmark.sh
#   ES_HOST=http://cluster:9200 CONFIRM_DESTRUCTIVE=yes ./run_benchmark.sh
#
# WARNING: the indexing-throughput and mixed-workload challenges DELETE and
# recreate the target index (default: rally-acceptance) on the target
# cluster. Running against anything other than the local compose cluster
# requires CONFIRM_DESTRUCTIVE=yes.
set -euo pipefail

LOCAL_PATH="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_ES_HOST="http://host.docker.internal:9200"
ES_HOST="${ES_HOST:-${DEFAULT_ES_HOST}}"
TRACK_NAME="cluster-acceptance"
CHALLENGE="${CHALLENGE:-indexing-throughput}"
RACE_ID="acceptance_${CHALLENGE}_$(date +%Y%m%d_%H%M%S)"
TRACK_PARAMS="${TRACK_PARAMS:-}"
CORPUS="${LOCAL_PATH}/tracks/${TRACK_NAME}/documents.json"

if [ ! -f "${CORPUS}" ]; then
  echo "Corpus not found: ${CORPUS}" >&2
  echo "Generate it first: ./scripts/generate_corpus.sh" >&2
  exit 1
fi

if [ "${ES_HOST}" != "${DEFAULT_ES_HOST}" ] && [ "${CONFIRM_DESTRUCTIVE:-}" != "yes" ]; then
  echo "Refusing to run against ${ES_HOST}." >&2
  echo "This benchmark DELETES and recreates its target index on the cluster." >&2
  echo "Re-run with CONFIRM_DESTRUCTIVE=yes if that is what you want." >&2
  exit 1
fi

CORPUS_DOCS="$(wc -l < "${CORPUS}")"
PARAMS="corpus_docs:${CORPUS_DOCS}"
if [ -n "${TRACK_PARAMS}" ]; then
  PARAMS="${PARAMS},${TRACK_PARAMS}"
fi

mkdir -p "${LOCAL_PATH}/benchmarks" "${LOCAL_PATH}/logs"

docker run --rm --name esrally-acceptance \
  --add-host=host.docker.internal:host-gateway \
  -v "${LOCAL_PATH}/tracks:/rally/.rally/tracks" \
  -v "${LOCAL_PATH}/benchmarks:/rally/.rally/benchmarks" \
  -v "${LOCAL_PATH}/logs:/rally/.rally/logs" \
  elastic/rally race \
  --track-path="/rally/.rally/tracks/${TRACK_NAME}" \
  --challenge="${CHALLENGE}" \
  --target-hosts="${ES_HOST}" \
  --pipeline=benchmark-only \
  --track-params="${PARAMS}" \
  --report-format=csv \
  --report-file="/rally/.rally/benchmarks/${RACE_ID}.csv" \
  --on-error=abort

echo "Benchmark complete! Results saved to:"
echo "${LOCAL_PATH}/benchmarks/${RACE_ID}.csv"
