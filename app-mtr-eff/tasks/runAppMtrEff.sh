#!/bin/bash
aliroot -q runAppMtrEff.C 2>&1 | tee ana.log
exit ${PIPESTATUS[0]}
