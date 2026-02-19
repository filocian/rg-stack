
# **README — Deno Deploy Multi-Region API Architecture (v3)**

**Stack:** Deno Deploy (new) · Deno · Hono · Postgres (Global + Regional) · Deno KV (Cache + Queues)

**Goal:** fast for a 2-person team now, ready for multi-region data residency later.

This README is **stand-alone**. It explains the full method by itself.

----------

## **0) What changed in v3 (important)**

This version adds 3 technical safeguards:

A) **Deno KV value size limit (64 KiB)**

- KV values have a max size of **64 KiB after serialization**.

- Cache writes must never break requests. If payload is too large, we **skip caching** or store a **pointer-only** entry.

B) **Encryption key rotation design (AES-GCM)**

- Cache encryption uses a key that must be rotatable.

- We store a **key version** with each cached value. When the key changes, old entries fail to decrypt and are treated as **cache misses** (safe behavior).

C) **Fast unit testing without Docker (optional)**

- Docker is great for integration tests, but unit tests should run with **in-memory fakes/mocks** for IRepository, IReadModel, etc.

- Deno has official guidance on mocking for isolated tests.

----------

## **1) Non-negotiable rules**

### **1.1 Stateless correctness**

The app must be **stateless for correctness**:

- no core behavior depends on in-memory state,

- memory can be used only as an optional optimization.

### **1.2 Data residency plan**

Sensitive data lives in a **regional DB** (EU, US, …).

A **Global DB** exists only for routing and minimal non-sensitive configuration.

### **1.3 Region must be present in hot requests**

After login, every request must include **region** in:

- the JWT claim (recommended), or

- a signed cookie (also valid).

**Global DB lookup for region is only allowed for:**

- login / first session establishment,

- rare recovery flows.

### **1.4 KV policy: no plaintext sensitive data**

KV must never store **plaintext sensitive data**.

KV may store:

- **encrypted cache blobs** (allowed),

- pointers/IDs,

- non-sensitive metadata,

- locks/idempotency keys.

### **1.5 Queue delivery is at-least-once**

Queue consumers must be **idempotent** because messages can be delivered more than once and failed handlers are retried.

### **1.6 Client errors must be sanitized**

Never return raw DB/driver messages to clients.

Return safe messages + traceId. Log full details internally.

----------

## **2) Big picture (3 planes)**

### **2.1 API plane (online)**

- REST endpoints (Hono)

- parse and validate input

- run business logic

- return standard envelopes (success/error)

### **2.2 Data plane (Postgres)**

- Postgres is the **source of truth**

- sensitive data lives only in the user’s regional DB

### **2.3 Elasticity plane (KV)**

- cache (safe DTOs or encrypted blobs)

- queue (pointer-only messages)

- locks (idempotency / dedupe)

----------

## **3) Database roles (concept only)**

### **3.1 GLOBAL DB (control plane)**

Stores only minimal routing/config:

- tenant/user routing: tenantId -> region, userId -> region

- non-sensitive configuration needed for routing/auth

**GLOBAL DB must not become a second user database.**

### **3.2 REGIONAL DBs (data plane)**

- EU DB stores EU sensitive data

- US DB stores US sensitive data

- later: more regions

### **3.3 Local dev (Docker)**

From day 1 locally we run:

- GLOBAL + EU + US Postgres

    This makes region separation real during development.

### **3.4 First hosted MVP**

Start with:

- GLOBAL + EU

    US is enabled later by adding US DB + routing entries.

----------

## **4) Postgres connections in serverless (critical)**

Deno Deploy can scale across many isolates. If each isolate opens direct TCP connections to Postgres, you can exhaust Postgres connection limits.

**Therefore, production must use one of these:**

- a **serverless driver / proxy protocol** (example: Neon serverless approach)

- an **external pooler** (PgBouncer / Supavisor)

- **AWS RDS Proxy** for RDS/Aurora

Local dev can use direct connections. Hosted should use pooled/proxied connections.

----------

"## **5) Folder structure (golden template)**

We follow a **Modular Monolith** approach. We group code by **Module** (Domain) and then by **Feature** (Vertical Slice), keeping technical layers minimal.

### **5.1 High-Level Skeleton**

```text
/apps               # Entry points (e.g. rg-api)
  /src
    composition.ts  # Dependency Injection root
    routes.ts       # Main router mounting all modules

/modules            # The core business logic
  /shared           # Kernel: Interfaces (Contracts), Utils, Common Infrastructure
  /sales            # Module: Sales
  /users            # Module: Users

/docker             # Infrastructure & Config
```

