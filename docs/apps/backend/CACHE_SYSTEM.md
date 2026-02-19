# Deno KV Caching System

This document outlines the fundamentals of the Caching System implemented in `apps/backend`. It is designed to be robust, secure (encrypted), and resilient (size limits), following the project's **Development Guidelines**.

## 1. Fundamentals

The system uses [Deno KV](https://deno.com/kv) as the underlying storage. It is abstracted behind a `Cache` interface to allow for future changes if needed, but the current implementation is strictly `DenoKvCache`.

### Key Features
1.  **Encryption (AES-GCM)**: Sensitive data can be encrypted at rest.
2.  **Key Rotation**: Supports multiple key versions. Data encrypted with an old key can still be decrypted (until the key is removed from rotation).
3.  **Size Safety**: Deno KV has a 64KiB value limit. The cache system catches errors when values are too large, ensuring cache writes never break the main request.
4.  **Pointer Support**: Large datasets or lists of IDs can be stored as "Pointers" (standard arrays/objects) to avoid fetching massive payloads repeatedly.

## 2. Usage

### 2.1 Basic Usage (Plaintext)

Use it for non-sensitive data, like public configurations or non-personal content.

```typescript
import { useKvCache } from '@/modules/shared/infrastructure/useKvCache.ts';

// Get cache instance via hook
const { cache } = useKvCache();

// SET
await cache.set(['config', 'public-settings'], { theme: 'dark' }, 60_000); // 60s TTL

// GET
const settings = await cache.get<{ theme: string }>(['config', 'public-settings']);
if (settings) {
  console.log(settings.theme);
}
```

### 2.2 Encrypted Caching

For sensitive data (PII, user sessions), encryption is handled via configuration. The `DenoKvCache` is instantiated with a `shouldEncrypt` strategy in `main.ts`.

If you need to ensure encryption for a specific write, you currently rely on the global configuration strategy passed to the cache constructor.

*Note: The current implementation inspects the value/config to decide. If you need explicit control, ensure your `shouldEncrypt` function in `main.ts` covers your data type.*

### 2.3 Pointers (Handling Large Lists)

If you have a large list of IDs (e.g., "All Books for User X"), store the IDs in the cache. Then use the IDs to fetch details from the DB (which might also be cached individually).

```typescript
import { useKvCache } from '@/modules/shared/infrastructure/useKvCache.ts';
const { cache } = useKvCache();

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

1.  **Always set a TTL**: Avoid stale data persisting forever.
2.  **Graceful Failures**: The cache `get` returns `null` on error/miss. Your code must always handle the `null` case by falling back to the source of truth (Database).
3.  **Use Arrays for Keys**: Deno KV keys are arrays `['users', '123', 'profile']`. This provides hierarchical namespace support.

## 4. Configuration

Encryption keys are managed via environment variables defined in `config.ts`:

-   `CACHE_ACTIVE_KEY_VERSION`: The version used for *new* writes (e.g., "v1").
-   `CACHE_ENCRYPTION_KEY_V1`: Base64 encoded AES key.
-   `CACHE_ENCRYPTION_KEY_V2`: (Optional) Next key version.

To rotate keys:

1. Add new key (V2) to env.
2. Deploy.
3. Change `CACHE_ACTIVE_KEY_VERSION` to "v2".
4. Old "v1" data is still readable. Use lazy migration (next write will use v2).

## 5. Architecture

- **Interface**: `Cache` (in `modules/shared/types/Cache.ts`)
- **Implementation**: `DenoKvCache` (in `modules/shared/infrastructure/DenoKvCache.ts`)
- **Encryption**: `AESGCMCryptoBox` (in `modules/shared/infrastructure/AESGCMCryptoBox.ts`)

---
**Status**: Implementation Verified ✅
