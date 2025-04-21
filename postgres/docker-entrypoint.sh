#!/bin/bash
set -e

function customize {
    # Create SSH directory if it doesn't exist
    mkdir -p /root/.ssh
    
    # Use environment variables for SSH keys if provided
    if [ ! -z "$SSH_PRIVATE_KEY" ]; then
        echo "$SSH_PRIVATE_KEY" > /root/.ssh/id_rsa
        echo "$SSH_PUBLIC_KEY" > /root/.ssh/id_rsa.pub
        echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    else
        # Generate SSH keys if not provided via env vars
        ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
        cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    fi
    
    # Set proper permissions
    chmod 700 /root/.ssh
    chmod 644 /root/.ssh/id_rsa.pub
    chmod 600 /root/.ssh/id_rsa
    chmod 600 /root/.ssh/authorized_keys

    # Do the same for postgres user
    su - postgres -c "mkdir -p ~postgres/.ssh
        if [ ! -z \"$SSH_PRIVATE_KEY\" ]; then
            echo \"$SSH_PRIVATE_KEY\" > ~postgres/.ssh/id_rsa
            echo \"$SSH_PUBLIC_KEY\" > ~postgres/.ssh/id_rsa.pub
            echo \"$SSH_PUBLIC_KEY\" > ~postgres/.ssh/authorized_keys
        else
            ssh-keygen -t rsa -N \"\" -f ~postgres/.ssh/id_rsa
            cp ~postgres/.ssh/id_rsa.pub ~postgres/.ssh/authorized_keys
        fi
        chmod 700 ~postgres/.ssh
        chmod 644 ~postgres/.ssh/id_rsa.pub
        chmod 600 ~postgres/.ssh/id_rsa
        chmod 600 ~postgres/.ssh/authorized_keys"

    # Create PGDATA directory if using subdirectory approach
    if [ ! -z "$PGDATA" ]; then
        # Check if parent directory exists (volume is mounted)
        parent_dir=$(dirname "$PGDATA")
        if [ ! -d "$parent_dir" ]; then
            # If parent directory doesn't exist, create it (no volume mounted)
            mkdir -p "$parent_dir"
            chown postgres:postgres "$parent_dir"
        fi

        # Now create the PGDATA subdirectory if it doesn't exist
        if [ ! -d "$PGDATA" ]; then
            mkdir -p "$PGDATA"
            chmod 700 "$PGDATA"
            chown postgres:postgres "$PGDATA"
        fi
    fi

    # Start SSH server
    /usr/sbin/sshd 2>&1
}

# Run custom setup and then the standard PostgreSQL entrypoint
customize & /usr/local/bin/docker-entrypoint.sh "$@"