#!/bin/bash
# YaCy Build Script with Interactive Release/Commit Selector
# Purpose: Build YaCy image with version selection from GitHub
# Usage: ./build.sh
# Features: Shows recent releases and commits, lets user pick one

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GITHUB_REPO="yacy/yacy_search_server"
GITHUB_API="https://api.github.com/repos/$GITHUB_REPO"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check for required dependencies
check_dependencies() {
    local missing=()

    # Check each required command
    for cmd in jq curl docker date sed; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}✗ Missing required dependencies:${NC}"
        for cmd in "${missing[@]}"; do
            echo ""
            case "$cmd" in
                jq)
                    echo -e "  ${YELLOW}jq${NC} - Command-line JSON processor"
                    echo -e "    Ubuntu/Debian: ${CYAN}apt-get install jq${NC}"
                    echo -e "    Alpine:        ${CYAN}apk add jq${NC}"
                    echo -e "    macOS:         ${CYAN}brew install jq${NC}"
                    ;;
                curl)
                    echo -e "  ${YELLOW}curl${NC} - Data transfer tool"
                    echo -e "    Ubuntu/Debian: ${CYAN}apt-get install curl${NC}"
                    echo -e "    Alpine:        ${CYAN}apk add curl${NC}"
                    echo -e "    macOS:         ${CYAN}brew install curl${NC}"
                    ;;
                docker)
                    echo -e "  ${YELLOW}docker${NC} - Container runtime"
                    echo -e "    https://docs.docker.com/engine/install/"
                    ;;
                date)
                    echo -e "  ${YELLOW}date${NC} - Date utility (usually pre-installed)"
                    echo -e "    Ubuntu/Debian: ${CYAN}apt-get install coreutils${NC}"
                    ;;
                sed)
                    echo -e "  ${YELLOW}sed${NC} - Stream editor (usually pre-installed)"
                    echo -e "    Ubuntu/Debian: ${CYAN}apt-get install sed${NC}"
                    ;;
            esac
        done
        echo ""
        echo -e "${RED}Please install missing dependencies and try again.${NC}"
        exit 1
    fi
}

check_dependencies

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║    YaCy Build Script - Variant & Version Selector      ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Step 1: Select Dockerfile variant
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}SELECT DOCKERFILE VARIANT:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${CYAN}[1]${NC} Debian/Ubuntu       (eclipse-temurin:24-jdk-noble) ~500MB"
echo -e "  ${CYAN}[2]${NC} Alpine Linux       (eclipse-temurin:21-jdk-alpine) ~200MB ⭐"
echo -e "      └─ Note: No wkhtmltopdf (PDF rendering disabled)"
echo -e "  ${CYAN}[3]${NC} ARM64 (aarch64)    (eclipse-temurin:21-jdk-noble) ~450MB"
echo -e "  ${CYAN}[4]${NC} ARM32 (armv7)      (eclipse-temurin:11-jdk) ~350MB"
echo ""

declare -A dockerfile_map
dockerfile_map["1"]="Dockerfile"
dockerfile_map["2"]="Dockerfile.alpine"
dockerfile_map["3"]="Dockerfile.aarch64"
dockerfile_map["4"]="Dockerfile.armv7"

declare -A variant_names
variant_names["1"]="Debian/Ubuntu"
variant_names["2"]="Alpine"
variant_names["3"]="ARM64"
variant_names["4"]="ARM32"

declare -A platform_tags
platform_tags["1"]=""           # Ubuntu = blank/default
platform_tags["2"]="alpine"
platform_tags["3"]="aarch64"
platform_tags["4"]="armv7"

while true; do
    echo -n -e "${YELLOW}Select variant (1-4, or Enter for Alpine): ${NC}"
    read -r variant_choice

    # Use Alpine as default if user just presses Enter
    if [ -z "$variant_choice" ]; then
        variant_choice="2"
    fi

    if [ -z "${dockerfile_map[$variant_choice]}" ]; then
        echo -e "${RED}Invalid selection. Try again.${NC}"
        continue
    fi

    SELECTED_DOCKERFILE="$PROJECT_DIR/docker/${dockerfile_map[$variant_choice]}"
    VARIANT_NAME="${variant_names[$variant_choice]}"
    break
done

echo -e "${GREEN}Selected: $VARIANT_NAME ($SELECTED_DOCKERFILE)${NC}"
echo ""

# Step 2: Fetch releases and commits
echo -e "${YELLOW}Fetching releases and commits from GitHub...${NC}"

