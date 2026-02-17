# Infraestructure overview

The project is going to create a lcoal Docker based infrastructure, wich is a replica of production infrastructure.
The goal is to have a centralized development environment, making easy other people can have and work with same infraestructure.
The stack composition resides in 3 repositries congifuredwith submodules.

## Github

### Git Config

As far as i will handle several github accounts in my different projects, i need to add a specific .gitconfig for every project.
This config will be used for all the project submodules as well.
The ssh key dedicated to msgns_stack is: `/Users/rodrigo.obalat/.ssh/id_ed25519_filocian`
The user name for git config (shown per users activity) is: `Rodrigo.Obalat`
The email for git config (shown per users activity) is: `rodrigo.balat@filocian.com`

### GitModule configuration

The gitModule configuration consists of:

1. Infrastructure stack as main module: contains docker infrastructure, including services and apps.
2. API as submodule: containing API app based on its own repository.
3. Frontend as submodule: containing frontend app based on its own repository.

The gitsubmodules configuration must use dirty for al submodules, in order to make easier the main repo management.

- Whole stack repository: git@github.com:filocian/rg-stack.git
- Backend repository: git@github.com:filocian/rg-api.git
- Frontend repository: git@github.com:filocian/rg-front.git

## Docker stack

### Docker structure

In order to keep stuff in order and simplicity, the stack structure most be as follows:

````
msgns-stack/ (root)
    apps/
        backend/ (api repository)
        frontend/ (frontend repository)
    docker/
        <services>/ (a folder for each service)
            <service_configuration_file> (any .env, or config file relative to its service)
            <service_data_folder>/ (a folder called data, containing all persistency data, or files used by service different from <service_environment_file>, ignored by git)
        <apps>/ ( every app musta have a folder with the same name here)
            <app_dockerfile> (the specific dockerfile if is required)
            <app_environment_file> (.env relative to its app, ignored by git)
            <app_environment_example_file> (.env.example as real .env empty skeleton)
    docs/
        services/ (all documentation generated relative to services)
        apps/ 
            frontend/ (all documentation generated relative to frontend app)
            backend/ (all documentation generated relative to backend app)
        dev_stack/
            <md_doc> (all documentation related to the whole stack)
        README.md (general usage explanation and usage)
    <docker_files> (any docker related file, not specific for any app or service)
    <make_file> (for quick commands)
    <git_files>
        
````

### Tech stack

- Backend: HONO over DENO with denotest
- Frontend: React 19 over Vite and Vitest with tanstack query
- Database: Postgres in its last stable version
- PgAdmin: for managing Postgres
- DenoKV: a local denokv based on sqlite (documentation: https://github.com/denoland/denokv)
- Traefik: for reverse proxy, and using <app>.rg.local

## Makefile

The makefile must procide all commands for:

- start, stop, build docker suite
- commands for all "commandable" services (e.g: bash)
- run frontend/backend tests
- start submodules (must check if exists, or can be forced to re-init from source)

## Documentation

The docs will be added on specified paths, but in regards of docker infra and local structure, the README.md at msgns-stack/docs must be filled with a step by step guide to achieve and run all the local suite.

## Language used for docs an coding in general

Along the whole satack the language used must be english: a simple english easy to understand for non native english people. It applies for: coding, documentation, comments, and everuthing related to the stack
