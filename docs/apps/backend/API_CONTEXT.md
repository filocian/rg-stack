# API Context (HonoContext & RequestContext)

In a web server, data often needs to be passed down from early-stage middleware to specific route handlers (e.g., authentication info, tracing IDs, or singleton services like caches). 

In `apps/backend`, we achieve this safely through two intertwined concepts: **HonoContext** and **RequestContext**.

## 1. HonoContext (`HonoEnv`)

Hono uses a generic `Context` (`c`) object passed to every route handler. To make this context deeply type-safe in TypeScript, we define a custom environment interface: `HonoEnv`.

**Location:** `modules/shared/types/HonoContext.ts`

```typescript
import { RequestContext } from './RequestContext.ts';
import { Cache } from './Cache.ts';

export interface HonoEnv {
  Variables: {
    ctx: RequestContext;   // Domain-specific request variables (like traceId, userId)
    cache: Cache;          // Infrastructure service (Dependency Injection)
  };
}
```

When building your Hono application or sub-routers, you must pass this generic:
`const app = new Hono<HonoEnv>();`

This ensures that when a developer types `c.get('cache')`, TypeScript knows precisely that it returns a `Cache` instance.

## 2. RequestContext

While `HonoEnv` holds the structure of the *container*, `RequestContext` holds the domain-specific metadata for the specific HTTP request being processed.

**Location:** `modules/shared/types/RequestContext.ts`

```typescript
export interface RequestContext {
  traceId: string;
  userId?: string;     // Added when Auth middleware validates a token
  tenantId?: string;   // Added when multi-tenant bounds are resolved
}
```

### The Context Middleware
The `ctx` object is injected early in the request lifecycle via `contextMiddleware.ts`. 
Its primary job is to ensure that **every single request gets a unique `traceId`**:

1. It checks if the client sent an `x-trace-id` header (useful for linking frontend to backend logs).
2. If none exists, it generates a fresh UUID.
3. It sets it into `c.set('ctx', { traceId })`.

## 3. Dependency Injection via Context

We do not use messy global variables (`export const cache = ...`) because they make unit testing extremely difficult. Instead, we use the `HonoContext` for **Dependency Injection (DI)**.

Services are instantiated once in `main.ts` and injected into the app using middleware:

```typescript
// cache.middleware.ts
export const cacheMiddleware = (cacheInstance: Cache) => {
  return async (c, next) => {
    c.set('cache', cacheInstance); // Injected!
    await next();
  };
};
```

## 4. Usage in Route Handlers

By combining `HonoEnv` and middleware injection, your route handlers become incredibly clean and predictable:

```typescript
app.get('/metrics', async (c) => {
  // 1. Get request metadata
  const { traceId, userId } = c.get('ctx');

  // 2. Get injected services
  const cache = c.get('cache');

  // 3. Do work safely
  await cache.set(['user', 'metrics', userId], data, { encrypt: true });
});
```
