# Deno KV Caching System

This document outlines the fundamentals of the Caching System implemented in `apps/backend`. It is designed to be robust, secure (encrypted), and resilient (size limits), following the project's **Development Guidelines**.

## 1. Fundamentals

The system uses [Deno KV](https://deno.com/kv) as the underlying storage. It is abstracted behind a `Cache` interface to allow for future changes if needed, but the current implementation is strictly `DenoKvCache`.

### Key Features

1. **Encryption (AES-GCM)**: Sensitive data can be encrypted at rest.
2. **Key Rotation**: Supports multiple key versions. Data encrypted with an old key can still be decrypted (until the key is removed from rotation).
3. **Size Safety**: Deno KV has a 64KiB value limit. The cache system catches errors when values are too large, ensuring cache writes never break the main request.
4. **Pointer Support**: Large datasets or lists of IDs can be stored as "Pointers" (standard arrays/objects) to avoid fetching massive payloads repeatedly.

## 2. Usage

### 2.1 Basic Usage (Plaintext)

Use it for non-sensitive data, like public configurations or non-personal content.

```typescript
// Inside any Hono route handler:
const cache = c.get('cache');

// SET
await cache.set(['config', 'public-settings'], { theme: 'dark' }, 60_000); // 60s TTL

// GET
const settings = await cache.get<{ theme: string }>(['config', 'public-settings']);
if (settings) {
  console.log(settings.theme);
}
```

### 2.2 Encrypted Caching

For sensitive data (e.g., PII, user sessions, auth payloads), encryption is handled completely transparently by the cache if the `encrypt: true` option is provided when setting the value.

The AES-GCM Crypto configuration is automatically initialized by the cache factory (`main.ts`). You simply have to declare when you want encryption to occur on a per-call basis.

By default, the cache is non-encrypted (plaintext).

```typescript
// Inside a Hono route handler:
const cache = c.get('cache');

// 1. Plaintext (default)
await cache.set(['user', 'profile', 'public'], { name: 'John' });

// 2. Encrypted (explicit option)
await cache.set(['user', 'profile', 'sensitive'], 
  { ssn: '123-456' }, 
  { encrypt: true } 
);

// Decrypts transparently upon retrieval (the system knows it's encrypted via metadata)
const sensitiveProfile = await cache.get(['user', 'profile', 'sensitive']);
```

### 2.3 Pointers (Handling Large Lists)

If you have a large list of IDs (e.g., "All Books for User X"), store the IDs in the cache. Then use the IDs to fetch details from the DB (which might also be cached individually).

```typescript
// Inside a Hono route handler:
const cache = c.get('cache');

// 1. Fetch IDs from DB (slow query)
const bookIds = await db.getBookIdsForUser(userId);

// 2. Cache the "Pointer" (list of IDs)
await cache.set(['users', userId, 'books', 'ids'], { ids: bookIds });

// 3. Later, retrieve...
const cachedPointer = await cache.get<{ ids: string[] }>(['users', userId, 'books', 'ids']);
if (cachedPointer) {
  // Fast fetch of details by ID
  return await db.getBooksByIds(cachedPointer.ids);
}
```

## 3. Best Practices

1. **Always set a TTL**: Avoid stale data persisting forever. If omitted, the system falls back to `CACHE_DEFAULT_TTL`.
2. **Graceful Failures**: The cache `get` returns `null` on error/miss. Your code must always handle the `null` case by falling back to the source of truth (Database).
3. **Use Arrays for Keys**: Deno KV keys are arrays `['users', '123', 'profile']`. This provides hierarchical namespace support.

## 4. Configuration

Encryption keys are managed via environment variables defined in `config.ts`:

- `CACHE_ACTIVE_KEY_VERSION`: The version used for *new* writes (e.g., "v1").
- `CACHE_ENCRYPTION_KEY_V1`: Base64 encoded AES key.
- `CACHE_ENCRYPTION_KEY_V2`: (Optional) Next key version.
- `CACHE_DEFAULT_TTL`: Default Time-To-Live in milliseconds (e.g., 60000).

To rotate keys:

1. Add new key (V2) to env.
2. Deploy.
3. Change `CACHE_ACTIVE_KEY_VERSION` to "v2".
4. Old "v1" data is still readable. Use lazy migration (next write will use v2).

## 5. Architecture

- **Interface**: `Cache` (in `modules/shared/types/Cache.ts`)
- **Implementation**: `DenoKvCache` (in `modules/shared/infrastructure/cache/DenoKvCache.ts`)
- **Encryption**: `AESGCMCryptoBox` (in `modules/shared/infrastructure/cache/AESGCMCryptoBox.ts`)
- **Dependency Injection**: `cacheFactory.ts` handles initialization, and `cache.middleware.ts` injects it into the `HonoEnv` Context.

### Initialization

The system is initialized in `main.ts` and injected into the App:

```typescript
import { createCacheSystem } from '@/modules/shared/infrastructure/cache/cacheFactory.ts';
import { createApp } from '@/http.ts';

const { cache } = await createCacheSystem(config.cache);
const app = createApp(cache);
```

---
**Status**: Implementation Verified ✅
