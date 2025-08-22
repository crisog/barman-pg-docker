# barman-pg-docker

**⚠️ EXPERIMENTAL**: This setup is experimental and not recommended for production use. Use at your own risk.

This repo is based off:
- softwarebrahma's [PostgreSQL-Disaster-Recovery-With-Barman](https://github.com/softwarebrahma/PostgreSQL-Disaster-Recovery-With-Barman/tree/master)
- Railway's official [postgres-ssl template](https://github.com/railwayapp-templates/postgres-ssl) for SSL configuration and Railway-specific scripts

# Generate Keys
```bash
# Generate Ed25519 SSH key pair
ssh-keygen -t ed25519 -a 100 -N "" -f id_ed25519

# Base64 encode for safe environment variable storage
SSH_PRIVATE_KEY=$(openssl base64 -A < id_ed25519)
SSH_PUBLIC_KEY=$(openssl base64 -A < id_ed25519.pub)
```