# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project does

`install.sh` automates provisioning a local Joomla site: creates a MySQL/MariaDB database and user, downloads and extracts a Joomla release, runs the Joomla CLI installer, removes the `installation/` directory, and prints login details.

## Usage

```bash
cp env.sample .env        # then edit .env
./install.sh <site-slug> [joomla-version]
```

Version examples: `latest`, `5`, `5.2`, `5.2.1`

## Configuration (.env)

All runtime configuration lives in `.env` (gitignored). `env.sample` is the committed template. Key variables:

| Variable | Purpose                                                               |
|---|-----------------------------------------------------------------------|
| `SITES_PREFIX` | Parent directory for site installs (e.g. `/home/myuser/Sites`)        |
| `DOMAIN_SUFFIX` | Domain suffix (e.g. `example.dev` → site at `https://bar.example.dev`) |
| `DB_HOST`, `DB_PORT`, `DB_ROOT_USER`, `DB_ROOT_PASSWORD` | MySQL/MariaDB root credentials                                        |
| `ADMIN_FULLNAME`, `ADMIN_USERNAME`, `ADMIN_PASSWORD` | Joomla Super User details                                             |
| `CACHE_DIR` | Download cache directory (defaults to `~/.cache/joomla-install`)      |

## Architecture

Two files do all the work:

**`install.sh`** — orchestrates the full install in sequential steps:
1. Load `.env`, apply defaults, validate slug
2. Drop and recreate the database and DB user (named after the slug; password = slug)
3. Delete and recreate the site directory (`$SITES_PREFIX/$SLUG`)
4. Download `sources.json.gz` from `https://getpanopticon.com/checksums/sources.json.gz` (refreshed if >1 day old), pass it to `resolve_version.php`
5. Download the Joomla archive (90-day file-mtime cache in `CACHE_DIR`); prefers `.tar.zst` > `.tar.bz2` > `.tar.gz` > `.zip`
6. Extract; flatten if the archive wraps content in a single subdirectory
7. Run `installation/joomla.php install` (creates `configuration.php` and the Super User)
8. Delete `installation/` directory
9. Print summary

**`resolve_version.php`** — reads `sources.json`, filters `cms=joomla` entries, and resolves the best version+URL for a given specifier (`latest`, major, major.minor, or exact). Skips alpha/beta/RC for non-exact requests. Prefers the best archive format. Outputs `version|url` on stdout.

## Key conventions

- The site slug is reused as the database name, database username, and database password.
- `mysql` is required as a baseline dependency; `mariadb` is preferred over `mysql` when both are present.
- `installation/joomla.php` is the Joomla installer CLI (works before `configuration.php` exists). `cli/joomla.php` is the site CLI (requires `configuration.php`).
- The version index (`sources.json`) is cached for 1 day; Joomla archives are cached for 90 days.
