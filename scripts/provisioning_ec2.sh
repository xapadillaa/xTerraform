#!/bin/bash
    
    # this script works for ubuntu/debian 

    apt-get update -y
    apt-get install -y apache2

    systemctl enable --now apache2
    
    echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
