# es-cluster-benchmark — Elasticsearch Cluster Acceptance Benchmark

A reproducible [Elasticsearch Rally](https://esrally.readthedocs.io/) harness
for answering one question about a **freshly provisioned cluster**: *is it good
enough to accept?* It measures the three things that matter before you put
real traffic on new hardware:

1. **Indexing throughput** — how fast the cluster ingests documents.
2. **Query latency under increasing load** — a stepped "ladder" that shows
   where response times start to degrade.
3. **Mixed workload** — query latency while the cluster is simultaneously
   indexing, which is what production actually looks like.

Everything runs through the official `elastic/rally` Docker image, pinned to
version 2.13.0, so there is no local Python or Rally installation. Clone,
generate the dataset, point it at your cluster.

> **⚠️ This benchmark is destructive by design.** The `indexing-throughput`
> and `mixed-workload` challenges **delete and recreate their target index**
> (default: `rally-acceptance`) on the cluster they run against. That is the
> point — an acceptance benchmark loads its own data. It only ever touches its
> own index, but never point it at a cluster holding data you care about
> without understanding this. Runs against anything other than the local
> Docker cluster require `CONFIRM_DESTRUCTIVE=yes`.

## Quick start (local self-test)

Verify the harness works on your machine before pointing it at a real cluster:

```bash
docker compose up -d               # start a single-node Elasticsearch 8.17.1
./scripts/generate_corpus.sh       # generate 100,000 synthetic documents
./run_benchmark.sh                 # run the default challenge (indexing-throughput)
CHALLENGE=query-ladder ./run_benchmark.sh
CHALLENGE=mixed-workload ./run_benchmark.sh
docker compose down                # tear down when finished
```

Each run writes a CSV report to `./benchmarks/` and full Rally logs to
`./logs/`.

## Multi-node self-test (still one host)

`docker-compose.cluster.yml` brings up three nodes — `es01`, `es02`, `es03` on
ports 9200, 9201 and 9202 — so you can exercise shard and replica layouts, and
spread the load across nodes, without a real cluster:

```bash
docker compose down                                  # free port 9200 first
docker compose -f docker-compose.cluster.yml up -d

CHALLENGE=indexing-throughput \
ES_HOST=http://host.docker.internal:9200,http://host.docker.internal:9201,http://host.docker.internal:9202 \
CONFIRM_DESTRUCTIVE=yes \
TRACK_PARAMS="number_of_shards:3,number_of_replicas:1" \
./run_benchmark.sh

docker compose -f docker-compose.cluster.yml down    # add -v to drop the data
```

Passing more than one host makes `ES_HOST` non-default, so the destructive
guard applies and `CONFIRM_DESTRUCTIVE=yes` is required.

The two compose files both bind port 9200 and run as separate compose
projects, so bring one down before starting the other.

> **A three-node cluster on one machine measures that machine.** The nodes
> share its cores, its disk and its page cache, and the load generator
> competes with all of them. Use this to check that a shard layout works and
> that the harness does what you expect — never to decide whether hardware is
> acceptable. `results/` records what this looks like in practice, including
> how much a cold first run understates throughput.

## Against a real (new) cluster

```bash
DOC_COUNT=5000000 ./scripts/generate_corpus.sh   # size the dataset realistically
ES_HOST=http://new-cluster:9200 CONFIRM_DESTRUCTIVE=yes ./run_benchmark.sh
ES_HOST=http://new-cluster:9200 CONFIRM_DESTRUCTIVE=yes CHALLENGE=query-ladder ./run_benchmark.sh
ES_HOST=http://new-cluster:9200 CONFIRM_DESTRUCTIVE=yes CHALLENGE=mixed-workload ./run_benchmark.sh
```

Two methodology rules for numbers you can trust:

- **Run Rally from a separate machine**, not on a cluster node — the load
  generator competes for CPU with Elasticsearch and corrupts the results.
- **Size the corpus so it exceeds the cluster's RAM.** If the whole dataset
  fits in memory you are benchmarking the filesystem cache, not the cluster.
  (The 100k default is only for verifying the harness itself.)

Repeat each challenge at least 3 times and compare runs before drawing
conclusions — single benchmark runs have natural variance.

### TLS and authentication

Most real clusters have both. Pass Rally's client options through
`CLIENT_OPTIONS`, and point `CA_CERT` at the certificate authority that signed
the cluster's HTTP certificate:

```bash
ES_HOST=https://new-cluster:9200 CONFIRM_DESTRUCTIVE=yes \
CA_CERT=./http_ca.crt \
CLIENT_OPTIONS="timeout:60,basic_auth_user:elastic,basic_auth_password:${ES_PASSWORD}" \
./run_benchmark.sh
```

API keys work the same way. Use the `encoded` field from the create-API-key
response:

```bash
CLIENT_OPTIONS="timeout:60,api_key:${ES_API_KEY}"
```

| Variable | Effect |
|---|---|
| `CLIENT_OPTIONS` | Reaches Rally as `--client-options`. Defaults to `timeout:60`; setting it replaces that default, so keep `timeout:60` unless you mean to change it |
| `CA_CERT` | Path to a PEM certificate authority. Mounted read-only into the container at `/rally/ca.crt` and appended to `CLIENT_OPTIONS` as `ca_certs`, so do not set `ca_certs` yourself |

On a cluster using Elasticsearch's auto-generated certificates, the HTTP CA
lives at `config/certs/http_ca.crt` on any node. Copy it out and point
`CA_CERT` at the copy.

Two things worth knowing. Omitting the CA fails fast and legibly, with
`CERTIFICATE_VERIFY_FAILED ... unable to get local issuer certificate`, rather
than hanging. And credentials passed this way are visible in the `docker run`
command line while the race is in flight, so read them from the environment
instead of typing them inline, and take that into account on a shared load
generator.

## The challenges

| Challenge | What it does | What to look at |
|---|---|---|
| `indexing-throughput` (default) | Deletes/recreates the index, bulk-loads the full corpus with parallel clients, then refreshes and force-merges | Mean throughput (docs/s) of `bulk-index`, error rate 0% |
| `query-ladder` | Runs a filtered search at fixed rates — 10, 25, 50 ops/s, then unthrottled — followed by unthrottled runs of each query shape. Needs a loaded index (run `indexing-throughput` first) | Service time p90/p99 at each step: the step where latency jumps is your saturation point; unthrottled throughput is your ceiling |
| `mixed-workload` | Reloads the index while throttled searches run concurrently; ends when the load completes | Search p99 under contention vs the quiet `query-ladder` numbers, and how much indexing throughput drops |

The three query shapes: `search-match` (full-text search), `search-filtered`
(full-text + keyword `terms` filter + date range — a typical app query), and
`search-aggs` (date histogram + terms + percentiles aggregations — a typical
dashboard query).

## Tuning parameters

Everything is overridable per run via `TRACK_PARAMS` (comma-separated
`key:value` pairs):

```bash
TRACK_PARAMS="bulk_clients:8,number_of_shards:3" ./run_benchmark.sh
```

| Parameter | Default | Meaning |
|---|---|---|
| `index_name` | `rally-acceptance` | Target index (deleted/recreated by the write challenges) |
| `number_of_shards` / `number_of_replicas` | 1 / 0 | Index layout — match what you plan to use in production |
| `bulk_size` | 1000 | Documents per bulk request |
| `bulk_clients` | 2 | Parallel indexing clients |
| `search_clients` | 2 | Parallel search clients |
| `ladder_warmup_iterations` / `ladder_iterations` | 20 / 100 | Per-client iterations at each ladder step |
| `mixed_search_throughput` / `mixed_aggs_throughput` | 20 / 5 | Search rates (ops/s) during the mixed workload |
| `cluster_health` | `green` | Health status to wait for after index creation (use `yellow` for single-node clusters with replicas) |
| `force_merge_segments` | 1 | Segment count to force-merge down to |
| `query_date_gte` / `query_date_lte` | 2026-01-15 / 2026-03-15 | Date range used by the queries (matches the generated corpus) |

`DOC_COUNT` (env var for `generate_corpus.sh`) controls corpus size; the
runner automatically tells Rally the actual document count.

## Defining acceptance criteria

A benchmark without pass/fail thresholds is just numbers. Before running,
write down what "good enough" means for *your* workload — for example:

| Check | Threshold (example — set your own) | From challenge |
|---|---|---|
| Sustained indexing throughput | ≥ 30,000 docs/s | `indexing-throughput` |
| Filtered search p99 at 50 ops/s | ≤ 100 ms | `query-ladder` |
| Filtered search p99 while indexing | ≤ 250 ms | `mixed-workload` |
| Error rate, all operations | 0% | all |

## Layout

```
docker-compose.yml         # Single-node ES 8.17.1 for local self-testing
docker-compose.cluster.yml # Three-node ES 8.17.1 on one host
scripts/generate_corpus.sh # Generates the synthetic corpus (JSON Lines)
tracks/cluster-acceptance/
  track.json               # Rally track: index, corpus, operations, challenges
  index-body.json          # Index settings + mappings (applied on create-index)
  operations/              # One JSON fragment per operation
  challenges/              # The three challenge schedules
  documents.json           # Generated corpus (not committed)
run_benchmark.sh           # Runs a challenge via the elastic/rally Docker image
results/                   # Committed CSVs from a local verification run
```

## Glossary

Rally and Elasticsearch benchmarking terms used in this repo:

- **Corpus** — the dataset a benchmark feeds into the cluster: a file with
  one JSON document per line (**JSON Lines** format). Ours is synthetic
  log-style data, generated deterministically so every clone benchmarks
  identical documents.
- **Track** — Rally's word for a benchmark definition: which index to use,
  which corpus to load, which operations exist, and which challenges can run.
- **Operation** — a single action Rally can perform: one search, one bulk
  request, creating an index.
- **Challenge** — a schedule of operations with iteration counts, client
  counts, and throughput targets. One track can offer several challenges;
  you pick one per run.
- **Race** — one execution of a challenge. Each race produces one report.
- **Client** — a simulated concurrent user. `clients: 2` means two
  connections issuing operations in parallel.
- **Warmup iterations** — executions that run but are excluded from the
  results, so caches and the JVM reach steady state before measuring.
- **Target throughput** — a fixed request rate (ops/s) Rally tries to hold.
  Used by the ladder to ask "what is latency *at* 25 ops/s?" instead of
  "how fast can we go?". Unthrottled tasks answer the second question.
- **Service time vs latency** — service time is how long the request itself
  took; latency additionally includes time spent waiting in the queue when
  the cluster can't keep up with the target rate. When latency climbs but
  service time doesn't, you've hit the saturation point.
- **Bulk** — Elasticsearch's batch-indexing API; `bulk_size` is how many
  documents go into each batch.
- **Refresh** — makes recently indexed documents visible to search.
- **Force-merge** — compacts an index's internal files (segments) after
  loading; done once after bulk-loading so query benchmarks run against a
  settled index rather than one mid-housekeeping.
- **`benchmark-only` pipeline** — Rally mode that assumes the cluster
  already exists and never installs or configures Elasticsearch itself. It
  does *not* prevent the track's own operations from creating/deleting
  indices — hence the destructive warning above.

## Requirements

- Docker (Rally runs entirely inside `elastic/rally:2.13.0`, pinned so the
  committed `results/` stay reproducible; `generate_corpus.sh` uses the system
  `python3`, standard library only)
- Network access from the machine running Rally to the target cluster
