#!/usr/bin/python
from requests import get
from time import sleep
fields = [ "name",
           "tasks_waiting", "tasks_running",
           "workers_idle", "workers_busy" ]
while True:
  j = get("http://wqcatalog.marathon.mesos:9097/query.json").json()
  for i in j:
    for f in fields:
      print "%s = %s" % (f, i[f]),
    print
    sleep(2)