# Optional GitHub token for higher rate limits (60 -> 5000 requests/hour)
# Set GITHUB_TOKEN env var to use: export GITHUB_TOKEN=ghp_...
CURL_AUTH=""
if [ -n "$GITHUB_TOKEN" ]; then
    CURL_AUTH="-H \"Authorization: token $GITHUB_TOKEN\""
    echo -e "${GREEN}✓ Using GitHub authentication (higher rate limits)${NC}"
fi

# Fetch latest releases (max 10, including pre-releases)
RELEASES=$(eval "curl -s $CURL_AUTH \"$GITHUB_API/releases?per_page=10\" 2>/dev/null" | jq -r '.[] | "\(.tag_name)|\(.published_at)|\(.name)"' 2>/dev/null || echo "")

# If no releases, try fetching tags with commit dates and SHAs
if [ -z "$RELEASES" ]; then
    # Fetch tags and their commit dates (using process substitution to preserve variables)
    RELEASES=$(
        eval "curl -s $CURL_AUTH \"$GITHUB_API/tags?per_page=10\" 2>/dev/null" | jq -r '.[] | "\(.name)|\(.commit.url)"' 2>/dev/null | while IFS='|' read -r tag commit_url; do
            if [ -n "$commit_url" ]; then
                commit_info=$(eval "curl -s $CURL_AUTH \"$commit_url\" 2>/dev/null" | jq -r '.commit.author.date // empty, .sha[0:7] // empty' 2>/dev/null)
                commit_date=$(echo "$commit_info" | sed -n '1p')
                commit_sha=$(echo "$commit_info" | sed -n '2p')
                [ -n "$commit_date" ] && [ -n "$commit_sha" ] && echo "$tag|$commit_date|$commit_sha"
            fi
        done | head -5
    )
fi

# Fetch latest commits (max 6, including master info)
COMMITS=$(eval "curl -s $CURL_AUTH \"$GITHUB_API/commits?per_page=6\" 2>/dev/null" | jq -r '.[] | "\(.sha[0:7])|\(.commit.author.date)|\(.commit.message | split("\n")[0])"' 2>/dev/null || echo "")

if [ -z "$RELEASES" ] && [ -z "$COMMITS" ]; then
    echo -e "${RED}Error: Could not fetch data from GitHub API${NC}"
    echo "Make sure you have internet connection and GitHub API is accessible"
    exit 1
fi

echo -e "${GREEN}✓ Fetched successfully${NC}"
echo ""

# Display menu
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}RELEASES:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

declare -A options
declare -A option_shas
declare -a option_order
index=1

# Process releases/tags
if [ -n "$RELEASES" ]; then
    while IFS='|' read -r version date sha; do
        # Skip empty lines
        [ -z "$version" ] && continue

        # Format date (handle null from tags API)
        if [ "$date" == "null" ] || [ -z "$date" ]; then
            readable_date="(tag)"
            sha_str=""
        else
            readable_date=$(date -d "$date" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$date")
            sha_str="$sha"
        fi

        # Use letters for releases (a, b, c, d, e, f, g, h, j)
        letter=$(echo -n "abcdefghj" | cut -c$index)

        options[$letter]="$version"
        option_shas[$letter]="$sha"
        option_order+=("$letter")

        # Format: [a] Release_1.941 f9b0ced 2026-03-29 04:24
        printf "  ${CYAN}%-3s${NC} %-24s %s ${YELLOW}%s${NC}\n" "[$letter]" "$version" "$sha_str" "$readable_date"

        index=$((index + 1))
        [ $index -gt 9 ] && break  # Max 9 letters
    done <<< "$RELEASES"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}RECENT COMMITS:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

commit_index=1

