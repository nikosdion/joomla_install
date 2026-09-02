# Joomla Local Install

A Bash script to provision a local Joomla site in one command. It sets up the database, downloads Joomla, runs the CLI installer, and prints your login URL and credentials.

## Requirements

- Bash
- PHP (in `PATH` as `php`)
- `mysql` or `mariadb` client (`mariadb` is preferred when both are present)
- `curl`, `gunzip`
- `zstd` (optional, for `.tar.zst` archives — recommended for speed)
- `unzip` (optional, for `.zip` archives)
- A running MySQL or MariaDB server accessible with root credentials

## Setup

```bash
cp env.sample .env
```

Edit `.env` to match your local environment:

| Variable | Description | Default |
|---|---|---|
| `SITES_PREFIX` | Parent directory where sites are created | `~/Sites` |
| `DOMAIN_SUFFIX` | Domain suffix for site URLs | `local` |
| `DB_HOST` | Database host | `127.0.0.1` |
| `DB_PORT` | Database port | `3306` |
| `DB_ROOT_USER` | MySQL/MariaDB root username | `root` |
| `DB_ROOT_PASSWORD` | MySQL/MariaDB root password | _(empty)_ |
| `ADMIN_FULLNAME` | Full name of the Joomla Super User | `Administrator` |
| `ADMIN_USERNAME` | Username of the Joomla Super User | `admin` |
| `ADMIN_PASSWORD` | Password of the Joomla Super User | `admin1234` |
| `CACHE_DIR` | Directory for cached downloads | `~/.cache/joomla-install` |

## Usage

```bash
./install.sh <site-slug> [joomla-version]
```

`site-slug` is used as the site directory name, database name, database username, and database password. It must start with a letter or digit and contain only letters, digits, and hyphens.

`joomla-version` can be the literal "latest" for the latest stable release (default), a major version, a version family (major.minor), or a full version (major.minor.patch). Examples:

| Value | Meaning |
|---|---|
| `latest` | Latest stable release _(default)_ |
| `5` | Latest stable Joomla 5.x |
| `5.2` | Latest stable Joomla 5.2.x |
| `5.2.1` | Exact version 5.2.1 |

### Examples

```bash
# Install the latest Joomla at https://mysite.example.dev
./install.sh mysite

# Install the latest Joomla 5.x
./install.sh mysite 5

# Install an exact version
./install.sh mysite 5.2.1
```

After a successful installation, the script prints something along the lines of:

```
Joomla 5.2.1 installed on https://mysite.example.dev

Your Super User login information is as follows.

 URL      : https://mysite.example.dev/administrator
 Username : admin
 Password : admin1234
```

## What the script does

1. Drops and recreates the MySQL/MariaDB database and user for the slug.
2. Deletes and recreates the site directory.
3. Fetches the Joomla version index from `https://getpanopticon.com/checksums/sources.json.gz` (cached for 1 day) and resolves the best matching download URL.
4. Downloads the Joomla archive (cached for 90 days in `CACHE_DIR`).
5. Extracts the archive into the site directory.
6. Runs `installation/joomla.php install` to install Joomla and create the Super User.
7. Removes the `installation/` directory.

## Re-installing a site

Running the script again with the same slug drops the existing database and deletes the site directory before starting fresh.

## License

This project is distributed under the [MIT License](LICENSE).
