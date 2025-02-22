set -xe

rm -f ../code/xtce_parser/xtce_type.odin 
touch ../code/xtce_parser/xtce_type.odin 

if [[ "$1" == "debug" ]]; then
  odin build . -debug 
else
  odin build .
fi
