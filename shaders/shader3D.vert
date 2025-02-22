#version 450

layout( binding = 1 ) uniform UniformBuffer {
    float width;
    float height;
    float fov;
    float zNear;
    float zFar;
    mat4  proj;
} ubo;

layout( location = 0 ) in vec3 inPos;
layout( location = 1 ) in vec3 inColor;
layout( location = 2 ) in vec2 inTex;

layout( location = 0 ) out vec3 fragColor;
layout( location = 1 ) out vec2 fragTexCoord;

void
main()
{        
    gl_Position  = ubo.proj * vec4(inPos, 1.0f);
    fragColor    = inColor.rgb * vec3(inTex, 1.0f);
    fragTexCoord = inTex;
}