### **5.2 Module & Feature Structure**

Inside a module, we organize by **Features** (Vertical Slices).

```text
/modules/sales/
├── routes.ts                 # Mounts this module's features
├── /features/                # One directory per Use Case
│   ├── /create-order/        # Feature: Create Order
│   │   ├── routes.ts         # Hono route definition
│   │   ├── endpoint.ts       # HTTP handler & validation
│   │   └── handler.ts        # Business logic (Command Handler)
│   └── /list-orders/
├── /domain/                  # (Optional) Shared domain rules/entities for this module
└── /infrastructure/          # (Optional) Module-specific DB adapters
```

- **Business-first**: Open `/features/create-order` and see everything related to creating orders.
- **Shared Kernel**: Use `/modules/shared` only for truly common utilities (Logger, DB Drivers, Base Interfaces).

----------

## **6) Layering model (explicit)**

We use 4 layers:

1. **App ./**

- builds shared services

- mounts modules

- global middleware

1. **Module/Feature**

- HTTP endpoints

- validation

- handlers or simple services

1. **Domain (optional)**

- business invariants

- no IO

1. **Infrastructure**

- DB adapters

- KV adapters

- crypto

- outbox processing

**Rule:** Features import interfaces from Shared/Contracts. Concrete implementations are created in App/composition.ts.

----------

## **7) Shared contracts (interfaces) — required**

The contracts (interfaces) naming must be in PascalCase, and **optionally start with 'I'**.

### **7.1 Request context**

```text
IRequestContext:
  traceId: string
  tenantId: string
  userId: string
  region: "EU" | "US" | string
  auth: object
```

### **7.2 Commands and queries**

```text
ICommand:
  type: string

IQuery:
  type: string
```

### **7.3 Handlers (CQRS)**

```text
ICommandHandler<TCommand, TResult>:
  handle(cmd: TCommand, ctx: IRequestContext) -> TResult

IQueryHandler<TQuery, TResult>:
  handle(query: TQuery, ctx: IRequestContext) -> TResult
```

### **7.4 Database routing**

```text
IDbRouter:
  controlDb() -> DbClient              // GLOBAL DB
  regionDb(region: string) -> DbClient // EU/US/...
```

### **7.5 Region resolver**

```text
IRegionResolver:
  // Hot path: region comes from JWT/cookie
  // Slow path: lookup in GLOBAL DB only when needed
  resolve(auth, ctx) -> string
```

### **7.6 Transactions**

```text
ITransactionRunner:
  run(db: DbClient, fn: (txDb: DbClient) -> any) -> any
```

### **7.7 Repository and read model**

```text
IRepository<TEntity, TId>:
  getById(id: TId, ctx: IRequestContext) -> TEntity | null
  save(entity: TEntity, ctx: IRequestContext) -> void

IReadModel<TQuery, TView>:
  execute(query: TQuery, ctx: IRequestContext) -> TView
```

### **7.8 Cache, queue, lock**

```text
ICache:
  get(key) -> any | null
  set(key, value, ttlMs) -> void
  delete(key) -> void

IQueue:
  enqueue(message, options?) -> void
  listen(handler) -> void

ILock:
  tryAcquire(key, ttlMs) -> bool
```

### **7.9 Outbox**

```text
IOutbox:
  append(txDb, event) -> void
  fetchPending(db, limit) -> events[]
  markProcessed(db, eventId) -> void
```

### **7.10 Crypto for KV cache blobs (AES-GCM)**

We encrypt/decrypt sensitive payloads stored in KV using Web Crypto (AES-GCM).

```text
ICryptoBox:
  encrypt(plaintextBytes, aadBytes?) -> { keyVersion: string, ivBytes, ciphertextBytes }
  decrypt(keyVersion, ivBytes, ciphertextBytes, aadBytes?) -> plaintextBytes
```

### **7.11 Standard HTTP envelopes**

```text
ApiSuccess<T>:
  ok: true
  traceId: string
  data: T

ApiError:
  ok: false
  traceId: string
  error:
    code: string
    message: string
    details?: any   // must be safe for clients
```

### **7.12 Logger**

```text
ILogger:
  info(eventName, fields)
  warn(eventName, fields)
  error(eventName, fields)    
```

----------

## **8) Routing: App → Module → Feature (Hono)**

We mount sub-apps with route(). Ordering matters (avoid catch-alls before specific routes).

**Pseudo:**

```text
// App/routes.ts
mountModules(app):
  app.route("/sales", SalesRoutes())
  app.route("/users", UsersRoutes())

// Sales/routes.ts
SalesRoutes():
  sales = new Hono()
  sales.route("/orders", CreateOrderRoutes())
  sales.route("/orders", ListOrdersRoutes())
  return sales
```

----------

## **9) Region resolution (fast hot path)**

### **9.1 Rule**

Every normal request must carry region (JWT claim or signed cookie).

Global DB lookup is allowed only in login/first session.

### **9.2 Context building (hot path)**

```text
buildContext(req):
  traceId = getOrCreateTraceId(req)
  auth = parseAuth(req)

  region = auth.regionClaimOrCookie
  if not region:
    // Only allowed for login/slow flows
    region = RegionResolver.resolve(auth, { traceId })

  return { traceId, tenantId: auth.tenantId, userId: auth.userId, region, auth }
```

### **9.3 Slow path (login/first session)**

```text
RegionResolver.resolve(auth, ctx):
  return TenantDirectory.lookupRegion(auth.tenantId, auth.userId) // GLOBAL DB
```

----------

## **10) CQRS policy: pragmatic (reduced boilerplate)**

We support two levels:

### **10.1 Level A — Simple CRUD path (default)**

For simple operations:

- endpoint → validate → call a simple service function → repository/db → return

- no Command/Query ceremony

- no outbox unless needed

```text
UpdateUserNameEndpoint(req):
  ctx = buildContext(req)
  input = UpdateUserNameValidator.parse(req.body)
  result = updateUserNameService(input, ctx)
  return ok(result)
```

### **10.2 Level B — Full Use Case path (when needed)**

Use Command/Query + Handler when:

- complex business rules,

- multi-step workflows,

- transactions + outbox,

- background jobs.

----------

## **11) Dispatching: no magic strings**

Avoid Map<string, handler> with string typos.

### **11.1 Preferred: direct function imports**

Handlers are stateless functions, exported directly.

```text
// CreateOrderCommandHandler.ts
export function handleCreateOrder(cmd, ctx): ...

// Feature endpoint imports it directly
import { handleCreateOrder } from "./CreateOrderCommandHandler.ts"
```

### **11.2 Optional: typed module router object**

```text
SalesHandlers = {
  CreateOrder: handleCreateOrder,
  ListOrders: handleListOrders,
}

dispatch(kind, message, ctx):
  return SalesHandlers[kind](message, ctx)
```

----------

## **12) Cache strategy (KV) — useful at the edge**

### **12.1 KV value size limit (critical)**

KV **values have a maximum length of 64 KiB after serialization**.

Therefore cache writes can fail if the DTO is big.

**Rule:** Cache writes must never break a request.

If payload is too big, **skip caching** or store **pointer-only**.

### **12.2 Three cache modes**

#### Mode 1 — Safe DTO cache (best)

Store non-sensitive DTOs directly.

#### Mode 2 — Encrypted payload cache (for sensitive)

Store encrypted blob: {keyVersion, iv, ciphertext} (no plaintext).

#### Mode 3 — Pointer-only cache (fallback)

Store pointer-only when payload is too large or policy disallows caching.

### **12.3 CacheKv: size guard behavior (required)**

We must catch the KV write failure and continue.

```text
CacheKv.set(key, value, ttlMs):
  try:
    kv.set(key, value, ttlMs)
  catch err:
    // This can happen when value > 64 KiB after serialization
    Logger.warn("cache.set.skipped", { key, reason: "VALUE_TOO_LARGE_OR_KV_ERROR" })
    // Do not throw. Cache is best-effort.
```

Optionally pre-check size:

```text
maybeSize = approximateJsonSize(value)
if maybeSize > 60KiB:
  skip cache
else:
  try set, catch and skip
```

(We use 60 KiB as a safety buffer; actual limit is 64 KiB after serialization.)

### **12.4 Cache pseudocode (end-to-end)**

```text
getOrderEndpoint(req):
  ctx = buildContext(req)
  orderId = req.params.id
  cacheKey = ["cache","order",ctx.region,orderId]

  cached = Cache.get(cacheKey)
  if cached exists:
    if cached.kind == "PLAINTEXT_SAFE":
      return ok(cached.value)
    if cached.kind == "ENCRYPTED":
      bytes = CryptoBox.decrypt(cached.keyVersion, cached.iv, cached.ciphertext, aad=ctx.tenantId)
      view = JSON.parse(bytes)
      return ok(view)
    if cached.kind == "POINTER":
      // fall through to DB

  db = DbRouter.regionDb(ctx.region)
  view = db.selectOrderView(orderId)

  if isNonSensitive(view):
    Cache.set(cacheKey, {kind:"PLAINTEXT_SAFE", value:view}, ttl=60s)  // best-effort
  else if policyAllowsEncryptedCache(view):
    bytes = JSON.stringify(view)
    enc = CryptoBox.encrypt(bytes, aad=ctx.tenantId)
    Cache.set(cacheKey, {kind:"ENCRYPTED", keyVersion:enc.keyVersion, iv:enc.iv, ciphertext:enc.ciphertext}, ttl=30s)
  else:
    Cache.set(cacheKey, {kind:"POINTER", id:orderId}, ttl=10s)

  return ok(view)
```

----------

## **13) Encryption (AES-GCM) with key rotation design**

### **13.1 AES-GCM in Deno**

We use Web Crypto AES-GCM (authenticated encryption).

### **13.2 Key versioning (required design)**

We store a keyVersion with every encrypted cache value.

**Example format:**

- KV value includes { keyVersion: "v1", iv, ciphertext }

**Rotation behavior:**

- if current environment key is "v2" and cache entry says "v1",

  - we try decrypt with v1 key if available,

  - if not available or decrypt fails: treat as cache miss and overwrite with v2.

### **13.3 Key ring contract (simple)**

We keep keys in a “key ring”:

- one active key version for encrypting new values

- optional older keys for decrypting old cache entries

```text
CryptoBox.encrypt(plaintext):
  kv = ActiveKeyVersion()
  key = KeyRing.get(kv)
  return { keyVersion: kv, iv, ciphertext }

CryptoBox.decrypt(keyVersion, iv, ciphertext):
  key = KeyRing.get(keyVersion)
  if !key: throw "UNKNOWN_KEY_VERSION"
  return decryptWithKey(key, iv, ciphertext)
```

### **13.4 Safe failure rule**

If decryption fails:

- do not throw to client,

- treat it as cache miss,

- fetch from DB,

- rewrite cache with current key version (best-effort).

----------

## **14) KV queues (pointer-only + idempotent workers)**

Queue messages remain pointer-only, which is correct for background work.

KV documentation highlights limits (including 64 KiB value size) and queue APIs.

### **14.1 Message contract**

```text
QueueMessage:
  jobId: string
  type: string
  tenantId: string
  region: string
  ref:
    entityId: string
  createdAt: timestamp
```

### **14.2 Worker pseudocode (idempotent)**

```text
Queue.listen(async (msg) => {
  ok = Lock.tryAcquire(["locks","jobs",msg.jobId], ttlMs=300_000)
  if !ok: return

  db = DbRouter.regionDb(msg.region)
  entity = db.loadSensitive(msg.ref.entityId)
  runJob(msg.type, entity)
})
```

----------

## **15) Outbox (DB → queue) for consistency**

Use outbox when “write + schedule work” must be consistent.

### **15.1 Write outbox inside transaction**

```text
handleCreateOrder(cmd, ctx):
  db = DbRouter.regionDb(ctx.region)

  TransactionRunner.run(db, (tx) => {
    orderId = saveOrder(tx, cmd)
    Outbox.append(tx, {
      eventId: newId(),
      type: "OrderCreated",
      tenantId: ctx.tenantId,
      region: ctx.region,
      ref: { entityId: orderId },
      createdAt: now()
    })
  })
```

### **15.2 Outbox processor**

```text
OutboxProcessor.run(region):
  db = DbRouter.regionDb(region)
  events = Outbox.fetchPending(db, limit=100)

  for e in events:
    Queue.enqueue({ jobId:e.eventId, type:e.type, tenantId:e.tenantId, region:e.region, ref:e.ref, createdAt:e.createdAt })
    Outbox.markProcessed(db, e.eventId)
```

----------

## **16) Standard endpoint template (mandatory)**

All endpoints must:

- build context (traceId, tenantId, region)

- validate

- execute logic

- return standard envelopes

- log start/ok/fail

- sanitize errors

```text
Endpoint(req):
  start = now()
  ctx = buildContext(req)

  Logger.info("request.start", { traceId: ctx.traceId, path: req.path, region: ctx.region })

  try:
    result = runFeature(req, ctx)
    Logger.info("request.ok", { traceId: ctx.traceId, ms: now()-start })
    return { status: 200, body: ApiSuccess(ok=true, traceId=ctx.traceId, data=result) }

  catch err:
    Logger.error("request.fail", { traceId: ctx.traceId, ms: now()-start, err })
    http = HttpErrorMapper.toHttpResponse(err, ctx) // sanitized
    return http
```

----------

## **17) Error handling (sanitized)**

### **17.1 Error types**

- InputError → 400

- DomainError → 422 (or 409)

- NotFoundError → 404

- InfraError → 503

### **17.2 Sanitization rules (strict)**

- InfraError responses must use a **generic** client message.

- Never expose SQL/driver error text to the client.

- Full details go to logs only (with traceId).

```text
HttpErrorMapper.toHttpResponse(err, ctx):
  if err is InfraError:
    publicMessage = "Service temporarily unavailable."
  else:
    publicMessage = safeMessage(err)

  return ApiError(traceId=ctx.traceId, code=..., message=publicMessage)
```

----------

## **18) Environment configuration (Deno Deploy contexts)**

Use environment variables with contexts (Production / Preview / Local / Build).

**Required env vars (concept):**

- GLOBAL_DB_URL

- EU_DB_URL

- US_DB_URL (local now; prod later)

- KV_PATH (optional local; e.g. ./kv.sqlite)

- CACHE_ENC_ACTIVE_KEY_VERSION (e.g. v2)

- CACHE_ENC_KEYS_JSON (map of versions to base64 keys; or separate env vars per version)

- APP_ENV = local | preview | prod

----------

## **19) Testing strategy (fast unit tests + Docker integration)**

### **19.1 Unit tests (no Docker, fast)**

Unit tests should not require Postgres or KV. Use:

- in-memory fakes for IRepository, IReadModel, ICache, IQueue

- Deno mocks/spies where needed

Deno provides an official mocking tutorial for isolated tests.

**Pseudo example:**

```text
// Shared/Testing/Fakes.ts
class InMemoryOrderRepository implements IRepository:
  store = Map()
  getById(id, ctx): return store.get(id) ?? null
  save(entity, ctx): store.set(entity.id, entity)

// test
repo = new InMemoryOrderRepository()
result = handleCreateOrder(cmd, ctx, deps={repo, ...})
assertEquals(...)
```

### **19.2 Integration tests (Docker)**

Use Docker for:

- real Postgres migrations,

- real region routing (GLOBAL/EU/US),

- outbox + queue integration.

----------

## **20) PR checklist (non-negotiable)**

- Region is present on hot requests (JWT/cookie). Global lookup only in login/slow flows.

- Production DB uses pooling/proxy/serverless driver to avoid connection storms.

- KV cache:

  - plaintext only for safe non-sensitive DTOs,

  - encrypted blobs allowed for sensitive cache,

  - never plaintext sensitive values,

  - cache set is best-effort with size guard (64 KiB limit).

- Encryption:

  - cache values include keyVersion,

  - decryption failure → cache miss (safe),

  - key rotation supported by design.

- Queue jobs are pointer-only and idempotent.

- Infra errors are sanitized (no driver messages leak to clients).

----------

## **21) Minimal “start now” build order**

1. Create folder structure + all I* contracts

2. Implement standard ILogger, Trace, errors + sanitized HttpErrorMapper

3. Implement DbRouter (GLOBAL/EU/US) + local direct connections

4. Implement RegionResolver (hot path expects region; slow path uses TenantDirectory only at login)

5. Implement Hono app + module routing

6. Implement 1 module with:

    - 1 Simple CRUD feature

    - 1 Query feature

7. Implement KV:

    - CacheKv with size guard (skip on >64 KiB)

    - CryptoBox with key versioning (v1/v2…)

    - QueueKv + LockKv (idempotent worker)

8. Add outbox only for the first workflow that truly needs it

----------

## **Appendix — Deno KV limits you must remember**

- **Max value size: 64 KiB after serialization**

- **Max key size: 2048 bytes after serialization**

    (Design cache keys accordingly.)

----------
