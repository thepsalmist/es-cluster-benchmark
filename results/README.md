# Results — local harness verification, 2026-08-31

Committed output from running all three challenges against a single-node and a
three-node cluster **on one laptop**. Its purpose is to show what the harness
produces and to document how the numbers behave, not to characterise any
cluster.

> **These are laptop numbers. Do not read them as cluster capacity.**
> All Elasticsearch nodes, and the Rally load generator, shared the same 8
> cores and the same NVMe disk. The 100,000-document corpus (24 MB) fits
> entirely in page cache. Both methodology rules in the top-level README are
> violated by construction: Rally is not on a separate machine, and the corpus
> does not exceed cluster RAM. A real acceptance run satisfies both.

## Environment

| | |
|---|---|
| Host | Intel Core i7-1185G7, 8 cores, 31 GB RAM, NVMe |
| Docker | 29.7.2 |
| Elasticsearch | 8.17.1, 1 GB heap per node |
| Rally | 2.13.0 (`elastic/rally` image) |
| Corpus | 100,000 synthetic log documents, 24 MB, seed 42 |
| Date | 2026-08-31 |

## Configurations

| Directory | Cluster | Index | Rally `--target-hosts` |
|---|---|---|---|
| `1node-1s0r/` | single node (`docker-compose.yml`) | 1 shard, 0 replicas | es01 |
| `3node-1s0r/` | 3 nodes (`docker-compose.cluster.yml`) | 1 shard, 0 replicas | es01 |
| `3node-3s1r/` | 3 nodes | 3 shards, 1 replica | es01 |
| `3node-3s1r-allhosts/` | 3 nodes | 3 shards, 1 replica | es01, es02, es03 |
| `3node-3s1r-allhosts/repeat-runs/` | 3 nodes | 3 shards, 1 replica | es01, es02, es03 |

Every run completed with a 0% error rate. Within each configuration the
challenges ran in order: `indexing-throughput`, `query-ladder`,
`mixed-workload`.

## What these runs actually establish

**Run order dominates everything else at this scale.** Three back-to-back
repeats of `indexing-throughput` on an unchanged configuration:

| Run | docs/s | p50 | p99 |
|---|---|---|---|
| cold (first on the configuration) | 11,578 | 93.7 ms | 280.8 ms |
| warm repeat 1 | 26,733 | 55.6 ms | 175.5 ms |
| warm repeat 2 | 18,997 | 70.0 ms | 196.0 ms |
| warm repeat 3 | 28,440 | 51.7 ms | 151.9 ms |

The cold run understates throughput by **2.1×** against the warm mean
(24,724 docs/s), and the three warm runs still spread **1.5×** among
themselves. This is why the top-level README says to repeat each challenge at
least three times.

**Therefore the cross-configuration tables below are not conclusive.** Each
configuration was measured once, in sequence on a machine that kept warming
up, so ordering is confounded with the setting under test. Differences smaller
than the ~1.5× warm-to-warm spread carry no signal. Isolating a topology or
shard-layout effect needs repeats per configuration, on hardware that is not
also running the load generator.

One consequence worth naming: `mixed-workload` reports *higher* bulk
throughput than `indexing-throughput` in every configuration (for example
20,662 vs 7,229 docs/s on the single node) despite doing the same bulk load
with concurrent searches added. It ran third in each sequence. That is a
warmup artefact, not evidence that concurrent searching speeds up indexing.

**The ladder finds no knee at this corpus size.** Filtered-search latency
*falls* as offered load rises — 14.0 ms p50 at 10 ops/s down to 7.4 ms
unthrottled on the single node. The working set is entirely cached and the
node never approaches saturation, so the throttled steps measure idle-time
overhead rather than load. A ladder that slopes the wrong way is the
signature of a corpus that is too small.

## Bulk indexing — first (cold) run of each configuration

