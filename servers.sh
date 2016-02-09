#!/bin/sh
influx -port 8186 -execute "show servers"
