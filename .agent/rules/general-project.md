---
trigger: always_on
---

# Generla project rules

This document lists rules that apply for the whole project

## Rules

- When a skill, rule, or workflow is used you must notyfy it to the user.

### .env manipulaiton

- The app env file is placed at ./docker/backend/.env with an example env called .env.example.
- Each time .env is modified, **must create/update** a placeholder file called .env.example with no real values: must contain all keys with placeholder values.
- You can **READ** the .env file whenever you need to without asking for permission.
- You **must ask** for user permission whenever then .env file needs to be edited.