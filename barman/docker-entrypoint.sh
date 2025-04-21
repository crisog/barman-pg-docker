#!/bin/bash
set -e

BARMAN_CONF="/etc/barman.conf"
TEMP_CONF="/tmp/barman.conf"

function setup_ssh {
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

    # Setup SSH for barman user
    mkdir -p /var/lib/barman/.ssh
    if [ ! -z "$SSH_PRIVATE_KEY" ]; then
        echo "$SSH_PRIVATE_KEY" > /var/lib/barman/.ssh/id_rsa
        echo "$SSH_PUBLIC_KEY" > /var/lib/barman/.ssh/id_rsa.pub
        echo "$SSH_PUBLIC_KEY" > /var/lib/barman/.ssh/authorized_keys
    else
        cp /root/.ssh/id_rsa /var/lib/barman/.ssh/id_rsa
        cp /root/.ssh/id_rsa.pub /var/lib/barman/.ssh/id_rsa.pub
        cp /root/.ssh/authorized_keys /var/lib/barman/.ssh/authorized_keys
    fi
    chmod 700 /var/lib/barman/.ssh
    chmod 644 /var/lib/barman/.ssh/id_rsa.pub
    chmod 600 /var/lib/barman/.ssh/id_rsa
    chmod 600 /var/lib/barman/.ssh/authorized_keys
    chown -R barman: /var/lib/barman/.ssh
}

function setup_directories {
    # Setup barman directories
    mkdir -p /var/log/barman && chown -R barman: /var/log/barman
    mkdir -p /backup/barman && chown -R barman: /backup/barman
    mkdir -p /etc/barman.d && chown -R barman: /etc/barman.d
}

# Setup SSH keys
setup_ssh

# Setup directories
setup_directories

# Start cron service
/etc/init.d/cron start

# Make sure SSH is running properly
# Start sshd WITHOUT the -D option so it goes to background
/usr/sbin/sshd
echo "SSH daemon started"

# Check if SSH is actually listening
sleep 2
netstat -tuln | grep ":22 "
echo "SSH listening status check completed"

# Now execute the command (likely "barman")
echo "Starting main command: $@"
exec "$@"