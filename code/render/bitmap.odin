package render

import "base:runtime"
import "core:math"
import "core:math/linalg/glsl"

texture_bitmap :: struct {
	bitmap:    []u8,
	width:     u32,
	height:    u32,
	offset:    u32,
	usage:     glsl.vec2,
	allocator: runtime.Allocator,
}

// ------------------------------------------------------------------

bitmap_create :: proc(width, height: u32, allocator := context.allocator) -> texture_bitmap {
	texture: texture_bitmap

	texture.allocator = allocator

	texture.bitmap = make([]u8, width * height, allocator)
	texture.width = width
	texture.height = height
	texture.usage = {0, 0}

	return texture
}

// ------------------------------------------------------------------

bitmap_destroy :: proc(bitmap: texture_bitmap) {
	delete(bitmap.bitmap, bitmap.allocator)
}

// ------------------------------------------------------------------

bitmap_push :: proc(w, h: f32, using bmap: ^texture_bitmap) -> []u8 {

	new_bmap: []u8

	if offset + cast(u32)(w * h) > (width * height) {
		return new_bmap
	}

	usage.x += w
	usage.y += h

	idx_offset := offset 

	offset += cast(u32)(w * h)

	new_bmap = bitmap[idx_offset:idx_offset + cast(u32)(w * h)]

	return new_bmap
}

// ------------------------------------------------------------------
