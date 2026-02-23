# Global Error Handling System

This document outlines the error handling architecture in the `apps/backend` project. The system is designed to be centralized, robust against information leakage, and easy to use via domain-specific helper functions.

## 1. Principles

- **Never Leak Infrastructure Secrets:** Internal errors (5xx) must never bleed stack traces or connection strings to the client.
- **Traceability:** Every error must be correlated to the failing request via a `traceId`.
- **Standardized Shape:** All errors are returned in a consistent JSON envelope (see `API_RESPONSES.md`).
- **Domain-Driven Exceptions:** Developers should throw semantic errors (Input, Domain, NotFound) rather than manually constructing HTTP responses.

## 2. Core Components

The error handling system in `modules/shared/infrastructure/errors/` consists of two main pieces:

1. **`error-helpers.ts`**: Functions to throw semantic errors from anywhere in the codebase.
2. **`global-error-handler.ts`**: A centralized Hono middleware that catches all exceptions and normalizes them into standard HTTP responses.

## 3. Usage (Throwing Errors)

Instead of returning HTTP responses directly or throwing generic Error objects, use the provided helper functions. This ensures standard formatting and automatic logging.

```typescript
import { throwInputError, throwDomainError, throwNotFound } from '@/modules/shared/infrastructure/errors/error-helpers.ts';

// 1. Validation Errors (400 Bad Request)
if (!user.email.includes('@')) {
  throwInputError('Invalid email format', { field: 'email', provided: user.email });
}

// 2. Business Rules (422 Unprocessable Entity)
if (user.balance < cost) {
  throwDomainError('Insufficient funds', { required: cost, current: user.balance });
}

// 3. Not Found (404)
if (!record) {
  throwNotFound('User profile not found', { userId: '123' });
}

// 4. Infrastructure Failures (503 Service Unavailable)
// The client will ONLY see "Service Unavailable" or a generic message.
// The raw details ({ dbError: '...' }) are secured and only visible in server logs.
if (!dbIsUp) {
  throwInfraError('Database connection lost', { dbError: 'conn reset' });
}
```

## 4. How the Global Handler Works

The `globalErrorHandler` is registered in the main Hono application (`http.ts`):

```typescript
app.onError(globalErrorHandler);
```

When an error is thrown, the handler performs the following:

1. **Extraction:** Retrieves the `traceId` from the request context.
2. **Classification:** Determines if it's a known HTTP exception (like our helpers) or an uncaught standard `Error`.
3. **Sanitization:** If the error is a 5xx series (Infrastructure or Uncaught), the true message and internal details are omitted from the client payload and replaced with a generic fallback message.
4. **Logging:** The full error, including the secure details and stack trace, is logged to the server console alongside the `traceId` for debugging.
5. **Response:** A strictly typed `ApiErrorResponse` is dispatched to the client.

## 5. Client Experience

No matter what goes wrong on the backend, the frontend will always receive an HTTP error status code, and a JSON body matching this shape:

```json
{
  "ok": false,
  "traceId": "123e4567-e89b-12d3-a456-426614174000",
  "error": {
    "code": "BAD_REQUEST",
    "message": "Invalid email format",
    "details": {
      "field": "email"
    }
  }
}
```
