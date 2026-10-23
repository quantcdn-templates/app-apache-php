#!/usr/bin/env bash
# The single-quoted commands run inside the container, so they must not expand
# here (SC2016). cleanup runs through trap (SC2329).
# shellcheck disable=SC2016,SC2329
#
# Checks for the PHP 7.4 image (Dockerfile.php74).
#
# Usage: tests/php74/run-tests.sh <image>
#
# Static checks run commands in a throwaway container. Runtime checks start
# the image the way Quant Cloud does (entrypoint scripts, then Apache) and
# send requests through Apache.
set -uo pipefail

IMAGE=${1:?usage: $0 <image>}
FAILS=0
CID=""

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1${2:+  -> $2}"; FAILS=$((FAILS + 1)); }

# check <name> <shell command run inside a throwaway container>
check() {
  local out
  if out=$(docker run --rm --entrypoint sh "$IMAGE" -c "$2" 2>&1); then
    pass "$1"
  else
    fail "$1" "$(echo "$out" | tail -3 | tr '\n' ' ')"
  fi
}

# expect <name> <expected> <actual>
expect() {
  if [ "$3" = "$2" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}

cleanup() { [ -n "$CID" ] && docker rm -f "$CID" >/dev/null 2>&1; }
trap cleanup EXIT

static_checks() {
  check "PHP is 7.4" 'php -r "exit(PHP_MAJOR_VERSION . \".\" . PHP_MINOR_VERSION === \"7.4\" ? 0 : 1);"'
  check "extensions of the official 7.4 image are loaded" '
    for e in apcu bcmath ctype curl dom exif fileinfo gd iconv imagick intl json mbstring mysqli \
             openssl pdo_mysql pdo_pgsql pdo_sqlite readline redis sockets sodium sqlite3 zip; do
      php -m | grep -qix "$e" || { echo "missing $e"; exit 1; }
    done
    php -m | grep -qx "Zend OPcache"'
  check "extensions the official image did not load stay off" '
    for e in ffi pgsql shmop sysvmsg sysvsem sysvshm xsl calendar gettext; do
      php -m | grep -qix "$e" && { echo "unexpected $e"; exit 1; }
    done; true'
  check "no php.ini is loaded (PHP defaults, as in the official image)" \
    'php --ini | grep -q "Loaded Configuration File: *(none)"'
  check "Apache and CLI both scan /usr/local/etc/php/conf.d" '
    [ "$(readlink /etc/php/7.4/apache2/conf.d)" = /usr/local/etc/php/conf.d ] &&
    [ "$(readlink /etc/php/7.4/cli/conf.d)" = /usr/local/etc/php/conf.d ]'
  check "a php.ini added to \$PHP_INI_DIR is loaded" '
    echo "memory_limit = 77M" > "$PHP_INI_DIR/php.ini" && php -r "exit(ini_get(\"memory_limit\") === \"77M\" ? 0 : 1);"'
  check "sessions use the system temp directory, as in the official image" \
    'php -r "session_start(); exit(dirname(session_save_path() ?: sys_get_temp_dir() . \"/x\") === rtrim(sys_get_temp_dir(), \"/\") && is_file(sys_get_temp_dir() . \"/sess_\" . session_id()) ? 0 : 1);"'
  check "Quant ini files apply" 'php -r "exit(ini_get(\"error_log\") === \"/dev/stderr\" && ini_get(\"zend.assertions\") === \"-1\" ? 0 : 1);"'
  check "/usr/local/bin/php exists" '/usr/local/bin/php -v | grep -q "^PHP 7.4"'
  check "www-data is UID/GID 1000" '[ "$(id -u www-data):$(id -g www-data)" = 1000:1000 ]'
  check "only postdrop keeps a SUID/SGID bit" \
    '[ "$(find / -xdev -perm /6000 -type f 2>/dev/null)" = /usr/sbin/postdrop ]'
  check "libgd3 comes from Debian, not Sury" '! dpkg-query -W -f "\${Version}" libgd3 | grep -q "gbp"'
  check "composer runs" 'composer --version --no-interaction | grep -q "^Composer version 2"'
  check "mail() queues without hanging" 'timeout 20 php -r "exit(mail(\"test@example.com\", \"s\", \"b\") ? 0 : 1);"'
  check "docker-php-ext-configure is accepted" 'docker-php-ext-configure gd --with-freetype --with-jpeg'
  check "docker-php-ext-install adds packaged extensions" \
    'docker-php-ext-install -j4 soap ldap pdo_mysql && php -m | grep -qx soap && php -m | grep -qx ldap'
  check "docker-php-ext-install removes the apt lists it downloaded" \
    'docker-php-ext-install soap >/dev/null 2>&1 && [ -z "$(ls /var/lib/apt/lists | grep -v -e lock -e partial)" ]'
  check "docker-php-ext-enable accepts --ini-name" 'docker-php-ext-enable --ini-name 50-apcu.ini apcu'
  check "docker-php-ext-install fails for an unknown extension" '! docker-php-ext-install not_a_real_extension'
  check "php7.4 packages reinstall cleanly (an upgrade must not trip ucf)" \
    'apt-get update -qq >/dev/null 2>&1 && apt-get install --reinstall -y -qq libapache2-mod-php7.4 php7.4-cli >/dev/null &&
     [ ! -e /etc/php/7.4/cli/php.ini ] && [ ! -e /etc/php/7.4/apache2/php.ini ]'
  check "no Debian updates are pending" \
    'apt-get update -qq >/dev/null 2>&1 && [ -z "$(apt list --upgradable 2>/dev/null | grep -v ^Listing)" ]'
}

# http <path> [curl args...] -> body
http() {
  local path=$1; shift
  curl -s --max-time 10 "$@" "http://127.0.0.1:${PORT}${path}"
}

start_container() {
  CID=$(docker run -d -p 127.0.0.1::80 -e PHP_MEMORY_LIMIT=384M \
    --entrypoint docker-entrypoint.sh "$IMAGE" apache2-foreground)
  PORT=$(docker port "$CID" 80/tcp | head -1 | sed 's/.*://')
  for _ in $(seq 1 30); do
    curl -s -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/" && return 0
    sleep 1
  done
  return 1
}

write_fixtures() {
  docker exec -i "$CID" sh -c 'cat > /var/www/html/t.php' <<'PHP'
<?php
echo implode('|', [
  php_sapi_name(),
  ini_get('memory_limit'),
  $_SERVER['HTTP_HOST'],
  $_SERVER['REMOTE_ADDR'],
  posix_getpwuid(posix_geteuid())['name'],
  opcache_get_status(false) ? 'opcache' : 'no-opcache',
]);
PHP
  docker exec "$CID" sh -c '
    echo "<?php echo \"EXECUTED\";" > /var/www/html/t.phtml
    mkdir -p /var/www/html/h /var/www/html/d
    echo "Header set X-Htaccess-Test on" > /var/www/html/h/.htaccess
    echo ok > /var/www/html/h/index.html
    chown -R www-data:www-data /var/www/html'
}

runtime_checks() {
  if ! start_container; then
    fail "container starts and serves HTTP" "$(docker logs "$CID" 2>&1 | tail -5 | tr '\n' ' ')"
    return
  fi
  pass "container starts and serves HTTP"
  write_fixtures

  IFS='|' read -r sapi mem host addr user opc <<<"$(http /t.php -H 'Quant-Orig-Host: example.test' -H 'Quant-Client-IP: 203.0.113.9')"
  expect "Apache runs PHP through mod_php" "apache2handler" "$sapi"
  expect "entrypoint ini template reaches Apache (PHP_MEMORY_LIMIT)" "384M" "$mem"
  expect "Quant-Orig-Host rewrites the Host header" "example.test" "$host"
  expect "Quant-Client-IP sets the client address" "203.0.113.9" "$addr"
  expect "PHP runs as www-data" "www-data" "$user"
  expect "OPcache is on in Apache" "opcache" "$opc"

  local body
  body=$(http /t.phtml)
  if [ "$body" = "EXECUTED" ]; then fail ".phtml files are not executed" "it was executed"; else pass ".phtml files are not executed"; fi
  expect "directory listing is off" "403" "$(http /d/ -o /dev/null -w '%{http_code}')"
  expect ".htaccess is honoured (AllowOverride All)" "on" \
    "$(http /h/ -D - -o /dev/null | tr -d '\r' | awk -F': ' 'tolower($1)=="x-htaccess-test"{print $2}')"
  local logged=0
  for _ in $(seq 1 10); do
    docker logs "$CID" 2>/dev/null | grep -q '"GET /t.php' && { logged=1; break; }
    sleep 1
  done
  if [ "$logged" = 1 ]; then pass "access log goes to stdout"; else fail "access log goes to stdout"; fi

  local t0=$SECONDS
  docker stop -t 20 "$CID" >/dev/null
  if [ $((SECONDS - t0)) -lt 10 ]; then pass "container stops gracefully"; else fail "container stops gracefully" "took $((SECONDS - t0))s"; fi
}

docroot_check() {
  local cid port body
  cid=$(docker run -d -p 127.0.0.1::80 -e DOCUMENT_ROOT=/var/www/html/public \
    --entrypoint sh "$IMAGE" -c 'mkdir -p /var/www/html/public && echo "<?php echo \"docroot-ok\";" > /var/www/html/public/index.php && exec docker-entrypoint.sh apache2-foreground')
  port=$(docker port "$cid" 80/tcp | head -1 | sed 's/.*://')
  for _ in $(seq 1 30); do
    body=$(curl -s --max-time 2 "http://127.0.0.1:${port}/") && [ -n "$body" ] && break
    sleep 1
  done
  expect "DOCUMENT_ROOT moves the document root" "docroot-ok" "$body"
  docker rm -f "$cid" >/dev/null
}

phpini_apache_check() {
  local cid port body
  cid=$(docker run -d -p 127.0.0.1::80 \
    --entrypoint sh "$IMAGE" -c 'echo "default_socket_timeout = 4321" > "$PHP_INI_DIR/php.ini" && echo "<?php echo ini_get(\"default_socket_timeout\");" > /var/www/html/i.php && exec docker-entrypoint.sh apache2-foreground')
  port=$(docker port "$cid" 80/tcp | head -1 | sed 's/.*://')
  for _ in $(seq 1 30); do
    body=$(curl -s --max-time 2 "http://127.0.0.1:${port}/i.php") && [ -n "$body" ] && break
    sleep 1
  done
  expect "a php.ini added to \$PHP_INI_DIR is loaded by Apache" "4321" "$body"
  docker rm -f "$cid" >/dev/null
}

static_checks
runtime_checks
docroot_check
phpini_apache_check

echo
if [ "$FAILS" -eq 0 ]; then echo "All checks passed"; else echo "$FAILS check(s) failed"; fi
exit $((FAILS > 0))
