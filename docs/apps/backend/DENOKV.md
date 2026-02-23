# Deno KV

`apps/backend` relies heavily on [Deno KV](https://deno.com/kv) for its core persistence layer. Deno KV is a globally distributed, highly consistent key-value store built directly into the Deno runtime, backed by FoundationDB.

This document outlines how Deno KV is used in the project.

## 1. Primary Use Cases

1. **Caching Layer:** As documented in `CACHE_SYSTEM.md`, Deno KV acts as our encrypted, fast-access cache.
2. **Persistence:** Deno KV can also act as the primary database for specific micro-features (like rate limiting, feature flags, or simple counters).

## 2. Key Structure & Namespacing

Deno KV stores data hierarchically using arrays of strings, numbers, or booleans as keys. This replaces traditional table systems.

**Best Practices for Keys:**
- **Group logically:** Think of the path like a REST URL.
- **Prefix collections:** Always start with a collection noun.
- **Use variables safely:** `['users', userId, 'preferences']`

```typescript
// Good
const key = ['tenant', tenantId, 'users', userId, 'profile'];

// Bad (Hard to query ranges)
const key = [`tenant_${tenantId}_user_${userId}`]; 
```

## 3. The Size Limit constraint

**CRITICAL:** Deno KV enforces a strict maximum size of **64 KiB** per value payload. 

If you attempt to write a value larger than 64 KiB, the underlying `kv.set()` operation will throw a fatal error.

### How we mitigate this:
1. **Safety Buffer:** Our `DenoKvCache` implementation implements a manual pre-check before writing, using a ~60 KiB soft limit (`maxSize: 61440`). 
2. **Pointers:** You must never store massive arrays of objects in a single KV entry. Instead, use "Pointers". Store a list of IDs in KV (`['user', id, 'posts'] = ['post1', 'post2']`), and store the objects individually (`['post', 'post1'] = {...}`).
3. **Graceful degradation:** The cache intercepts size limit errors and logs a warning instead of crashing the HTTP request, guaranteeing that cache failures do not break the API (Guideline §12.1).

## 4. Initialization & Access

When possible, access Deno KV instances through Dependency Injection or predefined Factories, rather than calling `Deno.openKv()` randomly.

In our current architecture:
1. `Deno.openKv()` is called exactly once in `cacheFactory.ts`.
2. The KV connection is passed into the `DenoKvCache` instance.
3. The cache is injected into Hono Context.

If future database collections require direct KV access without the Cache interface, a similar generic `dbMiddleware` should be injected into the Hono Context carrying the globally opened `Deno.Kv` instance.

## 5. Local vs Deploy

- **Local:** When running via `deno run`, Deno KV creates an SQLite file in the local file system to simulate the database.
- **Production (Deno Deploy):** The code connects seamlessly to the globally distributed FoundationDB cluster with zero configuration changes required.
