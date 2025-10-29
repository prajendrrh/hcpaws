#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Installing OpenShift Hub Cluster..."

# Setup AWS credentials in ~/.aws/credentials and ~/.aws/config
# Source the script instead of running it to preserve environment variables
if [ -f "$PROJECT_DIR/aws-credentials.env" ]; then
    source "$SCRIPT_DIR/setup-aws-credentials.sh"
fi

# Ensure AWS SDK loads config from ~/.aws directory
export AWS_SDK_LOAD_CONFIG=1

# Use current working directory
WORK_DIR="${PWD:-$(pwd)}"

# Check if install-config.yaml exists
if [ ! -f "$WORK_DIR/install-config.yaml" ]; then
    echo "Error: install-config.yaml not found in current directory ($WORK_DIR). Please run generate-install-config.sh first."
    exit 1
fi

# Create cluster in current directory
echo "⏳ Creating cluster (this will take 30-60 minutes)..."
cd "$WORK_DIR"

# Verify AWS credentials are available
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "❌ Error: AWS credentials not found in environment variables"
    echo "   Attempting to reload from aws-credentials.env..."
    source "$PROJECT_DIR/aws-credentials.env"
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
fi

# Verify credentials file exists
if [ ! -f ~/.aws/credentials ]; then
    echo "❌ Error: ~/.aws/credentials not found"
    exit 1
fi

echo "✅ AWS credentials verified and ready"

# Create log file for installation logs
INSTALL_LOG="$WORK_DIR/openshift-install.log"

# Run openshift-install with credentials explicitly available
# Redirect debug output to log file, but keep stdout/stderr for important messages
echo "📝 Installation logs will be saved to: $INSTALL_LOG"
echo "⏳ Starting cluster installation (this will take 30-60 minutes)..."
echo "   Check the log file for detailed progress: tail -f $INSTALL_LOG"

# Run openshift-install and redirect all output to log file
# Show a spinner or periodic status updates
if command -v spinner &> /dev/null; then
    openshift-install create cluster --dir . --log-level debug 2>&1 | tee "$INSTALL_LOG" &
    INSTALL_PID=$!
    # Simple progress indicator
    while kill -0 $INSTALL_PID 2>/dev/null; do
        echo -n "."
        sleep 30
    done
    wait $INSTALL_PID
    EXIT_CODE=$?
else
    # If spinner not available, just redirect process output to log
    # Run in background and show periodic updates
    openshift-install create cluster --dir . --log-level debug > "$INSTALL_LOG" 2>&1 &
    INSTALL_PID=$!
    
    # Show periodic status updates with dots and messages
    COUNTER=0
    echo -n "   Installing"
    while kill -0 $INSTALL_PID 2>/dev/null; do
        sleep 60
        COUNTER=$((COUNTER + 1))
        echo -n "."
        # Show message every 5 minutes
        if [ $((COUNTER % 5)) -eq 0 ]; then
            echo ""
            echo "   Still installing... ($((COUNTER)) minutes elapsed - check $INSTALL_LOG for details)"
            echo -n "   Installing"
        fi
    done
    echo ""
    wait $INSTALL_PID
    EXIT_CODE=$?
fi

# Check if installation was successful
if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ Cluster installation failed!"
    echo "   Check the log file for details: $INSTALL_LOG"
    echo "   Last 50 lines of log:"
    tail -50 "$INSTALL_LOG"
    exit $EXIT_CODE
fi

echo ""
echo "✅ Hub cluster installation completed!"
echo "📝 Full installation log saved to: $INSTALL_LOG"

