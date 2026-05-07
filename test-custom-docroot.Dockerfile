FROM test-apache-php:latest

# Test custom document root
ENV DOCUMENT_ROOT=/opt/custom/web
RUN /quant/set-document-root.sh
