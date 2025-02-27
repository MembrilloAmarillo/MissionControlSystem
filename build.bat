@echo off

echo "Compiling shaders..."

glslc .\shaders\shader3D.vert -o .\shaders\vert3D.spv
glslc .\shaders\shader3D.frag -o .\shaders\frag3D.spv

glslc .\shaders\shader2D.vert -o .\shaders\vert2D.spv
glslc .\shaders\shader2D.frag -o .\shaders\frag2D.spv
glslc .\shaders\compute.comp  -o .\shaders\compute.spv

pushd .

cd code

IF "%1" == "debug" (
	odin build . -debug -collection:simple_hash=.\simple_hash -collection:xtce_parser=.\xtce_parser
 echo "Debug mode enabled"
) ELSE IF "%1" == "sanitize" (
	odin build . -sanitize:address -collection:simple_hash=.\simple_hash -collection:xtce_parser=.\xtce_parser
 echo "Sanitize mode enabled"
) ELSE IF "%1" == "release" (
	odin build . -o:speed -collection:simple_hash=.\simple_hash -collection:xtce_parser=.\xtce_parser
 echo "Release mode enabled"
) ELSE (
	odin build . -collection:simple_hash=.\simple_hash -collection:xtce_parser=.\xtce_parser
 echo "No optimization mode enabled"
)

popd