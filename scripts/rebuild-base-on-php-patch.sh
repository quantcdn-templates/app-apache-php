#!/usr/bin/env bash
# rebuild-base-on-php-patch.sh — rapid-response base-image rebuild for the PHP
# security release (CVE-2026-109618 / CVE-2026-109619, session.upload_progress RCE).
#
# This image's Dockerfile floats the minor tag (FROM php:${PHP_VERSION}-apache-trixie),
# so NO Dockerfile change is needed — a rebuild pulls the patched PHP automatically.
#
# PRECONDITION: docker-library has published the patched php:8.4.x-apache-trixie
# (and 8.3/8.2). Confirm before rebuilding, else you rebuild on the OLD php:
#   docker buildx imagetools inspect php:8.4-apache-trixie --format '{{json .Config.Labels}}' | tr ',' '\n' | grep -i version
#   # or check https://hub.docker.com/_/php tags for 8.4.27 etc.
#
# Steps:
#   1. Trigger the matrix rebuild (8.2/8.3/8.4/7.4) on main.
#   2. When green, read the NEW published digests — these are what portal and
#      apexwise bump to (scripts/php-patch-bump.sh sha256:<digest> in each).
set -euo pipefail

echo "==> Triggering app-apache-php CI rebuild on main ..."
gh workflow run ci.yml -R quantcdn-templates/app-apache-php --ref main
echo "    (watch: gh run watch \"\$(gh run list -R quantcdn-templates/app-apache-php --limit 1 --json databaseId -q '.[0].databaseId')\" -R quantcdn-templates/app-apache-php)"
echo
echo "==> When the run is GREEN, read the new digests for downstream bumps:"
for v in 8.2 8.3 8.4; do
  printf '  %-4s -> ' "$v"
  docker buildx imagetools inspect "ghcr.io/quantcdn-templates/app-apache-php:$v" \
    --format '{{.Manifest.Digest}}' 2>/dev/null || echo '(available after the rebuild publishes)'
done
echo
echo "Then in portal and apexwise:  scripts/php-patch-bump.sh <the 8.4 digest above>"
echo "Downstream templates (drupal/wordpress/laravel/...) float the :8.4 tag —"
echo "rebuild each (CI / empty commit) to pick up the patched base."
