#!/bin/bash

CMDS="cmds"

cd app
make
tar -cvf fs.img `cat $CMDS`
mv fs.img ../fs.img
cd ..
