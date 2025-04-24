set -xe

glslc ./shaders/shader3D.vert -o ./shaders/vert3D.spv
glslc ./shaders/shader3D.frag -o ./shaders/frag3D.spv

glslc ./shaders/shader2D.vert -o ./shaders/vert2D.spv
glslc ./shaders/shader2D.frag -o ./shaders/frag2D.spv

pushd .

cd ./code

compiler=../Odin/odin
collection="-collection:simple_hash=simple_hash -collection:xtce_parser=xtce_parser"
compilation_mode=" build ."
output_name="-out:OrbitMCS"

if [[ "$1" == "valgrind" ]]; then 
  compilation_mode="$compilation_mode -debug"
elif [[ "$1" == "release" ]]; then 
  compilation_mode="$compilation_mode -o:speed"
elif [[ "$1" == "debug" ]]; then 
  compilation_mode="$compilation_mode -debug"
elif [[ "$1" == "speed" ]]; then 
  compilation_mode="$compilation_mode -sanitize:address"
else 
  echo 
fi

$compiler $compilation_mode $output_name $collection

popd

if [[ "$1" == "valgrind" ]]; then 
  sh ./valgrind.sh
fi

rm -f ./NEW_ORBIT_LOG


