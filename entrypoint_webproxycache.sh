#!/bin/sh
set -e

# Initialize Squid cache directories if they don't exist
if [ ! -d /var/spool/squid/00 ]; then
    echo "Initializing squid cache directories..."
    #squid -N -f /etc/squid/squid.conf -z
    squid -z
    sleep 3
fi

# Initialize SSL database for SSL bumping if it doesn't exist
if [ ! -d /var/spool/squid/ssl_db ]; then
    echo "Initializing squid SSL database..."
    /usr/lib/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 4MB
    chown -R squid:squid /var/spool/squid/ssl_db
fi

# Start Squid
exec squid -N -d 1 -f /etc/squid/squid.conf
