FROM test-apache-php:latest

# Just like Drupal - simply set the env var
ENV DOCUMENT_ROOT=/opt/drupal/web

# That's it! The entrypoint will handle the rest
