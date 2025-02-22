#version 450

layout(binding = 2) uniform sampler2D texSampler;

layout( location = 0 ) in vec4  fragColor00;
layout( location = 1 ) in vec4  fragColor01;
layout( location = 2 ) in vec4  fragColor10;
layout( location = 3 ) in vec4  fragColor11;
layout( location = 4 ) in vec2  fragTexCoord;
layout( location = 5 ) in vec2  in_dst_pos;         
layout( location = 6 ) in vec2  in_dst_center;      
layout( location = 7 ) in vec2  in_dst_half_size;   
layout( location = 8 ) in vec2  in_coorner_coord;   
layout( location = 9 ) in float in_corner_radius;  
layout( location =10 ) in float in_edge_softness;  
layout( location =11 ) in float in_border_thickess;  


layout(location = 0) out vec4 outColor;

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

float RectSDF(vec2 sample_pos, vec2 rect_half_size, float r)
{
 return normalize(distance(sample_pos, rect_half_size) - r);
}

float RoundedRectSDF(vec2 sample_pos,
                     vec2 rect_center,
                     vec2 rect_half_size,
                     float r)
{
 vec2 d2 = (abs(rect_center - sample_pos) -
            rect_half_size +
            vec2(r, r));
 return min(max(d2.x, d2.y), 0.0) + length(max(d2, 0.0)) - r;
}

void main()
{
 // Already flipped
 vec3 flipped_texCoords  = vec3(fragTexCoord.x, fragTexCoord.y, 1.0f);
 if (flipped_texCoords.x == -2 || flipped_texCoords.x == -3) // omit texture
 {
  vec4 top_color   = (1-in_coorner_coord.x)*fragColor00 + (in_coorner_coord.x)*fragColor10;
  vec4 bot_color   = (1-in_coorner_coord.x)*fragColor01 + (in_coorner_coord.x)*fragColor11;
  vec4 tint        = (1-in_coorner_coord.y)*top_color   + (in_coorner_coord.y)*bot_color;
  
  float softness = in_edge_softness;
  vec2 softness_padding = vec2(max(0, softness*2-1),
                               max(0, softness*2-1));
  
  // sample distance
  float dist = RoundedRectSDF(in_dst_pos,
                              in_dst_center,
                              in_dst_half_size-softness_padding,
                              in_corner_radius);
  
  // map distance => a blend factor
  float sdf_factor = 1.f - smoothstep(0, 2*softness, dist);
  
  float border_factor = 1.f;
  
  if( in_border_thickess != 0)
  {
   vec2 interior_half_size =
    in_dst_half_size - vec2(in_border_thickess, in_border_thickess);
   
   float interior_radius_reduce_f = 
    min(interior_half_size.x/in_dst_half_size.x,
        interior_half_size.y/in_dst_half_size.y);
   
   float interior_corner_radius =
   (in_corner_radius *
    interior_radius_reduce_f *
    interior_radius_reduce_f);
   
   // calculate sample distance from "interior"
   float inside_d = RoundedRectSDF(in_dst_pos,
                                   in_dst_center,
                                   interior_half_size-softness_padding,
                                   interior_corner_radius);
   
   // map distance => factor
   float inside_f = smoothstep(0, 2*softness, inside_d);
   border_factor = inside_f;
  }
  
  outColor = tint;
  outColor *= sdf_factor * border_factor;
 }
 else
 {
    float distance = texture(texSampler, flipped_texCoords.xy).r;
    outColor = fragColor00 * distance;
    float gamma = 2.2;
    outColor.rgb = pow(outColor.rgb, vec3(1.0f/gamma));
  }
}
