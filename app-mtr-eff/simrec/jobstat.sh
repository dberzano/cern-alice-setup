#!/bin/bash
#watch -n1 'echo -n "Jobs running: " ; qstat | cut -b69-69 | sort | egrep -v -- "[-S]" | grep -c R ; echo -n "Jobs queued:  " ; qstat | cut -b69-69 | sort | grep -c Q ;'
watch -n1 'showq|tail -n1'
