#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Starting port-forward to OpenClaw..."
echo ""
echo "Access OpenClaw at: http://localhost:18789"
echo ""
echo "Press Ctrl+C to stop"
echo ""

oc port-forward -n openclaw svc/openclaw 18789:18789
