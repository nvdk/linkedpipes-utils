# linkedpipes-utils

Cron helpers for the LinkedPipes ETL servers (QA `srvlodlppoc01`, PROD
`srvlodlppr01`), installed in `/opt/linkedpipes-utils/`. Need bash, curl
and jq.

| Script | Does |
|---|---|
| `run-pipeline.sh <pipeline IRI>` | starts an execution of a pipeline |
| `prune-executions.sh` | execution retention (replaces `remove-old-executions.sh` and `remove-failed-executions.sh`) |

## prune-executions.sh

The old cleanup deleted **every** finished execution once a week (and the
failed ones on another day), so there was no history of successful runs,
and between the two jobs the Nagios check (`check_lp_etl_failed.sh` in
LOD_linked_pipes) fell back to an older failure and raised a false
CRITICAL.

Per pipeline, `prune-executions.sh` keeps:

- the newest `--keep` executions (default 10), whatever their status;
- the newest successful and the newest unsuccessful execution, always;
- every queued/running execution and every execution without a start time;

and deletes the rest once older than `--finished-days` (default 30) for
finished runs, or `--failed-days` (default 90) for failed, cancelled,
dangling, unresponsive and invalid runs.

```
prune-executions.sh --dry-run              # list what would go, delete nothing
prune-executions.sh                        # defaults: keep 10, 30 d, 90 d
prune-executions.sh --keep 20 --finished-days 60
```

Deletes go through `DELETE /api/v1/executions?iri=<execution IRI>` (the
frontend has no DELETE on `/resources/executions/<id>`). Exit codes: 0 ok,
1 usage, 2 the list could not be fetched or parsed, 3 some deletes failed.
Output is one timestamped line per action, suitable for a cron log.

### Rollout

1. On QA: `prune-executions.sh --dry-run` and check the list.
2. Replace both QA cron lines with one daily run, logging to a file:

   ```
   15 3 * * *  root  /opt/linkedpipes-utils/prune-executions.sh >> /var/log/lp-prune.log 2>&1
   ```

3. After a week on QA, the same on PROD. Then delete
   `remove-old-executions.sh` and `remove-failed-executions.sh` from the
   server and from this repo.

### Testing without a server

`--input FILE` reads the execution list (the JSON-LD of
`GET /resources/executions`) from a file and implies `--dry-run`.
