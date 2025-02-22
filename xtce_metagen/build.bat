del ..\code\xtce_parser\xtce_type.odin 
type null >> ..\code\xtce_parser\xtce_type.odin 

IF "%1" == "-debug" (
    odin build . -debug 
) ELSE (
    odin build .
)
