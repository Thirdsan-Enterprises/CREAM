#!/bin/sh
# Runs the whole manual, start to finish, through the real app on a fresh database.
# See ../README.md for setup. Screenshots land in ./shots.
cd "$(dirname "$0")"
set -e
mkdir -p shots
( cd ../../../backend && php artisan migrate:fresh --seed --force >/dev/null 2>&1 ) && echo "database reset"
for p in partA partB partE partC partE2 partD partG partH; do
  printf "%s: " "$p"
  node $p.js > "/tmp/walkthrough-$p.out" 2>&1 && echo ok || { echo FAILED; tail -5 "/tmp/walkthrough-$p.out"; exit 1; }
done
echo "ALL PARTS PASSED"
