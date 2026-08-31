# AGENTS.md

Reproducible Elasticsearch Rally harness for cluster acceptance benchmarking:
indexing throughput, a stepped query-latency ladder, and a mixed read/write
workload against a freshly provisioned cluster.

## Layout

- `docker-compose.yml` — single-node ES 8.17.1 for local self-testing
- `docker-compose.cluster.yml` — three-node ES 8.17.1 on one host (separate
  compose project; both files bind 9200, so only one can run at a time).
  Co-located nodes share the host's CPU, disk and page cache: use it for shard
  layout and harness checks, never to judge hardware
- `results/` — committed CSVs from a local verification run, with
  `results/README.md` documenting the configurations and their caveats
- `scripts/generate_corpus.sh` — generates the synthetic JSON Lines corpus
  into `tracks/cluster-acceptance/documents.json` (gitignored; deterministic
  via fixed random seed)
- `tracks/cluster-acceptance/` — the Rally track: committed `track.json`,
  `index-body.json` (settings + mappings), `operations/`, and `challenges/`;
  there is no build/render step — Rally's own Jinja templating
  (`{{ param | default(...) }}`) handles all parameters at race time.
  Note: index settings/mappings must live in the body file referenced by the
  track's `indices` declaration — a `body` inlined on the `create-index`
  operation is ignored when the index is declared in the track
- `run_benchmark.sh` — runs one challenge via the `elastic/rally` Docker
  image; computes `corpus_docs` from the corpus file and passes it as a
  track param

## Hard constraints

- Rally runs only via the official `elastic/rally` Docker image. Never
  install Rally or its Python dependencies locally.
- **This harness is destructive by design, but only to its own index**: the
  write challenges delete/recreate `{{ index_name }}` (default
  `rally-acceptance`). It must never touch any other index, template, or
  cluster setting on the target. Keep the `CONFIRM_DESTRUCTIVE=yes` guard in
  `run_benchmark.sh` for any non-default `ES_HOST`.
- The corpus generator must stay deterministic (fixed seed) and stdlib-only.
- `document-count` passed to Rally must always reflect the real corpus line
  count — the runner computes it with `wc -l`; never hardcode it.

## Verification

- Verify every change end-to-end against the local compose cluster: generate
  the corpus, run all three challenges, and confirm CSV reports land in
  `benchmarks/` with 0% error rates. Reasoning alone is not verification.
- Track fragments collected via `rally.collect` are not standalone JSON
  documents (they contain Jinja) — Rally successfully parsing the track is
  the authoritative validation.
- Shell scripts should pass `shellcheck`.
