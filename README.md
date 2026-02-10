# Matrix on Ratio1

A Matrix homeserver (Synapse) deployed as a Worker App on a Ratio1 edge node.

## Overview

This setup provides a lightweight Matrix homeserver suitable for 5-6 people, running as a Worker App on your Ratio1 edge node. Uses SQLite for simplicity and persistent storage for data retention.

## Quick Start

1. Deploy this repo to a Ratio1 Worker App Runner
2. Set resource limits (recommended):
   - CPU: 1-2 cores
   - Memory: 1-2 GB RAM
   - Storage: 2-5 GB persistent volume
   - Expose port: 8008

3. Configure the Worker App with these commands:
   ```bash
   ./start.sh
   ```

## Configuration

- Server runs on port 8008
- Uses SQLite database (stored in persistent volume)
- Server name: matrix.local
- Data directory: /data (mounted persistent volume)
- Synapse runs from a Python virtualenv at `/data/synapse-venv`

## Worker App Runner Example

```yaml
# Example Worker App configuration
name: matrix-homeserver
repo: https://github.com/youruser/matrix-on-ratio1
build_cmd: ""
run_cmd: "./start.sh"
base_image: ubuntu:22.04
resources:
  cpu: 1
  memory: "2GB"
port: 8008
health_check:
  path: "/_matrix/client/versions"
volumes:
  - "/data:/data"
environment: {}
```

## Usage

Once running, access your Matrix homeserver at:
- Client API: http://localhost:8008/_matrix/client/
- Server API: http://localhost:8008/_matrix/server/

Use any Matrix client (Element, etc.) to connect using server name "matrix.local".

## Database

Uses SQLite for simplicity. Database file: `/data/homeserver.db`

## Scaling

For 5-6 users, this configuration provides adequate performance:
- 1-2 CPU cores
- 1-2 GB RAM
- SQLite handles the load well for small groups
- Consider PostgreSQL for larger deployments

## Persistence

The entire data directory (`/data`) should be mounted as a persistent volume to survive container restarts. This includes:
- Database file
- Media files
- Configuration
- Logs

## Troubleshooting

Check logs for Synapse startup issues. Common problems:
- Port conflicts
- Permission issues with data directory
- Network connectivity issues
