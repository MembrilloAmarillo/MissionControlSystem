#version 450

//layout(binding = 2) uniform sampler2D texSampler;

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;


void
main()
{
    //vec3 coord = vec3(gl_FragCoord.x, gl_FragCoord.y, gl_FragCoord.z);
	//OutColor   = fragColor;
    
    outColor = vec4(fragColor, 1.0);
    //outColor = vec4( texture( texSampler, fragTexCoord ).rrr, 1.0f );
}
