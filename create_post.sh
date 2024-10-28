#!/bin/bash
# A silly script to automatize post creation a bit.

function create_post(){
  if [ $# -lt 2 ]; then 
    echo "usage: $0 <type> <name>"
    return 1
  fi

  date=$(date +"%Y-%m-%d")
  name=$(echo "${@:2}" | sed -e "s/ /_/g")
  filename=$(echo "$date-$name")

  if [ ! -d "./_posts/${1}s" ]; then
     echo "error: specified post type $1 doesn't exists."
     return 1
  fi

  echo "Adding post $filename..."  
  cp "./templates/$1.markdown" "./_posts/${1}s/$filename.markdown"
  echo "Done"
}

create_post $@
