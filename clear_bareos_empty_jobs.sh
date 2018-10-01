#!/bin/bash

echo delete jobid=$(sudo -u bareos psql -A -t -R "," -c "select jobid from Job where JobBytes=0 and JobFiles=0 and (JobStatus='T' or JobStatus='f' or JobStatus='A' or JobStatus='E') order by jobid;") | bconsole

