FROM denoland/deno:alpine

WORKDIR /app

# Prefer not to run as root.
USER deno

# Cache the dependencies as a separate step (if deno.json or import_map.json exists)
COPY deno.json* .
# COPY import_map.json* . 

# These steps will be re-run upon each file change in your working directory:
COPY . .

# Compile the main app so that it doesn't need to be compiled each startup/entry.
# RUN deno cache main.ts

CMD ["deno", "run", "--allow-net", "--allow-read", "--allow-env", "src/main.ts"]
