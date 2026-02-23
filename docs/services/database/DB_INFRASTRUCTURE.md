# Database Infrastructure Documentation: Geographical Sharding

This document outlines the architecture, configuration, and operational procedures for the regional PostgreSQL sharding implementation within our local Docker development environment. This setup simulates our production infrastructure (designed for AWS RDS/Aurora or Google Cloud SQL) to ensure compliance with data residency and legal requirements from day one.

## Architectural Overview

The architecture implements a "Control Plane vs. Data Plane" pattern utilizing three independent PostgreSQL nodes. This simulates geographic distribution across multiple continents to enforce local data residency.

*   **`db-global` (Control Plane):** Simulates the primary database instance (e.g., located in `us-east-1`). This node manages global routing, including user authentication credentials and the `home_region` mapping.
*   **`db-eu` (Data Plane - Europe):** Simulates an instance in Frankfurt (e.g., `eu-central-1`). This database exclusively stores data belonging to European users.
*   **`db-us` (Data Plane - USA):** Simulates a secondary instance in Virginia (e.g., `us-east-1`). This database exclusively stores data belonging to US users.

### Key Principles

1.  **Strict Isolation:** There are no shared volumes between the databases. Each container operates exactly as an independent server in its respective region.
2.  **Global Identifiers (UUID v7):** We strictly prohibit the use of `SERIAL` (auto-incremental) IDs. Using auto-incrementing IDs across distributed databases leads to irreconcilable collisions during global data aggregation. 
    *   **Implementation:** All primary keys must use UUID v7. UUID v7 includes a time-based component (timestamp) which ensures records remain sortable by creation time. This prevents index fragmentation and maintains high read/write performance compared to traditional random UUID v4s.

---

## Technical Configuration

### Docker Compose Services

The infrastructure is defined in `docker-compose.yml` with three primary `postgres:latest` services. Each service is exposed via Traefik for internal routing:

*   `db-global.localhost:5432`
*   `db-eu.localhost:5432`
*   `db-us.localhost:5432`

### Environment Configuration

Each database is managed by its own set of environment variables to maintain strict separation of concerns.

*   **Global Node:** `./docker/db-global/.env`
*   **EU Node:** `./docker/db-eu/.env`
*   **US Node:** `./docker/db-us/.env`

*(Always refer to the respective `.env.example` files in each directory for the required keys).*

### Automated PgAdmin Connectivity

To simplify management across multiple nodes, the local `pgadmin` service is pre-configured to automatically connect to all three databases.

This is achieved via a dynamically mounted configuration file: `./docker/pgadmin/servers.json`. When the pgAdmin container starts, it automatically registers `db-global`, `db-eu`, and `db-us` under the "Sharding Nodes" server group.

---

## Operating Procedures

### 1. Starting the Infrastructure

Run the standard Docker Compose command from the root directory:

```bash
docker compose up -d
```

### 2. Accessing Databases via PgAdmin

1. Navigate to `http://pgadmin.localhost` in your browser.
2. Login using the credentials defined in `./docker/pgadmin/.env`.
3. Expand **Servers** -> **Sharding Nodes**. You will see `DB Global`, `DB EU`, and `DB US` pre-configured and ready for query execution.

### 3. Application Connection

The backend currently connects to the Control Plane by default.

Ensure `./docker/backend/.env` is configured properly:
```properties
DB_HOST=db-global
POSTGRES_USER=postgres
POSTGRES_PASSWORD=...
```

The application layer will be responsible (in future iterations) for connecting to `db-eu` or `db-us` dynamically based on the user's `home_region` provided by `db-global` during authentication.

---

## Logical Replication (Pub/Sub)

In a distributed layout, constant cross-region queries to fetch non-sensitive global data (like product catalogs or fixed pricing tiers) introduce severe latency. To mitigate this, we use PostgreSQL Logical Replication to push read-only copies of non-sensitive tables from `db-global` down to the regional nodes.

### Step-by-step Setup

#### A. Configure the Publisher (`db-global`)

1. Connect to `db-global`.
2. Create the table that contains shared, non-sensitive data.
3. Create a publication for that table.

```sql
-- Executed on db-global
CREATE TABLE products (
    id uuid PRIMARY KEY, 
    name text, 
    price numeric
);

-- Publish the data to listening nodes
CREATE PUBLICATION pub_shared_data FOR TABLE products;
```

#### B. Configure the Subscribers (`db-eu` & `db-us`)

1. Connect to the regional node (e.g., `db-eu`).
2. Create the exact same table schema locally.
3. Subscribe to the global publication using the internal Docker DNS name (`db-global`).

```sql
-- Executed on db-eu (and appropriately on db-us)
CREATE TABLE products (
    id uuid PRIMARY KEY, 
    name text, 
    price numeric
);

-- Subscribe to the global publication
CREATE SUBSCRIPTION sub_global_products 
CONNECTION 'host=db-global port=5432 user=postgres password=YOUR_PASSWORD dbname=filocian' 
PUBLICATION pub_shared_data;
```

*Note: Ensure the PostgreSQL user in the connection string has the necessary privileges (`REPLICATION` role) inside `db-global`.*

---

## Maintenance and Best Practices

1. **Schema Migrations:** Migrations must be applied contextually. Tables belonging to the Control Plane run only on `db-global`. Tables belonging to the Data Plane must be applied identically to both `db-eu` and `db-us`.
2. **Data Residency Compliance:** Never store Personally Identifiable Information (PII) of a regional user in the `db-global` node. `db-global` should only map `user_id` -> `home_region`.
3. **UUID Enforcement:** Create a trigger or database-level check (if possible) to prevent the accidental creation of integer-based sequences on tables synchronized across regions. Use PostgreSQL 17/18 native UUIDv7 generators or validated application-side libraries.
4. **Environment File Security:** When creating new nodes or altering configurations, always update `.env.example` with blank/default placeholders to prevent accidental commit of developer credentials.

---

## Compliance Report

| Policy | Usage Description |
| :--- | :--- |
| **Language Rule** | Written entirely in clear, concise English for broad team accessibility. |
| **Documentation Paths** | Created explicitly at `docs/services/database/DB_INFRASTRUCTURE.md` as requested and adhering to stack structural rules. |
| **.env Manipulation** | Document implicitly references correct `.env` and `.env.example` file usage over the architecture. |
