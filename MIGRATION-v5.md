# Upgrading the S3DF CryoSPARC service from v4.7 to v5

CryoSPARC v5 revalidates and rewrites the database on first use, and the only
upgrade path Structura documents is `cryosparcm update`, which rewrites
`/app/cryosparc_master` in place. In this deployment that directory lives inside
a read-only Apptainer image, so `cryosparcm update` cannot be used. The guide is
also explicit that pointing a fresh v5 install at a v4 database is unsafe:

> Do not attempt installing a new v5 instance with an existing CryoSPARC
> database that was previously in-use by v4.

The database-only upgrade is `cryosparcm upgrade`, which Structura described for
container sites in [discuss #24679](https://discuss.cryosparc.com/t/upgrade-v4-to-v5/24679).


## How the migration works

Each user's database is **copied** into a new v5 data directory and the copy is
upgraded. The v4 directory is never written to, so it is simultaneously the
backup and the rollback path.

| | v4 | v5 |
|---|---|---|
| Data directory | `$CRYOSPARC_DATADIR` (e.g. `$HOME/cryosparc`) | `${CRYOSPARC_DATADIR}-v5` |
| Database | `.../cryosparc_database` | `...-v5/cryosparc_database` |

Extra disk cost is one copy of the database, alongside the original. Bulk data
lives in project directories, not the database, so this is normally modest — but
`cryosparc_db_migrate.sh` still refuses to start if free space is below
`db_size * 1.5` (2 GB floor), because many users have moved their data directory
into a quota-managed project folder.

Migration runs automatically the first time a user starts a v5 session. The
script is idempotent via
`${CRYOSPARC_DATADIR}-v5/.cryosparc_v5_migration` (`seeded` / `done` /
`failed`), logs to `run/v5_migration_<timestamp>.log`, refuses to copy a
database whose `mongod.lock` is non-empty (copying live WiredTiger files yields
a corrupt copy), and writes progress to `~/Desktop/CRYOSPARC-MIGRATION.txt` so a
user watching an empty desktop knows what is happening. On failure it refuses to
start CryoSPARC and points the user at a v4.7 session.

Open OnDemand's `form.js` switches `CRYOSPARC_DATADIR` to the `-v5` sibling and
pre-fills `CRYOSPARC_MIGRATE_FROM` with the original path whenever a 5.x image is
selected, so users who relocated their data directory are handled correctly.

### Ports — this one blocks the build

**v5 refuses any base port inside the Linux ephemeral range (32768-60999).** The
installer fails outright:

```
Error: Port range 39000 to 39010 overlaps with ephemeral port range (32768-60999)
This may cause conflicts with automatically assigned ports.
Please choose a port outside this range.
```

This is the "port conflict checks added at installation and startup" line in the
v5.0.0 release notes, and it is why v5's default base port moved from 39000 to
61000 — and why the
[forum report](https://discuss.cryosparc.com/t/database-fails-to-start-after-upgrade-from-v4-7-1-to-v5-0-4-no-such-file-or-directory-mongo/24768)
was fixed by `cryosparcm changeport 61000`.

### The idle culler

`cryosparcm job status` did not just get renamed — its output changed shape. v4
printed a `Jobs running:` header with the count on the **next** line. v5 prints
one line per status with the count on the **same** line, for five statuses:

```
Jobs queued: 0
Jobs launched: 0
Jobs started: 0
Jobs running: 2
Jobs waiting: 0
```

The v4 culler read the line *after* `Jobs running:`, which in v5 is
`Jobs waiting: 0`. That fails the integer comparison, which bash treats as
false, which the culler reads as "idle" — **killing sessions with running jobs
after two hours.**

It now sums the `launched`, `started`, `running` and `waiting` counts, and if it
cannot parse the output at all it assumes the session is busy and logs a warning
rather than culling. Failing safe matters more here than precision.

`queued` is deliberately excluded. A job whose ancestor failed stays queued
indefinitely without ever running, so counting it as activity would keep the
session and its GPUs alive forever for work that will never start. "Unparseable"
is decided from the unfiltered output, so a session whose only jobs are queued
reports zero activity and is correctly cullable, rather than being mistaken for
a session we could not read.

One caveat if cluster lanes are ever turned on here
(`CRYOSPACE_ADD_JOB_LANES=1`): a job queued to a Slurm lane and pending for
longer than the idle timeout would no longer protect its session, and culling
the master would orphan it. With only the local worker registered — the default
for this app — a job that is queued while nothing is running is stuck, so
excluding queued is correct.

### Scheduler target enumeration

v5 has no machine-readable target listing, but `cryosparcm cli <python expr>`
survives and prints JSON. Targets live in a single document —
`db.sched_config{name:"targets"}.value[]` — each with a `name` and a type of
`"node"` or `"cluster"`, which determines whether it is removed with
`cryosparcm cluster remove NAME` or `cryosparcm worker disconnect --worker NAME`.
`cryosparc.sh` reads that directly rather than scraping the `cryosparcm
resources` table, and falls back to removing just our own registered lane names
if the query fails.

`cryosparc-server.sh` (the non-desktop Kubernetes path) still uses v4 commands
and has **not** been updated. Either port it or retire it before it is used
against a v5 image.

## The startup sequence is mandatory (and explains the forum's auth failure)

Running the documented container recipe — `start database`, `start cache`,
`upgrade -y` — **fails** against a real v4.6.2 database:

```
SASL SCRAM-SHA-1 authentication failed for cryosparc_admin on admin
  ; UserNotFound: Could not find user cryosparc_admin@admin
OperationFailure: Authentication failed.
```

v5 runs MongoDB with authentication on (`db_enable_auth: true`) and expects
`cryosparc_admin` / `cryosparc_user` accounts whose credentials derive from the
license. A v4.6.2 database has no Mongo users at all, so nothing can connect.

This is almost certainly the failure
[reported on the forum](https://discuss.cryosparc.com/t/upgrade-v4-to-v5/24679)
and attributed there to "a database created with a different license key than
the one used to issue `cryosparcm upgrade`". The license is a red herring: the
accounts do not exist yet in *any* v4 database.

The fix is to follow what `bin/cryosparcm` does for the database stage of its own
update, rather than the abbreviated forum recipe:

```
cryosparcm start --no-startup --no-app    # <- runs `database configure`, which
                                          #    creates the MongoDB auth users
cryosparcm upgrade -y
cryosparcm stop
```

The dry-run startup is the step that matters and the one the forum recipe omits.
With it, the migration completes. `cryosparcm database fixport` is kept only as a
fallback: a v4 database carries a replica-set configuration pinned to its old
port, and every migration here changes the port (v4 instances sat around 39100;
v5 cannot go below 61000). In testing `start` handled the reconfiguration itself,
but the fallback costs nothing.

## Two more traps found by building

**`cryosparcm` cannot run at all without a writable `run/` directory.** It
attaches a rotating log handler to `run/cli.log` at import time, before it parses
arguments, so with an unwritable `run/` even `cryosparcm --help` dies with a
`PermissionError` traceback. Anything that looks like a missing command or a
broken install should be checked against this first; the migration script now
asserts it up front with a clear message.

That interacted badly with `entrypoint.bash`: v5 ships `cryosparc_master/run` as
a real, root-owned directory (the installer leaves a `cli.log` in it), so
`ln -sf "$datadir/run" .../run` placed the link *inside* it as `run/run` and left
the root-owned directory in place — breaking every `cryosparcm` call. The
entrypoint now removes the directory first. Open OnDemand bind-mounts over this
path so production was unaffected, but the docker/Kubernetes path was broken.

**Exec bits.** `COPY` preserves the source file mode, and a locally built 4.6.2
image had `/cryosparc.sh` and `/entrypoint.bash` non-executable — which makes
Open OnDemand's `singularity exec ... /cryosparc.sh` fail with "command not
found". The Dockerfile now sets the bit explicitly rather than trusting the
checkout's modes.

## `cryosparcm upgrade` can succeed while doing nothing

`upgrade` exits 0 without touching anything if the database has no
`running_version` recorded ("This is a new installation and database upgrade is
not required") or already reports v5. Since the migration only runs having just
copied a v4 database in, either outcome means the documents were **not**
migrated — and letting v5 loose on un-upgraded v4 data is the exact scenario the
guide warns about. The script now greps for those messages and fails closed
instead of reporting success.

## Verified by building v5.0.7

The image builds: `slaclab/cryosparc-desktop:5.0.7-0`, 21.6 GB (the 4.6.2 image
is 27.5 GB). Confirmed inside the built image:

- `cryosparcm upgrade --help` runs and offers exactly `-y/--yes`,
  `--skip-validation`, `--validate-only` — the migration's central assumption,
  confirmed end to end rather than inferred from source.
- `cryosparcm database check` / `fixport` / `backup` / `restore` all exist.
- Python envs at `.pixi/envs/{master,worker}`; `deps/anaconda` genuinely absent,
  so the v4 paths would have failed.
- `compute/blobio/*.so` compiled for both master and worker.
- The idle-culler stanza is appended to `config/supervisord.conf`.
- `/usr/local/bin/MotionCor2` resolves to the locally staged
  `MotionCor2_1.4.5_Cuda100-10-22-2021`.
- Topaz resolves and runs from `/opt/topaz` (`topaz --help` works), so the
  micromamba re-homing is sound.
- `config.sh` carries `CRYOSPARC_FORCE_USER=true`, `CRYOSPARC_BASE_PORT=61000`,
  `CRYOSPARC_LICENSE_ID=TBD`.
- MongoDB still bundled at `deps_bundle/external/mongodb/bin/mongod`; v5 settings
  record `mongo_fcv: "3.6"`.

End to end, against a v4.6.2 database produced by the 4.6.2 image: the lock
guard, free-space check, copy, service startup, auth-user creation,
`cryosparcm upgrade`, `cryosparcm database check` and the no-op guard all behave
correctly.

## Still unverified

1. **The document upgrade itself.** The local test database turned out to be
   empty — v4 initialised MongoDB but never populated the `meteor` database, so
   the upgrade correctly declined it and the no-op guard fired. Everything around
   the upgrade is proven; the actual migration of users, projects, workspaces,
   jobs, sessions and exposures is not. **This needs a real user database**, and
   it is the one remaining thing that must be tested before any user sees v5.
2. **Runtime startup under Apptainer specifically** — the tests above ran under
   Docker via `entrypoint.bash`; production uses `singularity exec /cryosparc.sh`
   with bind mounts, a read-only image, and host identity.
3. **`cryosparcm database check` exit semantics** — whether non-zero means real
   corruption or merely warnings. Currently treated as a warning that still lets
   the user in, since the v4 original is intact either way.
4. **The scheduler-target purge** against a database that actually has stale
   targets in `db.sched_config`.
5. **NVIDIA driver on the cluster** (below).

## Cluster prerequisites

| Requirement | Status |
|---|---|
| Source instance on v4.0+ | 4.6.2 / 4.7.0 — OK |
| GLIBC >= 2.28 | base image Ubuntu 22.04 (2.35) — OK |
| GPU compute capability 5.0–12.0 | Turing 7.5 / Ampere 8.0 / Ada 8.9 — OK |
| **NVIDIA driver >= 570.26** | **verify on `turing`, `ampere`, `ada`** |

The driver is the one hard blocker. CUDA 12.9 on S3DF implies R575, which would
satisfy it, but confirm per partition before announcing anything:

```
srun -p ada --gpus=1 nvidia-smi --query-gpu=driver_version --format=csv,noheader
```

Target **v5.0.7**, not v5.0.0: v5.0.1 and v5.0.3 fixed database-upgrade
validation bugs, including projects being wrongly detached during upgrade,
integer overflow on large parameters, and empty project titles.

## Test plan

Build, push and convert as usual (`make all`), then work through this before
exposing the v5 option to users. Use your own account and at least two
volunteers.

1. **Fresh instance.** Blank `CRYOSPARC_MIGRATE_FROM`. Confirm login, lanes,
   local worker, and a short job (import movies + 2D classification).
2. **Small 4.7 database.** Confirm the copy happens, upgrade completes, all
   projects are still attached, and job history is intact.
3. **Large / old database** (ideally a 4.6.2 one with thousands of jobs). Time
   it. This sets the expectation you publish to users.
4. **Database with Live sessions.** v4 Live configuration profiles are not
   retained across a downgrade; confirm what survives the upgrade.
5. **Quota failure.** Point the v5 datadir at a nearly-full location and confirm
   it aborts cleanly with a readable message and changes nothing.
6. **Concurrent v4 session.** Start a v4 session, then a v5 session, and confirm
   the `mongod.lock` guard refuses to copy a live database.
7. **Rollback.** After a successful migration, start a v4.7 session against the
   original datadir and confirm it still works.

On (7), note the one thing the copy does **not** protect: project directories are
shared between v4 and v5 and v5 will write to them. The database rollback is
clean; project directories are best-effort. Test this with a real project before
telling users rollback is safe.

## Rollout

1. Verify the driver prerequisite and the build checklist.
2. File the support ticket with Structura about `cryosparcm upgrade`.
3. Publish v5.0.7 in the form with v4.7.0 kept in place. The form already lists
   v5 first and keeps both v4 tags.
4. Migrate volunteers first, then announce. Tell users the first v5 session is
   slow, that their v4 data is untouched, and that they can fall back to v4.7.
5. Leave both versions available for at least one full processing cycle.
6. Once v5 is established, retire the v4 tags from the form and tell users they
   can delete the old `cryosparc` directory to reclaim space. Do not delete
   anything on their behalf.

## Notes

- v5 writes `cryosparc_instance_config_*.tar` into `cryosparc_master/run` every
  60 minutes, and `run` is bind-mounted into the user's data directory — so these
  recovery files persist per user at no cost. `cryosparcm recover -f <file>`
  rebuilds an instance from one if a database is lost. Worth mentioning in user
  documentation.
- Downgrading below v4.4 is impossible once a database has seen v5. Irrelevant
  here as long as the copy-based scheme holds, but it is why the original is
  never written to.
- `cryosparcm database compact`, `export`/`import` and `export-instance-config`
  are new in v5 and may be useful for support work.
