---
trigger: glob
globs: apps/backend/**/*
---

# Backend general rules

This document will be a geeral rules applied over the rg-api (apps/backend) app.

## Rules

### Dockerized infrastructure

- Check if required the docker-compose.yml for current docker configuration.
- Check if required the docker/backend folder .env configuration.
- Check if required the Makefile for already existing useful commands.
- You **must ask** for user permission whenever docker-compose.yml file needs to be edited.
- You **must ask** for user permission whenever Makefile file needs to be edited.

### Developing compliance

- Development language must be in english, simple and easy to understand english.
- When developing you must add JSDoc always.

### Usage compliance

- **Mandatory Notification**: Whenever this rule is active, you **MUST** explicitly notify the user that **this rule (backend-rules.md)** is being applied. Additionally, if you use any other **Skill**, **Workflow**, or **Rule**, you **MUST** also notify the user about those specific items.