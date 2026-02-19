# **DEVELOPMENT PLAYBOOK (v3)**

**Goal:** Mechanical, high-speed development suitable for AI Agents.

**Stack:** Deno Deploy · Hono · Postgres · Deno KV

**Architecture:** Strict CQRS + Russian Doll Routing.

----------

## **0) The Golden Rules**

1. **Strict CQRS:** Every feature is either a **Command** (Write) or a **Query** (Read). No "simple services".

2. **Russian Doll Routing:** Routes are defined at the Feature level and mounted upwards (`App -> Module -> Feature`).

3. **Fast Tests First:** Logic is tested with **Unit Tests** using in-memory Fakes. Docker is only for integration.

4. **Region Aware:** `ctx.region` must be passed to all DB calls.

5. **KV Safety:** Cache writes are best-effort (catch errors). Max value size is **64 KiB**.

----------

## **1) The "Write" Path (Commands)**

**Scenario:** Create an Order (Write + Transaction + Side Effects).

**Files to create:**

1. `routes.ts` (Hono instance)

2. `CreateOrderEndpoint.ts` (HTTP adapter)

3. `CreateOrderValidator.ts` (Zod schema)

4. `CreateOrderCommand.ts` (Type definition)

5. `CreateOrderCommandHandler.ts` (Pure logic)

**Code Template (Endpoint):**

```TypeScript
// CreateOrderEndpoint.ts
import { Context } from "hono";
import { successResponse } from "../../Shared/Infrastructure/api-response.ts";
import { throwInputError } from "../../Shared/Errors/error-helpers.ts";
import { CreateOrderValidator } from "./CreateOrderValidator.ts";
import { handleCreateOrder } from "./CreateOrderCommandHandler.ts";

export const CreateOrderEndpoint = async (c: Context) => {
  // 1. Parse & Validate (Zod will throw if invalid)
  const body = await c.req.json();
  const cmd = CreateOrderValidator.parse(body);
  
  // 2. Build Context
  const ctx = c.get("ctx");

  // 3. Logic (Deps injected via composition root)
  const result = await handleCreateOrder(cmd, ctx, deps);

  // 4. Success Response
  return successResponse(c, result, "Order created successfully", 201);
};
```

**Code Template (Handler):**

```TypeScript
// CreateOrderCommandHandler.ts
import { IRepository, ITransactionRunner, IOutbox } from "../../Shared/Contracts/index.ts";

export async function handleCreateOrder(
  cmd: CreateOrderCommand,
  ctx: IRequestContext,
  deps: { 
    repo: IRepository<Order>; 
    txRunner: ITransactionRunner;
    outbox: IOutbox 
  }
) {
  // 1. Validation
  if (cmd.items.length === 0) throw new DomainError("Empty order");

  // 2. Transaction
  return await deps.txRunner.run(async (txDb) => {
    const order = Order.create(cmd, ctx);
    
    // 3. Persist
    await deps.repo.save(txDb, order);

    // 4. Outbox (Pointer Only)
    await deps.outbox.append(txDb, {
      type: "OrderCreated",
      ref: { entityId: order.id },
      region: ctx.region
    });

    return { orderId: order.id };
  });
}
```

----------

## **2) The "Read" Path (Queries)**

**Scenario:** Get Order Details (Read + Cache).

**Files to create:**

1. `routes.ts`

2. `GetOrderEndpoint.ts`

3. `GetOrderValidator.ts`

4. `GetOrderQuery.ts` (Type definition)

5. `GetOrderQueryHandler.ts` (Pure logic)

**Code Template (Endpoint):**

```TypeScript
// GetOrderEndpoint.ts
import { Context } from "hono";
import { successResponse } from "../../Shared/Infrastructure/api-response.ts";
import { throwNotFound } from "../../Shared/Errors/error-helpers.ts";
import { handleGetOrder } from "./GetOrderQueryHandler.ts";

export const GetOrderEndpoint = async (c: Context) => {
  const orderId = c.req.param("id");
  const ctx = c.get("ctx");

  const query = { orderId };
  
  // Logic
  const result = await handleGetOrder(query, ctx, deps);

  if (!result) {
     return throwNotFound("Order not found", { orderId });
  }

  // Success
  return successResponse(c, result);
};
```

**Code Template (Handler):**

```TypeScript
// GetOrderQueryHandler.ts
import { IReadModel, ICache } from "../../Shared/Contracts/index.ts";

export async function handleGetOrder(
  query: GetOrderQuery,
  ctx: IRequestContext,
  deps: { readModel: IOrderReadModel; cache: ICache }
) {
  const cacheKey = ["view", "order", ctx.region, query.orderId];

  // 1. Try Cache
  const cached = await deps.cache.get(cacheKey);
  if (cached) return cached;

  // 2. Read DB
  const view = await deps.readModel.getById(query.orderId, ctx.region);
  if (!view) throw new NotFoundError("Order not found");

  // 3. Set Cache (Best Effort + Size Guard)
  // Note: Implementation of cache.set must catch >64KiB errors
  await deps.cache.set(cacheKey, view, 60_000);

  return view;
}
```

