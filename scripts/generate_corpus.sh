#!/bin/bash
# Generates the synthetic corpus (the dataset the benchmark indexes) as
# JSON Lines — one log-style document per line — into the track directory.
#
#   ./scripts/generate_corpus.sh                # 100,000 docs (default)
#   DOC_COUNT=1000000 ./scripts/generate_corpus.sh
#
# The corpus is deterministic (fixed random seed), so every clone of this
# repo benchmarks against identical data.
set -euo pipefail

LOCAL_PATH="$(cd "$(dirname "$0")/.." && pwd)"
DOC_COUNT="${DOC_COUNT:-100000}"
OUT="${LOCAL_PATH}/tracks/cluster-acceptance/documents.json"

python3 - "${OUT}" "${DOC_COUNT}" <<'PYEOF'
import json
import random
import sys
from datetime import datetime, timedelta

out, count = sys.argv[1], int(sys.argv[2])
random.seed(42)

services = [
    f"svc-{n}"
    for n in (
        "auth", "billing", "search", "ingest", "api", "frontend",
        "worker", "scheduler", "mailer", "reports", "payments", "inventory",
    )
]
levels = ["INFO"] * 70 + ["DEBUG"] * 15 + ["WARN"] * 10 + ["ERROR"] * 5
status_codes = [200] * 80 + [301, 404] * 8 + [500, 503] * 2
words = (
    "request completed timeout retry cache miss hit user session token "
    "queue flush index shard replica merge commit connection pool thread "
    "latency batch upload download parse render schedule worker job task event"
).split()

start = datetime(2026, 1, 1)
span_seconds = 90 * 24 * 3600

with open(out, "w") as f:
    for _ in range(count):
        ts = start + timedelta(seconds=random.randrange(span_seconds))
        doc = {
            "@timestamp": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "service": random.choice(services),
            "level": random.choice(levels),
            "host": f"host-{random.randrange(24):02d}",
            "status_code": random.choice(status_codes),
            "duration_ms": round(random.expovariate(1 / 45), 2),
            "message": " ".join(random.choices(words, k=random.randrange(8, 20))),
        }
        f.write(json.dumps(doc) + "\n")
PYEOF

echo "Wrote ${DOC_COUNT} documents to ${OUT} ($(du -h "${OUT}" | cut -f1))"
