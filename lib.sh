#!/bin/bash

### Library with helper functions.

function check_dependency {
    ## Checks that dependency is installed, otherwise exits.

    local dep=$1

    if ! command -v $dep &> /dev/null
    then
        echo "${dep} is missing"
        echo "\$ sudo apt-get install ${dep}"
        exit 1
    fi
}
