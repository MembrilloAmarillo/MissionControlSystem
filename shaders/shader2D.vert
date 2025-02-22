#version 450

layout( binding = 0 ) uniform UniformBuffer {
 float time;
 float deltaTime;
 float width;
 float height;
 float AtlasWidth;
 float AtlasHeight;
} ubo;

layout( location = 0 )  in vec2 v_p0; // top left corner
layout( location = 1 )  in vec2 v_p1; // bottom right corner

layout( location = 2 )  in vec4 inColor00; // Colors for top-left corner
layout( location = 3 )  in vec4 inColor01; // Colors for top-right corner
layout( location = 4 )  in vec4 inColor10; // Colors for lower-left corner
layout( location = 5 )  in vec4 inColor11; // Colors for lower-right corner

layout( location = 6 )  in vec2 in_tex_p0; // top left corner texture
layout( location = 7 )  in vec2 in_tex_p1; // bottom right corner texture
layout( location = 8 )  in float in_corner_radius;
layout( location = 9 )  in float in_edge_softness;
layout( location = 10 ) in float in_border_thickness;

layout( location = 0 ) out vec4  fragColor00;
layout( location = 1 ) out vec4  fragColor01;
layout( location = 2 ) out vec4  fragColor10;
layout( location = 3 ) out vec4  fragColor11;
layout( location = 4 ) out vec2  fragTexCoord;
layout( location = 5 ) out vec2  out_dst_pos;
layout( location = 6 ) out vec2  out_dst_center;
layout( location = 7 ) out vec2  out_dst_half_size;
layout( location = 8 ) out vec2  out_coorner_coord;
layout( location = 9 ) out float out_corner_radius;
layout( location =10 ) out float out_edge_softness;
layout( location =11 ) out float out_border_thickness;

#define GAMMA_TO_LINEAR(Gamma) ((Gamma) < 0.04045 ? (Gamma) / 12.92 : pow(max((Gamma) + 0.055, 0.0) / 1.055, 2.4))

void
main()
{
 vec2 vertices[4] =
 {
  {-1, -1},
  {-1,  1},
  { 1, -1},
  { 1,  1},
 };
 vec2 pixel_vert[4] =
 {
  { 0, 1},
  { 0, 0},
  { 1, 1},
  { 1, 0},
 };
 vec2 top_left  = v_p0;
 vec2 bot_right = v_p1;

 vec2 tex_top_left  = in_tex_p0;
 vec2 tex_bot_right = in_tex_p1;

 vec2 dst_half_size = (bot_right - top_left) / 2;
 vec2 dst_center    = (bot_right + top_left) / 2;
 vec2 dst_pos       = (vertices[gl_VertexIndex] * dst_half_size + dst_center);

 vec2 src_half_size = (tex_bot_right - tex_top_left) / 2;
 vec2 src_center    = (tex_bot_right + tex_top_left) / 2;
 vec2 src_pos       = (vertices[gl_VertexIndex] * src_half_size + src_center);

 fragColor00 = inColor00;
 fragColor10 = inColor10;
 fragColor01 = inColor01;
 fragColor11 = inColor11;

#if 1 // I would have to do this if format space is SRGB, but I have put it as UNORM
 fragColor00.r = GAMMA_TO_LINEAR(inColor00.r);
 fragColor00.g = GAMMA_TO_LINEAR(inColor00.g);
 fragColor00.b = GAMMA_TO_LINEAR(inColor00.b);
 fragColor00.a = 1.0 - GAMMA_TO_LINEAR(1.0 - inColor00.a);

 fragColor01.r = GAMMA_TO_LINEAR(inColor01.r);
 fragColor01.g = GAMMA_TO_LINEAR(inColor01.g);
 fragColor01.b = GAMMA_TO_LINEAR(inColor01.b);
 fragColor01.a = 1.0 - GAMMA_TO_LINEAR(1.0 - inColor01.a);

 fragColor10.r = GAMMA_TO_LINEAR(inColor10.r);
 fragColor10.g = GAMMA_TO_LINEAR(inColor10.g);
 fragColor10.b = GAMMA_TO_LINEAR(inColor10.b);
 fragColor10.a = 1.0 - GAMMA_TO_LINEAR(1.0 - inColor10.a);

 fragColor11.r = GAMMA_TO_LINEAR(inColor11.r);
 fragColor11.g = GAMMA_TO_LINEAR(inColor11.g);
 fragColor11.b = GAMMA_TO_LINEAR(inColor11.b);
 fragColor11.a = 1.0 - GAMMA_TO_LINEAR(1.0 - inColor11.a);
#endif

 out_coorner_coord = pixel_vert[gl_VertexIndex];

 fragTexCoord = vec2(src_pos.x / ubo.AtlasWidth, src_pos.y / ubo.AtlasHeight);

 gl_Position = vec4( 2 * dst_pos.x / ubo.width  - 1,
                    2 * dst_pos.y / ubo.height - 1,
                    0,
                    1);

 if( tex_top_left[0] == -2 ) //rectangle
 {
  // Update the z position to not overlap with the text
  // This happens as I did enable depth testing on the pipeline
  //
  //gl_Position.z = 0.01;

  fragTexCoord = vec2(-2, -2);
 }
 else if ( tex_top_left[0] == -3 )
 {
  //gl_Position.z = 0.02;
  fragTexCoord = vec2(-3, -3);
 }

 out_dst_pos       = dst_pos;
 out_dst_center    = dst_center;
 out_dst_half_size = dst_half_size;
 out_corner_radius = in_corner_radius;
 out_edge_softness = in_edge_softness;
 out_border_thickness = in_border_thickness;
}
