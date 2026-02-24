#!/bin/bash

# Test script to inject vulnerable dependency and verify quality gates

echo "🧪 Testing Security Quality Gates"
echo "================================="

# Backup original package.json
cp package.json package.json.backup

echo "📦 Injecting vulnerable dependency (lodash 4.17.15 - known CVE)..."

# Add vulnerable dependency
npm install lodash@4.17.15 --save

echo "🔍 Running security scans..."

# Test 1: npm audit should fail
echo "Testing npm audit..."
npm audit --audit-level=high
AUDIT_EXIT=$?

if [ $AUDIT_EXIT -eq 0 ]; then
    echo "❌ npm audit should have failed but passed"
else
    echo "✅ npm audit correctly detected vulnerabilities"
fi

# Test 2: Snyk should fail (if token available)
if [ ! -z "$SNYK_TOKEN" ]; then
    echo "Testing Snyk..."
    npx snyk test --severity-threshold=high
    SNYK_EXIT=$?
    
    if [ $SNYK_EXIT -eq 0 ]; then
        echo "❌ Snyk should have failed but passed"
    else
        echo "✅ Snyk correctly detected vulnerabilities"
    fi
fi

echo "🔧 Restoring original package.json..."
mv package.json.backup package.json
npm install

echo "✅ Testing complete - Quality gates should block vulnerable deployments"