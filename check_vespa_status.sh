#!/bin/bash
# Script to check Vespa status and connectivity with background server on EC2

echo "=========================================="
echo "Vespa Status Check for EC2 Machine"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Check if Vespa container is running
echo "1. Checking if Vespa container is running..."
if docker ps | grep -q "vespa\|index"; then
    echo -e "${GREEN}✓ Vespa container is running${NC}"
    docker ps | grep -E "vespa|index|CONTAINER"
else
    echo -e "${RED}✗ Vespa container is NOT running${NC}"
    echo "   Checking all containers..."
    docker ps -a | grep -E "vespa|index"
fi
echo ""

# 2. Check Vespa health endpoint
echo "2. Checking Vespa health endpoint..."
VESPA_HOST=${VESPA_HOST:-localhost}
VESPA_PORT=${VESPA_PORT:-8081}

# Try to get VESPA_HOST from docker-compose if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/deployment/docker_compose/.env" ]; then
    source "$SCRIPT_DIR/deployment/docker_compose/.env" 2>/dev/null || true
elif [ -f "deployment/docker_compose/.env" ]; then
    source deployment/docker_compose/.env 2>/dev/null || true
fi

# If running in docker-compose, try to get container name
VESPA_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "index|vespa" | head -1)

if [ -n "$VESPA_CONTAINER" ]; then
    echo "   Found Vespa container: $VESPA_CONTAINER"
    echo "   Checking health endpoint inside container..."
    
    HEALTH_CHECK=$(docker exec $VESPA_CONTAINER curl -s http://localhost:8081/state/v1/health 2>/dev/null)
    if [ $? -eq 0 ] && echo "$HEALTH_CHECK" | grep -q '"code":"up"'; then
        echo -e "${GREEN}✓ Vespa health check passed${NC}"
        echo "$HEALTH_CHECK" | python3 -m json.tool 2>/dev/null || echo "$HEALTH_CHECK"
    else
        echo -e "${RED}✗ Vespa health check failed${NC}"
        echo "   Response: $HEALTH_CHECK"
    fi
else
    echo "   Attempting direct connection to $VESPA_HOST:$VESPA_PORT..."
    HEALTH_CHECK=$(curl -s http://${VESPA_HOST}:${VESPA_PORT}/state/v1/health 2>/dev/null)
    if [ $? -eq 0 ] && echo "$HEALTH_CHECK" | grep -q '"code":"up"'; then
        echo -e "${GREEN}✓ Vespa health check passed${NC}"
        echo "$HEALTH_CHECK" | python3 -m json.tool 2>/dev/null || echo "$HEALTH_CHECK"
    else
        echo -e "${RED}✗ Cannot reach Vespa at $VESPA_HOST:$VESPA_PORT${NC}"
        echo "   Response: $HEALTH_CHECK"
    fi
fi
echo ""

# 3. Check background server container status
echo "3. Checking background server container status..."
BACKGROUND_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "background" | head -1)

if [ -n "$BACKGROUND_CONTAINER" ]; then
    echo -e "${GREEN}✓ Background server container is running: $BACKGROUND_CONTAINER${NC}"
    
    # Check if background server is healthy
    echo "   Checking background server logs for Vespa connection..."
    echo "   (Last 20 lines related to Vespa)"
    docker logs $BACKGROUND_CONTAINER 2>&1 | grep -i vespa | tail -20 || echo "   No Vespa-related logs found"
else
    echo -e "${RED}✗ Background server container is NOT running${NC}"
fi
echo ""

# 4. Check Vespa connectivity from background server
echo "4. Testing Vespa connectivity from background server container..."
if [ -n "$BACKGROUND_CONTAINER" ]; then
    # Get VESPA_HOST from background container environment
    VESPA_HOST_IN_CONTAINER=$(docker exec $BACKGROUND_CONTAINER printenv VESPA_HOST 2>/dev/null || echo "index")
    VESPA_PORT_IN_CONTAINER=$(docker exec $BACKGROUND_CONTAINER printenv VESPA_PORT 2>/dev/null || echo "8081")
    
    echo "   VESPA_HOST in background container: $VESPA_HOST_IN_CONTAINER"
    echo "   VESPA_PORT in background container: $VESPA_PORT_IN_CONTAINER"
    
    # Test connectivity
    TEST_URL="http://${VESPA_HOST_IN_CONTAINER}:${VESPA_PORT_IN_CONTAINER}/state/v1/health"
    echo "   Testing: $TEST_URL"
    
    HEALTH_RESPONSE=$(docker exec $BACKGROUND_CONTAINER curl -s $TEST_URL 2>/dev/null)
    if [ $? -eq 0 ] && echo "$HEALTH_RESPONSE" | grep -q '"code":"up"'; then
        echo -e "${GREEN}✓ Background server can reach Vespa${NC}"
    else
        echo -e "${RED}✗ Background server CANNOT reach Vespa${NC}"
        echo "   Response: $HEALTH_RESPONSE"
    fi
else
    echo -e "${YELLOW}⚠ Cannot test - background server container not running${NC}"
fi
echo ""

# 5. Check Vespa application status
echo "5. Checking Vespa application status..."
if [ -n "$VESPA_CONTAINER" ]; then
    VESPA_TENANT_PORT=$(docker exec $VESPA_CONTAINER printenv VESPA_TENANT_PORT 2>/dev/null || echo "19071")
    APP_STATUS=$(docker exec $VESPA_CONTAINER curl -s http://localhost:${VESPA_TENANT_PORT}/application/v2/tenant/default/application/default 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Vespa application endpoint is accessible${NC}"
        echo "$APP_STATUS" | python3 -m json.tool 2>/dev/null | head -30 || echo "$APP_STATUS" | head -10
    else
        echo -e "${RED}✗ Cannot access Vespa application endpoint${NC}"
    fi
fi
echo ""

# 6. Check recent background server logs for Vespa errors
echo "6. Checking background server logs for Vespa connection errors..."
if [ -n "$BACKGROUND_CONTAINER" ]; then
    echo "   Recent errors/warnings (last 50 lines):"
    docker logs $BACKGROUND_CONTAINER 2>&1 | tail -50 | grep -iE "vespa|error|failed|timeout" || echo "   No recent Vespa errors found"
else
    echo -e "${YELLOW}⚠ Background server container not running${NC}"
fi
echo ""

# 7. Network connectivity check
echo "7. Checking Docker network connectivity..."
if [ -n "$VESPA_CONTAINER" ] && [ -n "$BACKGROUND_CONTAINER" ]; then
    # Check if they're on the same network
    VESPA_NETWORK=$(docker inspect $VESPA_CONTAINER --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{end}}' | head -1)
    BACKGROUND_NETWORK=$(docker inspect $BACKGROUND_CONTAINER --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}}{{end}}' | head -1)
    
    if [ "$VESPA_NETWORK" = "$BACKGROUND_NETWORK" ]; then
        echo -e "${GREEN}✓ Both containers are on the same network: $VESPA_NETWORK${NC}"
    else
        echo -e "${YELLOW}⚠ Containers are on different networks${NC}"
        echo "   Vespa: $VESPA_NETWORK"
        echo "   Background: $BACKGROUND_NETWORK"
    fi
    
    # Test ping from background to vespa
    VESPA_IP=$(docker inspect $VESPA_CONTAINER --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' | head -1)
    if [ -n "$VESPA_IP" ]; then
        echo "   Testing ping from background server to Vespa IP: $VESPA_IP"
        PING_RESULT=$(docker exec $BACKGROUND_CONTAINER ping -c 2 $VESPA_IP 2>&1)
        if echo "$PING_RESULT" | grep -q "2 received"; then
            echo -e "${GREEN}✓ Network connectivity OK${NC}"
        else
            echo -e "${RED}✗ Network connectivity issue${NC}"
        fi
    fi
fi
echo ""

# 8. Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
VESPA_RUNNING=$(docker ps | grep -q "vespa\|index" && echo "YES" || echo "NO")
BACKGROUND_RUNNING=$(docker ps | grep -q "background" && echo "YES" || echo "NO")

echo "Vespa Container: $VESPA_RUNNING"
echo "Background Server: $BACKGROUND_RUNNING"

if [ "$VESPA_RUNNING" = "YES" ] && [ "$BACKGROUND_RUNNING" = "YES" ]; then
    echo -e "${GREEN}Both services are running. Check health endpoints above for connectivity.${NC}"
else
    echo -e "${RED}One or more services are not running. Please check Docker containers.${NC}"
fi
echo ""
echo "For more detailed checks, run:"
echo "  python backend/scripts/debugging/onyx_vespa.py --action connect"
echo ""

