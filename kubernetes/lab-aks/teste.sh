#/bin/bash

if [[ $# < 2 ]];
then 
    echo "Missing parameter "
else
    for i in $@
      do 
        echo -e "$i\n"
      done
fi
