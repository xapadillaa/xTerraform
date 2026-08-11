#!/bin/bash
    apt-get update -y
    apt-get install busybox -y

    mkdir -p /var/www
    echo "Hello from BusyBox!" > /var/www/index.html
    
    nohub busybox -f -h /var/www -p ${var.server_port} -v