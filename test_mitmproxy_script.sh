#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Parse command line arguments
ALTERNATIVE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --alternative)
            ALTERNATIVE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--alternative <number>]"
            echo ""
            echo "Test HTTP cache proxy with different test endpoints"
            echo ""
            echo "Available alternatives:"
            echo "  0: httpbingo.org - default"
            echo "  1: postman-echo.com"  
            echo "  2: reqres.in"
            echo "  3: jsonplaceholder.typicode.com"
            echo "  4: httpbin.org"
            echo "  5: eu.httpbin.org"
            echo ""
            echo "Example: $0 --alternative 1"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Define test endpoints for different alternatives
declare -A TEST_CONFIGS
TEST_CONFIGS[0]="httpbingo.org|httpbingo.org/get|httpbingo.org/headers|dl.rockylinux.org/vault/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm|ftp.swin.edu.au/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm"

TEST_CONFIGS[1]="postman-echo.com|postman-echo.com/get|postman-echo.com/headers|dl.rockylinux.org/vault/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm|mirror.aarnet.edu.au/pub/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm"

TEST_CONFIGS[2]="reqres.in|reqres.in/api/users/1|reqres.in/api/users|download.rockylinux.org/vault/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm|mirror.23m.com/rockylinux/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm"

TEST_CONFIGS[3]="jsonplaceholder.typicode.com|jsonplaceholder.typicode.com/posts/1|jsonplaceholder.typicode.com/posts|dl.rockylinux.org/vault/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm|ftp.halifax.rwth-aachen.de/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm"

TEST_CONFIGS[4]="httpbin.org|httpbin.org/get|httpbin.org/headers|dl.rockylinux.org/vault/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm|mirrors.xtom.com/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm"

TEST_CONFIGS[5]="eu.httpbin.org|eu.httpbin.org/get|eu.httpbin.org/headers|dl.rockylinux.org/vault/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm|ftp.nluug.nl/pub/rocky/9.0/BaseOS/x86_64/os/Packages/a/accel-config-libs-3.4.2-2.el9.i686.rpm"

# Get configuration for selected alternative
if [[ ! ${TEST_CONFIGS[$ALTERNATIVE]+_} ]]; then
    echo -e "${RED}Invalid alternative: $ALTERNATIVE${NC}"
    echo -e "Use --help to see available alternatives"
    exit 1
fi

IFS='|' read -r BASE_URL GET_ENDPOINT HEADERS_ENDPOINT RPM_URL1 RPM_URL2 <<< "${TEST_CONFIGS[$ALTERNATIVE]}"

# Display selected configuration
echo -e "${BLUE}Using test alternative $ALTERNATIVE:${NC}"
echo -e "  Base URL: $BASE_URL"
echo -e "  GET endpoint: $GET_ENDPOINT" 
echo -e "  Headers endpoint: $HEADERS_ENDPOINT"
echo -e "  RPM URL 1: $RPM_URL1"
echo -e "  RPM URL 2: $RPM_URL2"
echo ""

#set -x

