.PHONY: start stop build shell-backend shell-frontend test-backend test-frontend init logs

# Start all services in detached mode
start:
	docker-compose up -d

# Stop all services
stop:
	docker-compose down

# Build or rebuild services
build:
	docker-compose build

# View logs
logs:
	docker-compose logs -f

# Access backend shell
shell-backend:
	docker-compose exec backend sh

# Access frontend shell
shell-frontend:
	docker-compose exec frontend sh

# Run backend tests
test-backend:
	docker-compose exec backend deno test

# Run frontend tests
test-frontend:
	docker-compose exec frontend npm run test

# Initialize submodules and data directories
init:
	git submodule update --init --recursive
	mkdir -p docker/postgres/data docker/denokv/data
