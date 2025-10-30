#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Checking prerequisites..."

# Check for required tools
MISSING_TOOLS=()

check_tool() {
    if command -v "$1" &> /dev/null; then
        # For yq, redirect all output to null as it may show usage info
        if [ "$1" = "yq" ]; then
            VERSION=$($1 --version 2>/dev/null | head -n1 || echo "installed")
        else
            VERSION=$($1 version 2>/dev/null || $1 --version 2>/dev/null | head -n1 || echo "installed")
        fi
        echo -e "${GREEN}✓${NC} $1 is installed ($VERSION)"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is not installed"
        MISSING_TOOLS+=("$1")
        return 1
    fi
}

# Check for openshift-install
if ! check_tool "openshift-install"; then
    echo -e "${YELLOW}Installing openshift-install...${NC}"
    # Download and install openshift-install
    # User needs to provide the client or we can download from mirror
    echo "Please download openshift-install from: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
    echo "Or use: wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz"
    exit 1
fi

# Check for oc CLI
if ! check_tool "oc"; then
    echo -e "${YELLOW}Installing oc CLI...${NC}"
    # Download oc CLI
    echo "Please download oc from: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/"
    echo "Or use: wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz"
    exit 1
fi

# Check for hcp CLI
if ! check_tool "hcp"; then
    echo -e "${YELLOW}Installing hcp CLI...${NC}"
    echo "Please install hcp CLI. Check documentation for installation instructions."
    exit 1
fi

# Check for AWS CLI
if ! check_tool "aws"; then
    echo -e "${YELLOW}Installing AWS CLI...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "On macOS, install using: brew install awscli"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "On Linux, install using package manager or: curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
    fi
    exit 1
fi

# Check for yq (for YAML parsing)
if ! check_tool "yq"; then
    echo -e "${YELLOW}Installing yq (for YAML parsing)...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install yq
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Install yq from: https://github.com/mikefarah/yq#install"
    fi
    exit 1
fi

# Check for envsubst (usually comes with gettext)
if ! command -v envsubst &> /dev/null; then
    echo -e "${YELLOW}Installing envsubst (gettext package)...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install gettext
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get install gettext-base || sudo yum install gettext
    fi
    exit 1
fi

if [ ${#MISSING_TOOLS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All prerequisites are installed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Please install the missing tools and run this script again.${NC}"
    exit 1
fi