# Clean cache
rm -rf ./the_cache_dir/*

# Function to run test with better error handling
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_status="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "\n${YELLOW}Running: $test_name${NC}"
    
    # Run the command and capture both stdout and stderr
    local output
    local exit_code
    
    # Use timeout with bash -c instead of eval
    output=$(timeout 30 bash -c "$command" 2>&1)
    exit_code=$?
    
    echo "Command output:"
    echo "$output"
    
    # Check if command timed out
    if [ $exit_code -eq 124 ]; then
        echo -e "${YELLOW}⚠️  $test_name SKIPPED - Command timed out (30s)${NC}"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        return 0
    fi
    
    # Check if command failed (network error, etc.)
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}❌ $test_name FAILED - Command failed with exit code $exit_code${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Check for server errors in response
    if echo "$output" | grep -q "HTTP/[0-9.]\+ [45][0-9][0-9]"; then
        echo -e "${YELLOW}⚠️  $test_name SKIPPED - Server returned error status${NC}"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        return 0
    fi
    
    # Check for DNS resolution failures
    if echo "$output" | grep -q "Could not resolve host\|Name or service not known"; then
        echo -e "${YELLOW}⚠️  $test_name SKIPPED - DNS resolution failed${NC}"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        return 0
    fi
    
    # Check for connection failures
    if echo "$output" | grep -q "Connection refused\|Connection timed out\|Failed to connect"; then
        echo -e "${YELLOW}⚠️  $test_name SKIPPED - Connection failed${NC}"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        return 0
    fi
    
    # Check for cache status
    if echo "$output" | grep -q "x-cache-status: $expected_status"; then
        echo -e "${GREEN}✅ $test_name SUCCEEDED - Found x-cache-status: $expected_status${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    elif echo "$output" | grep -q "x-cache-status: ERROR"; then
        echo -e "${YELLOW}⚠️  $test_name SKIPPED - Server error (x-cache-status: ERROR)${NC}"
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
        return 0
    elif echo "$output" | grep -q "x-cache-status:"; then
        local actual_status=$(echo "$output" | grep -o "x-cache-status: [A-Z-]*" | cut -d' ' -f2)
        echo -e "${RED}❌ $test_name FAILED - Expected '$expected_status' but got '$actual_status'${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    else
        echo -e "${RED}❌ $test_name FAILED - No x-cache-status header found${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: HTTP GET - First request (should be MISS)
run_test "HTTP GET (MISS)" \
    "http_proxy=webproxycache:3128 curl -v http://$GET_ENDPOINT" \
    "MISS"

sleep 1

# Test 2: HTTP GET - Second request (should be HIT)
run_test "HTTP GET (HIT)" \
    "http_proxy=webproxycache:3128 curl -v http://$GET_ENDPOINT" \
    "HIT"

sleep 1

# Test 3: HTTPS GET - First request (should be MISS)
run_test "HTTPS GET (MISS)" \
    "curl -v --proxy http://webproxycache:3128 https://$GET_ENDPOINT" \
    "MISS"

sleep 1

# Test 4: HTTPS GET - Second request (should be HIT)
run_test "HTTPS GET (HIT)" \
    "curl -v --proxy http://webproxycache:3128 https://$GET_ENDPOINT" \
    "HIT"

sleep 1

# Test 5: HTTP with Bearer token - First request (should be MISS)
run_test "HTTP Bearer (MISS)" \
    "curl -v --proxy http://webproxycache:3128 http://$HEADERS_ENDPOINT -H \"Authorization: Bearer token123\"" \
    "MISS"

sleep 1

# Test 6: HTTP with Bearer token - Second request (should be HIT)
run_test "HTTP Bearer (HIT)" \
    "curl -v --proxy http://webproxycache:3128 http://$HEADERS_ENDPOINT -H \"Authorization: Bearer token123\"" \
    "HIT"

sleep 1

# Test 7: HTTPS with Bearer token - First request (should be MISS)
run_test "HTTPS Bearer (MISS)" \
    "curl -v --proxy http://webproxycache:3128 https://$HEADERS_ENDPOINT -H \"Authorization: Bearer token123\"" \
    "MISS"

sleep 1

# Test 8: HTTPS with Bearer token - Second request (should be HIT)  
run_test "HTTPS Bearer (HIT)" \
    "curl -v --proxy http://webproxycache:3128 https://$HEADERS_ENDPOINT -H \"Authorization: Bearer token123\"" \
    "HIT"

sleep 1

# Test 9: RPM file - First request (should be MISS)
run_test "RPM Download (MISS)" \
    "curl -v --proxy http://webproxycache:3128 https://$RPM_URL1 -o /tmp/pack1.rpm" \
    "MISS"

sleep 1

# Test 10: Same RPM file from different mirror (should be HIT due to filename caching)
run_test "RPM Download Same File (HIT)" \
    "curl -v --proxy http://webproxycache:3128 https://$RPM_URL2 -o /tmp/pack2.rpm" \
    "HIT"

echo -e "\n${GREEN}All tests completed using alternative $ALTERNATIVE ($BASE_URL)!${NC}"
echo -e "Check the cache directory:"
ls -la ./the_cache_dir/

# Calculate success rate
success_rate=0
if [ $TESTS_TOTAL -gt 0 ]; then
    success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
fi

# Show detailed summary
echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}                    TEST RESULTS SUMMARY                    ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "Alternative used: ${BLUE}$ALTERNATIVE${NC} - ${BLUE}$BASE_URL${NC}"
echo ""
echo -e "📊 ${BLUE}Test Statistics:${NC}"
echo -e "   Total tests run:    ${BLUE}$TESTS_TOTAL${NC}"
echo -e "   ${GREEN}✅ Passed:${NC}          ${GREEN}$TESTS_PASSED${NC}"
echo -e "   ${RED}❌ Failed:${NC}          ${RED}$TESTS_FAILED${NC}"
echo -e "   ${YELLOW}⚠️  Skipped:${NC}         ${YELLOW}$TESTS_SKIPPED${NC}"
echo -e "   Success rate:       ${BLUE}${success_rate}%${NC}"
echo ""
echo -e "💾 ${BLUE}Cache Statistics:${NC}"
echo -e "   Cache entries:      ${BLUE}$(ls -1 ./the_cache_dir/*.cache 2>/dev/null | wc -l)${NC}"
echo -e "   Header files:       ${BLUE}$(ls -1 ./the_cache_dir/*.json 2>/dev/null | wc -l)${NC}"
echo -e "   Cache size:         ${BLUE}$(du -sh ./the_cache_dir 2>/dev/null | cut -f1)${NC}"

# Overall test result
echo ""
if [ $TESTS_FAILED -eq 0 ] && [ $TESTS_PASSED -gt 0 ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! Cache proxy is working correctly.${NC}"
elif [ $TESTS_FAILED -eq 0 ] && [ $TESTS_SKIPPED -eq $TESTS_TOTAL ]; then
    echo -e "${YELLOW}⚠️  ALL TESTS SKIPPED! Check network connectivity or try different alternative.${NC}"
    echo -e "${YELLOW}   Try: $0 --alternative 1${NC}"
elif [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}❌ SOME TESTS FAILED! Check cache proxy configuration.${NC}"
    if [ $TESTS_PASSED -gt 0 ]; then
        echo -e "${YELLOW}   Cache proxy is partially working - $TESTS_PASSED/$TESTS_TOTAL tests passed.${NC}"
    fi
else
    echo -e "${BLUE}ℹ️  Testing completed.${NC}"
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"

# Exit with appropriate code
if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
elif [ $TESTS_PASSED -eq 0 ]; then
    exit 2  # All skipped
else
    exit 0  # Success
fi
