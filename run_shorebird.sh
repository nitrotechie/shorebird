#!/bin/bash

# Shorebird Self-Hosted Startup Script
# This script starts the infrastructure, backend API, and web console.

# Color constants for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Shorebird Self-Hosted Ecosystem...${NC}"

# Function to cleanup background processes on exit
cleanup() {
    echo -e "\n${YELLOW}Stopping background services...${NC}"
    kill $(jobs -p) 2>/dev/null
    exit
}

trap cleanup SIGINT SIGTERM

# 1. Start Infrastructure (Docker)
echo -e "${YELLOW}[1/4] Starting Docker infrastructure (PostgreSQL, MinIO)...${NC}"
cd shorebird-backend
docker-compose up -d
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to start Docker containers. Ensure Docker is running.${NC}"
    exit 1
fi

# 2. Prepare and Start Backend
echo -e "${YELLOW}[2/4] Initializing and starting Backend API...${NC}"
if [ ! -d "node_modules" ]; then
    echo "Installing backend dependencies..."
    npm install
fi

# Start backend in background
npm run dev > ../backend.log 2>&1 &
BACKEND_PID=$!

# Wait for backend to be ready
echo -n "Waiting for backend to initialize..."
for i in {1..30}; do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
    if [ $i -eq 30 ]; then
        echo -e "\n${RED}Backend failed to start within 30 seconds. Check backend.log${NC}"
        cleanup
    fi
done

# 3. Prepare and Start Console
echo -e "${YELLOW}[3/4] Initializing and starting Web Console...${NC}"
cd ../shorebird-console
if [ ! -d "node_modules" ]; then
    echo "Installing console dependencies..."
    npm install
fi

# Start console in background on port 3001
PORT=3001 npm run dev > ../console.log 2>&1 &
CONSOLE_PID=$!

# Wait for console to be ready
echo -n "Waiting for console to initialize..."
for i in {1..30}; do
    if curl -s http://localhost:3001/ > /dev/null; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
    if [ $i -eq 30 ]; then
        echo -e "\n${RED}Console failed to start within 30 seconds. Check console.log${NC}"
        cleanup
    fi
done

# 4. Success Summary
echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}   Shorebird Self-Hosted is now RUNNING!      ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "${BLUE}Web Console:${NC} http://localhost:3001"
echo -e "${BLUE}Backend API:${NC} http://localhost:3000"
echo -e "${BLUE}MinIO UI:   ${NC} http://localhost:9001 (shorebird_admin / shorebird_secret_password)"
echo -e "${BLUE}PostgreSQL: ${NC} localhost:5433 (postgres / postgres)"
echo -e "${GREEN}==============================================${NC}"
echo -e "${YELLOW}CLI Configuration:${NC}"
echo -e "  export SHOREBIRD_HOSTED_URL=\"http://localhost:3000\""
echo -e "  export AUTH_SERVICE_URL=\"http://localhost:3000\""
echo -e "  export FLUTTER_STORAGE_BASE_URL=\"http://localhost:8080\""
echo -e "\n${YELLOW}Press Ctrl+C to stop all services.${NC}"

# Keep script running to maintain background processes
wait
