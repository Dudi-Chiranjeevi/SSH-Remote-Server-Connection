#!/bin/bash

# Function to display script usage
usage() {
    echo "Usage: $0 [-u <username>] [-p <ssh_port>] [-k <pem_file>] [-c] [-f <config_file>]"
    echo "  -u   Remote username (default: current user)"
    echo "  -p   SSH port (default: 22)"
    echo "  -k   Path to AWS private key (.pem file, required for AWS)"
    echo "  -c   Configure ~/.ssh/config for passwordless login (optional)"
    echo "  -f   Path to server list config file (default: ./server_list.conf)"
    exit 1
}

# Default values
USERNAME=$(whoami)
SSH_PORT=22
CONFIGURE_SSH=0
PEM_FILE=""
CONFIG_FILE="./server_list.conf"

# Parse command-line options
while getopts "u:p:k:cf:" opt; do
    case $opt in
        u) USERNAME=$OPTARG ;;
        p) SSH_PORT=$OPTARG ;;
        k) PEM_FILE=$OPTARG ;;
        c) CONFIGURE_SSH=1 ;;
        f) CONFIG_FILE=$OPTARG ;;
        *) usage ;;
    esac
done

# Validate required parameters
if [[ -z $PEM_FILE ]]; then
    echo "Error: Path to AWS private key (.pem file) (-k) is required."
    usage
fi

if [[ ! -f $PEM_FILE ]]; then
    echo "Error: PEM file $PEM_FILE not found."
    exit 1
fi

if [[ ! -f $CONFIG_FILE ]]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Read servers from the configuration file
SERVERS=$(cat "$CONFIG_FILE" | tr '\n' ',' | sed 's/,$//')

# Generate SSH key if it doesn't exist
SSH_KEY_PATH="$HOME/.ssh/id_rsa"
if [[ ! -f $SSH_KEY_PATH ]]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 2048 -f "$SSH_KEY_PATH" -q -N ""
    echo "SSH key generated at $SSH_KEY_PATH"
else
    echo "SSH key already exists at $SSH_KEY_PATH"
fi

# Distribute the public key to each server
IFS=',' read -ra SERVER_LIST <<< "$SERVERS"
for SERVER in "${SERVER_LIST[@]}"; do
    echo "Copying SSH key to $SERVER..."
    scp -i "$PEM_FILE" -P "$SSH_PORT" "$SSH_KEY_PATH.pub" "$USERNAME@$SERVER:/tmp/id_rsa.pub"
    if [[ $? -ne 0 ]]; then
        echo "Failed to copy SSH key to $SERVER. Check username, PEM file, or SSH connectivity."
        continue
    fi

    # Append the public key to authorized_keys on the remote server
    ssh -i "$PEM_FILE" -p "$SSH_PORT" "$USERNAME@$SERVER" "mkdir -p ~/.ssh && cat /tmp/id_rsa.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm /tmp/id_rsa.pub"
    if [[ $? -eq 0 ]]; then
        echo "SSH key successfully copied and configured on $SERVER"
    else
        echo "Failed to configure SSH key on $SERVER"
    fi
done

# Optional: Configure ~/.ssh/config
if [[ $CONFIGURE_SSH -eq 1 ]]; then
    echo "Configuring ~/.ssh/config for easier access..."
    for SERVER in "${SERVER_LIST[@]}"; do
        HOST_ALIAS=$(echo "$SERVER" | tr '.' '-')
        {
            echo "Host $HOST_ALIAS"
            echo "    HostName $SERVER"
            echo "    User $USERNAME"
            echo "    Port $SSH_PORT"
            echo "    IdentityFile $SSH_KEY_PATH"
        } >> "$HOME/.ssh/config"
    done
    chmod 600 "$HOME/.ssh/config"
    echo "Configuration saved in ~/.ssh/config"
fi

echo "SSH setup process completed!"