if [ -n "$COMMITS" ]; then
    while IFS='|' read -r sha date message; do
        # Format date
        readable_date=$(date -d "$date" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$date")

        # Truncate message
        msg_short="${message:0:35}"
        [ ${#message} -gt 35 ] && msg_short="${msg_short}..."

        # Use numbers for commits (1, 2, 3, etc)
        options[$commit_index]="$sha"
        option_shas[$commit_index]="$sha"
        option_order+=("$commit_index")

        printf "  ${CYAN}%-3s${NC} %-10s ${YELLOW}%s${NC} ${GREEN}%s${NC}\n" "[$commit_index]" "$sha" "$readable_date" "$msg_short"

        commit_index=$((commit_index + 1))
    done <<< "$COMMITS"
fi

# Add branch option
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}BRANCHES:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Get master branch latest commit date and message
MASTER_INFO=$(eval "curl -s $CURL_AUTH \"$GITHUB_API/commits?sha=master&per_page=1\" 2>/dev/null" | jq -r '.[0] | "\(.commit.author.date)|\(.commit.message | split("\n")[0])"' 2>/dev/null || echo "")

if [ -n "$MASTER_INFO" ]; then
    IFS='|' read -r master_date master_msg <<< "$MASTER_INFO"
    master_readable=$(date -d "$master_date" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$master_date")

    # Truncate message if too long
    msg_short="${master_msg:0:30}"
    [ ${#master_msg} -gt 30 ] && msg_short="${msg_short}..."

    # Get master commit SHA
    MASTER_SHA=$(eval "curl -s $CURL_AUTH \"$GITHUB_API/commits?sha=master&per_page=1\" 2>/dev/null" | jq -r '.[0].sha[0:7]' 2>/dev/null || echo "")
    printf "  ${CYAN}%-3s${NC} %-24s %s ${YELLOW}%s${NC}\n" "[m]" "master" "$MASTER_SHA" "$master_readable"
    option_shas["m"]="$MASTER_SHA"
else
    printf "  ${CYAN}%-3s${NC} %-24s\n" "[m]" "master"
fi

options["m"]="master"
option_order+=("m")

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Set default to latest (master branch)
DEFAULT_OPTION="m"
DEFAULT_VERSION="${options[$DEFAULT_OPTION]}"

# Get user input
while true; do
    echo -n -e "${YELLOW}Select version to build ${NC}(${CYAN}a-m, 1-${commit_index}${NC}, or Enter for master): "
    read -r selection

    # Use default if user just presses Enter
    if [ -z "$selection" ]; then
        selection="$DEFAULT_OPTION"
    fi

    if [ -z "${options[$selection]}" ]; then
        echo -e "${RED}Invalid selection. Try again.${NC}"
        continue
    fi

    SELECTED_VERSION="${options[$selection]}"
    SELECTED_SHA="${option_shas[$selection]}"
    break
done

# Determine image tag based on selection
# For commits (numeric selection), use fingerprint
# For releases/master (letter/m), use the version name
if [[ "$selection" =~ ^[0-9]+$ ]]; then
    # Numeric selection = commit fingerprint
    IMAGE_TAG="$SELECTED_VERSION"
else
    # Letter/m selection = release name or master
    if [ "$SELECTED_VERSION" == "master" ]; then
        IMAGE_TAG="master"
    else
        # Release name like Release_1.941
        IMAGE_TAG="$SELECTED_VERSION"
    fi
fi

# Get platform tag from selection
PLATFORM_TAG="${platform_tags[$variant_choice]}"

# Build full image name
if [ -z "$PLATFORM_TAG" ]; then
    FULL_IMAGE_NAME="yacy:$IMAGE_TAG"
else
    FULL_IMAGE_NAME="yacy:$PLATFORM_TAG-$IMAGE_TAG"
fi

# Get build date
BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

echo ""
echo -e "${GREEN}✓ Selected Version: $SELECTED_VERSION${NC}"
echo -e "${GREEN}✓ Selected Variant: $VARIANT_NAME${NC}"
echo -e "${GREEN}✓ Image Tag: $FULL_IMAGE_NAME${NC}"
echo -e "${GREEN}✓ Build Date: $BUILD_DATE${NC}"

# Show what will be built
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Building Docker image...${NC}"
echo -e "${CYAN}Repository: $GITHUB_REPO${NC}"
echo -e "${CYAN}Version: $SELECTED_VERSION${NC}"
echo -e "${CYAN}Variant: $VARIANT_NAME${NC}"
echo -e "${CYAN}Image Tag: $FULL_IMAGE_NAME${NC}"
echo -e "${CYAN}Build Date: $BUILD_DATE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Build
cd "$PROJECT_DIR"
docker build \
    --build-arg YACY_VERSION="$SELECTED_VERSION" \
    --build-arg YACY_SHA="$SELECTED_SHA" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    -f "$SELECTED_DOCKERFILE" \
    -t "$FULL_IMAGE_NAME" \
    -t "yacy:latest" \
    .

BUILD_EXIT=$?

echo ""
if [ $BUILD_EXIT -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo ""
    echo "Image details:"
    docker image inspect "$FULL_IMAGE_NAME" \
        | jq -r '.[0].Config.Labels | to_entries[] | "  \(.key): \(.value)"' \
        | grep -E "(version|created|source)" || true

    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  1. Start service: ${YELLOW}docker compose up -d${NC}"
    echo -e "  2. Check status: ${YELLOW}docker compose ps${NC}"
    echo -e "  3. Access YaCy: ${YELLOW}https://yacy.yourdomain.com${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi
