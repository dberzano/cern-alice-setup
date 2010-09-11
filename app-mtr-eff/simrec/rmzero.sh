#!/bin/bash
find . -size 0 -maxdepth 1 -exec rm -f '{}' \;
