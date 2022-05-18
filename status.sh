#!/bin/bash
sudo -s
cd  / 
mkdir app 
cd /app && git clone https://github.com/yuhongwei380/exporter.git
cd /app/expoter/
sudo sed -i "s/host/$(hostname)/"  /app/exporter/filename.yml
cd /app/exporter/ && docker-compose up -d
