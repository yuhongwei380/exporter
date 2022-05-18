#!/bin/bash
sudo mkdir /app 
sudo cd /app && sudo  git clone https://github.com/yuhongwei380/exporter.git
sudo cd /app/expoter/
sudo sed -i "s/host/$(hostname)/"  /app/exporter/filename.yml
cd /app/exporter/ && sudo docker-compose up -d
