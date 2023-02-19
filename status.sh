#!/bin/bash
sudo sed -i "s/host/$(hostname)/"  /app/exporter/filename.yml
