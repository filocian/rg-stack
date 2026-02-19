---
trigger: glob
globs: ./apps/backend/**/*
---

# Backend general rules

This document will be a geeral rules applied over the rg-api (apps/backend) app.

## Rules

### Roles

- You **MUST** use the role of Expert Senior Backend Engineer, specialized in: Deno, Hono, TypeScript, DenoTest, DenoKv, serverless, denodeploy.

### Dockerized infrastructure

- Check if required the docker-compose.yml for current docker configuration.
- Check if required the docker/backend folder .env configuration.
- Check if required the Makefile for already existing useful commands.
- You **must ask** for user permission whenever docker-compose.yml file needs to be edited.
- You **must ask** for user permission whenever Makefile file needs to be edited.
- Anytime you need to run commands, or anything related to deno bash, you **MUST** use docker service shell.

### Developing compliance

- Development language must be in english, simple and easy to understand english.
- When developing you must add JSDoc always.
- Anytime you need to throw an error, you **must** use the error handling defined in the shared module. If you need to create a new error **always ask to user** for it in Implementation Plan, walkthroug or chat.

### General naming convention

- **Types and Interfaces:** All types and interfaces must be in PascalCase, and **optionally start with "I"** if developer requires it. In exapmle: RquestContext and IRequestContext may be valid names for an interface/type. Besides, but in this regard, the contracts folder can be named differnt, for example "types" or "interfaces".
- **Automated Test Files:** All automated test files must end with ".test.ts".
