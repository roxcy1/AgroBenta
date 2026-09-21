# Docker-First Development Template — Laravel + React + MySQL + Redis

A reusable Docker development environment for **Laravel 13** (backend) and **React + Vite** (frontend) with MySQL, Redis, Nginx, and optional Laravel Reverb (WebSockets).

Nothing except **Docker Desktop** and **Git** needs to be installed on your machine. PHP, Composer, MySQL, Redis, and Node all run inside containers.

---

## Prerequisites

Install these on your machine before starting:

| Software | Why you need it |
|----------|-----------------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | Runs all services in containers |
| [Git](https://git-scm.com/) | Clones this template |

No PHP, Composer, Node, or MySQL installation required on your host machine.

---
**Optional but recommended:** change the folder name when you copy this template — it becomes your Docker project name automatically. 

## Quick Start

```bash
# 1. Copy or clone this template into a new folder named after your project
#    (the folder name becomes your Docker project name automatically)
cp -r path/to/template ./MyNewProject
cd MyNewProject

# 2. Copy the environment file and edit it with your own values
cp .env.example .env
#    Open .env and CHANGE every CHANGE_THIS_* value (see "Configuration" below)

# 3. Build the Docker images
docker compose build

# 4. Start all containers in the background
docker compose up -d --build

# 5. View the logs to confirm everything started correctly
docker compose logs -f
#    Press Ctrl+C to stop watching logs (containers keep running)
```

### Scaffold Laravel and React (first time only)

The `backend/` and `frontend/` directories start empty. Scaffold them once:

```bash
# Remove placeholder files so Composer and Vite can scaffold into these folders
rm backend/.gitkeep
rm frontend/.gitkeep

# Scaffold Laravel
docker compose run --rm php composer create-project laravel/laravel .
docker compose run --rm php php artisan install:api --no-interaction
docker compose run --rm php php artisan key:generate

# Scaffold React + Vite
docker compose run --rm node npm create vite@latest . -- --template react
docker compose run --rm node npm install
```

### Configure Laravel's database connection

After scaffolding, edit `backend/.env` so it matches your root `.env`:

```
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=CHANGE_THIS_DATABASE_NAME
DB_USERNAME=CHANGE_THIS_DATABASE_USER
DB_PASSWORD=CHANGE_THIS_DATABASE_PASSWORD

REDIS_HOST=redis
REDIS_PORT=6379
```

Then run migrations and restart:

```bash
docker compose exec php php artisan migrate
docker compose restart php nginx
```

---

## Configuration — Things You MUST Change

**Unique configuration values you need to customize: 4**

| # | File | Change This | Purpose |
|---|------|-------------|---------|
| 1 | `.env` | `CHANGE_THIS_DATABASE_NAME` | MySQL database name |
| 2 | `.env` | `CHANGE_THIS_DATABASE_USER` | MySQL username |
| 3 | `.env` | `CHANGE_THIS_DATABASE_PASSWORD` | MySQL password |
| 4 | `.env` | `CHANGE_THIS_ROOT_PASSWORD` | MySQL root password |

After changing `.env`, also update `backend/.env` with matching values for Laravel's database configuration (see Quick Start above).

**Optional but recommended:** change the folder name when you copy this template — it becomes your Docker project name automatically.

---

## URLs

| Service | URL |
|---------|-----|
| Laravel (via Nginx) | http://localhost:8001 |
| React + Vite dev server | http://localhost:5174 |
| phpMyAdmin | http://localhost:8082 |
| MySQL (external client) | localhost:33070 |
| Redis (external client) | localhost:6379 |

> Laravel Reverb is **disabled** in this setup until real-time (WebSocket) features are required.

---

## Docker Commands

### Build images only

```bash
docker compose build
```

Builds or rebuilds the Docker images. Does **not** start containers.

### Start containers (build if needed)

```bash
docker compose up -d --build
```

Builds images if necessary, then starts all containers in the background (`-d`). This is the main command for day-to-day use.

### View logs

```bash
docker compose logs -f
```

Follows the combined log output from all running containers. Press `Ctrl+C` to stop watching (containers keep running).

### Stop containers

```bash
docker compose down
```

Stops and removes all containers and the Compose network. Data in volumes (`mysql_data`, `redis_data`) is preserved.

### Stop containers and wipe database data

```bash
docker compose down -v
```

Same as above, but also deletes the MySQL and Redis volumes. Use this for a fresh start.

---

## Daily Workflow — Running Commands

You never install PHP/Composer/Node on Windows. Instead, run commands *through* the containers:

```bash
# Laravel Artisan
docker compose exec php php artisan migrate
docker compose exec php php artisan make:model Listing -mcr

# Composer
docker compose exec php composer require laravel/reverb

# npm (from the frontend/ folder, run through the node container)
docker compose exec node npm install axios
docker compose exec node npm run build
```

Tip: create shell aliases in your PowerShell profile or `.bashrc` so you can type shorter commands like `art migrate` instead of `docker compose exec php php artisan migrate`.

---

## Services Explained

### `php` — required
Runs Laravel via PHP-FPM. Built from a custom Dockerfile with the PHP extensions Laravel needs (`pdo_mysql`, `redis`, `gd`, `zip`, `intl`, etc.) and Composer bundled in. Not exposed to your browser directly — Nginx talks to it over the internal network on port 9000.

### `nginx` — required
The web-facing entrypoint. Serves static files itself and forwards anything ending in `.php` to the `php` service. Exposed on `localhost:8001`.

### `mysql` — required
Your database. Data persists in the `mysql_data` volume, so `docker compose down` (without `-v`) keeps your data across restarts.

### `phpmyadmin` — optional, but recommended for teams
A GUI for MySQL so teammates who aren't comfortable with a SQL CLI can still inspect tables. Removable with no impact on the rest of the stack.

### `redis` — recommended
Backs Laravel's cache, session, and queue drivers. Required by Reverb if you use WebSockets beyond one instance. Technically optional (Laravel defaults to file/database drivers), but Redis is the standard choice for production-ready apps.

### `node` — required for React + Vite development
Runs Vite's dev server with hot reload on `localhost:5174`. The anonymous `node_modules` volume in `compose.yaml` keeps native binaries consistent and avoids slow cross-filesystem syncing on Windows.

### `reverb` — optional, for real-time features
Laravel Reverb WebSocket server. Reuses the same PHP image but runs a different process. Won't do anything until you run:

```bash
docker compose exec php composer require laravel/reverb
docker compose exec php php artisan install:broadcasting
```

Leave the service defined so the network wiring exists when you're ready.

### Supervisor — NOT used, kept as reference only
`docker/supervisor/supervisord.conf` shows how you *could* combine php-fpm, queue worker, and Reverb into one container. The default setup avoids this in favor of one process per container.

---

## Design Decisions

**No `container_name:` on services.** Docker Compose generates predictable names from the project folder name (e.g. `MyNewProject-mysql-1`). Explicit names would collide if you run a second Compose project.

**`depends_on` with `condition: service_healthy`.** Waits for MySQL/Redis to be *ready*, not just started, avoiding "connection refused" errors on cold starts.

**PHP 8.4.** Laravel 13 requires PHP 8.3 minimum. Since PHP runs entirely inside Docker, there's no reason not to use the faster 8.4 release.

**Manual scaffolding.** The entrypoints print instructions instead of auto-scaffolding, because auto-scaffolding silently intercepts commands and hides what's being installed. Scaffolding is an explicit one-time step you run yourself.

---

## Folder Structure

```
MyNewProject/
├── backend/                # Laravel 13 app (scaffolded on first run)
├── frontend/               # React + Vite app (scaffolded on first run)
├── docker/
│   ├── php/
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── opcache.ini
│   │   └── www.conf
│   ├── nginx/
│   │   └── default.conf
│   ├── mysql/              # Reserved for custom my.cnf if needed
│   ├── node/
│   │   ├── Dockerfile
│   │   └── entrypoint.sh
│   └── supervisor/
│       └── supervisord.conf   # Reference only, not active by default
├── compose.yaml
├── .env.example
├── .gitignore
└── README.md
```
