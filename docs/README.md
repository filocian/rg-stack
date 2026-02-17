# Local Docker Stack Guide

This guide explains how to set up and run the local development environment using Docker.

## Prerequisites

- Docker and Docker Compose installed
- Git installed and configured with SSH access to the repositories

## Quick Start

1. **Initialize Submodules and Data Directories** (First time only)
   ```bash
   make init
   ```

2. **Start the Stack**
   ```bash
   make start
   ```

3. **Verify Services**
   - **Frontend**: http://app.rg.local (traefik routing) or http://localhost:5173
   - **Backend**: http://api.rg.local (traefik routing) or http://localhost:8000
   - **PgAdmin**: http://pgadmin.rg.local (traefik routing) or http://localhost:8081
   - **Traefik Dashboard**: http://localhost:8080

   *Note: You may need to add local DNS entries to your `/etc/hosts` file:*
   ```
   127.0.0.1 app.rg.local api.rg.local pgadmin.rg.local
   ```

## Managing Services

- **Stop Services**:
  ```bash
  make stop
  ```

- **Rebuild Services**:
  ```bash
  make build
  ```

- **View Logs**:
  ```bash
  make logs
  ```

## Development

- **Backend Shell**:
  ```bash
  make shell-backend
  ```

- **Frontend Shell**:
  ```bash
  make shell-frontend
  ```

## Troubleshooting

- If services fail to start, check logs with `make logs`.
- Ensure ports 80, 8080, 8081, 4512 are not in use.
- Ensure Docker is running.