----------

## **3) Routing Strategy (The Russian Doll)**

We mount routes from the bottom up. **Every feature has its own Hono instance.**

### **Level 1: Feature**

_File: `src/Sales/Features/CreateOrder/routes.ts`_

```TypeScript
import { Hono } from "hono";
import { CreateOrderEndpoint } from "./CreateOrderEndpoint.ts";

export const createOrderRoute = new Hono();

// Defined as root "/" relative to parent
createOrderRoute.post("/", CreateOrderEndpoint);
```

### **Level 2: Module**

_File: `src/Sales/routes.ts`_

```TypeScript
import { Hono } from "hono";
import { createOrderRoute } from "./Features/CreateOrder/routes.ts";
import { getOrderRoute } from "./Features/GetOrder/routes.ts";

export const salesRouter = new Hono();

// Mounts features
salesRouter.route("/orders", createOrderRoute); // POST /sales/orders
salesRouter.route("/orders", getOrderRoute);    // GET  /sales/orders/:id
```

### **Level 3: App**

_File: `src/App/routes.ts`_

```TypeScript
import { Hono } from "hono";
import { salesRouter } from "../Sales/routes.ts";

export const appRouter = new Hono();

appRouter.route("/sales", salesRouter);
```

----------

## **4) Testing Strategy (Speed)**

We test logic in **milliseconds** using Fakes.

**Template (Unit Test):**

```TypeScript
import { assertEquals } from "std/assert";
import { handleCreateOrder } from "./CreateOrderCommandHandler.ts";
import { FakeOrderRepository, FakeTxRunner, FakeOutbox } from "../../Shared/Testing/Fakes.ts";

Deno.test("CreateOrder saves to repo and outbox", async () => {
  // Setup Fakes
  const repo = new FakeOrderRepository();
  const outbox = new FakeOutbox();
  const ctx = { userId: "u1", region: "EU" } as any;

  // Act
  await handleCreateOrder(
    { items: [], currency: "EUR" }, 
    ctx, 
    { repo, txRunner: new FakeTxRunner(), outbox }
  );

  // Assert
  assertEquals(repo.items.size, 1);
  assertEquals(outbox.events.length, 1);
});
```

----------

## **5) AI Agent Workflow (Copy & Paste)**

Use this prompt to generate features correctly with Cursor/Windsurf.

**Prompt Template:**

```Plaintext
I need a new feature: [Feature Name] (e.g. "CancelOrder").
Context: Module [Module Name] (e.g. "Sales").
Type: [Command | Query]

Follow the Strict CQRS Architecture (v3):

1. FILES: Create folder /src/[Module]/Features/[Feature] with exactly 5 files:
   - routes.ts (Exports 'const [feature]Route = new Hono()')
   - [Feature]Endpoint.ts (Hono handler)
   - [Feature]Validator.ts (Zod)
   - [Feature][Command|Query].ts (Type)
   - [Feature][Handler].ts (Pure async function with 'deps' injection)

2. ROUTING WIRING:
   - Define POST/GET on "/" in the Feature route.
   - Import and mount it in /src/[Module]/routes.ts.

3. LOGIC RULES:
   - Handler must accept (cmd, ctx, deps).
   - Use IRequestContext.
   - If Command: use ITransactionRunner + IRepository.
   - If Query: use ICache + IReadModel.
   - Endpoint only parses request, calls Handler, and returns `successResponse`.
   - **DO NOT use try/catch**. Exceptions are handled by Global Error Middleware.
   - Use `throwNotFound`, `throwInputError`, etc. from `../../Shared/Errors/error-helpers.ts` if needed.
   - Generate a Unit Test using Fakes for the Handler.
```

----------

## **6) KV Cache Safety Checklist**

When implementing caching, verify:

1. **Size Limit:** Is the object potentially > **64 KiB**?

    - _Yes:_ Store `Pointer-Only` (ID) or skip cache.

    - _No:_ Store DTO.

2. **Sensitive Data:** Does it contain PII (Email, Address, Phone)?

    - _Yes:_ Must use `CryptoBox.encrypt()` (AES-GCM).

    - _No:_ Store plaintext.

3. **Error Handling:**

    - `cache.set()` is wrapped in `try/catch`. Failures are logged (warn), not thrown.

----------

## **7) Pre-Merge Checklist**

1. [ ] **Files:** 5 files created per feature?

2. [ ] **Routing:** Feature route mounted in Module route?

3. [ ] **Strictness:** Endpoint contains NO business logic?

4. [ ] **Test:** Unit test with Fakes passes?

5. [ ] **Region:** `ctx.region` is used for DB calls (no Global DB in hot path)?

6. [ ] **Sanitized:** Endpoint returns `ApiSuccess` / `ApiError` envelopes?