| Configuration | docs/s | p50 | p99 |
|---|---|---|---|
| 1 node, 1s/0r | 7,229 | 81.4 ms | 785.6 ms |
| 3 node, 1s/0r | 6,616 | 89.3 ms | 780.9 ms |
| 3 node, 3s/1r | 4,481 | 153.7 ms | 1,036.2 ms |
| 3 node, 3s/1r, all hosts | 11,578 | 93.7 ms | 280.8 ms |

## Query ladder — ops/s · p50 · p99

| Step | 1n 1s/0r | 3n 1s/0r | 3n 3s/1r | 3n 3s/1r all hosts |
|---|---|---|---|---|
| filtered @10 ops/s | 9.9 · 14.0 · 16.8 | 9.8 · 16.0 · 19.1 | 9.8 · 15.7 · 21.8 | 10.0 · 14.0 · 39.5 |
| filtered @25 ops/s | 25.1 · 11.2 · 14.7 | 25.1 · 13.5 · 17.3 | 25.1 · 12.5 · 17.0 | 25.1 · 12.7 · 24.4 |
| filtered @50 ops/s | 50.1 · 9.7 · 12.6 | 50.1 · 11.1 · 16.1 | 50.1 · 10.3 · 14.3 | 50.2 · 12.0 · 25.6 |
| filtered unthrottled | 223.9 · 7.4 · 13.0 | 191.6 · 9.0 · 11.5 | 166.7 · 10.0 · 19.9 | 162.1 · 11.1 · 18.6 |
| match unthrottled | 166.4 · 7.9 · 12.7 | 130.9 · 10.0 · 13.8 | 92.1 · 12.3 · 34.9 | 161.8 · 10.2 · 27.2 |
| aggs unthrottled | 67.7 · 6.7 · 11.0 | 100.9 · 9.3 · 14.8 | 71.0 · 9.7 · 23.6 | 100.1 · 11.9 · 26.6 |

## Mixed workload

| Task | 1n 1s/0r | 3n 1s/0r | 3n 3s/1r | 3n 3s/1r all hosts |
|---|---|---|---|---|
| `mixed-bulk` (docs/s · p50 · p99) | 20,662 · 61.4 · 198.5 | 18,664 · 65.5 · 187.8 | 7,446 · 198.5 · 427.6 | 19,438 · 80.3 · 179.4 |
| `mixed-search-filtered` (ops/s · p50 · p99) | 20.3 · 13.7 · 74.8 | 20.2 · 16.1 · 36.1 | 20.1 · 60.8 · 260.3 | 20.2 · 17.8 · 80.4 |
| `mixed-search-aggs` (ops/s · p50 · p100) | 5.3 · 13.6 · 72.2 | 5.4 · 16.8 · 98.7 | 5.2 · 65.8 · 311.1 | 5.2 · 19.4 · 96.9 |

`mixed-search-aggs` runs too few samples at 5 ops/s for Rally to report a p99,
so the last column is the maximum.

## Reproducing

```bash
./scripts/generate_corpus.sh                      # 100,000 docs, deterministic

# single node
docker compose up -d
for c in indexing-throughput query-ladder mixed-workload; do
  CHALLENGE=$c ./run_benchmark.sh
done
docker compose down

# three nodes, 3 shards / 1 replica, load spread across all three
docker compose -f docker-compose.cluster.yml up -d
for c in indexing-throughput query-ladder mixed-workload; do
  CHALLENGE=$c \
  ES_HOST=http://host.docker.internal:9200,http://host.docker.internal:9201,http://host.docker.internal:9202 \
  CONFIRM_DESTRUCTIVE=yes \
  TRACK_PARAMS="number_of_shards:3,number_of_replicas:1" \
  ./run_benchmark.sh
done
```

Absolute numbers will not reproduce — they depend on the machine and on how
warm it is. The *shapes* should: a cold first run well below later ones, and a
ladder with no knee until the corpus outgrows RAM.
