#!/bin/bash

source lib/maas.sh

for i in s02 s03 s04
do
    maas_release $i
done
