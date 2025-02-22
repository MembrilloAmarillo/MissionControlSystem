package render

import "core:fmt"
import "core:math"
import "core:math/linalg/glsl"
import "core:os"
import "core:mem"
import "vendor:stb/truetype"

f_Glyph :: struct {
	glyph:   u32,
	x_off:   f32,
	y_off:   f32,
	x:       f32,
	y:       f32,
	width:   f32,
	height:  f32,
	advance: f32,
}

f_kerning :: struct {
	first:  u32,
	second: u32,
	amount: u32,
}

FontCache :: struct {
	glyph:        [96]f_Glyph,
	FontSize:     f32,
	BitmapArray:  ^u8,
	BitmapWidth:  u32,
	BitmapHeight: u32,
	BitmapOffset: glsl.vec2, // NOTE: I store this here for now. I need this to now where in the original bitmap is located
	ascent:       i32,
	descent:      i32,
	scale:        f32,
	line_height:  f32,
	kerning:      []f_kerning,
	kerning_size: u32,
}

f_BuildFont :: proc(FontSize: f32, width: u32, height: u32, BitmapArray: ^u8, font_path : string = "" ) -> FontCache {
	using truetype

	fc := FontCache {
		FontSize     = FontSize,
		BitmapArray  = BitmapArray,
		BitmapWidth  = width,
		BitmapHeight = height,
	}

	ctx: pack_context
	allocator: rawptr
	PackBegin(&ctx, fc.BitmapArray, cast(i32)width, cast(i32)height, 0, 1, allocator)

	data : []u8
	if len(font_path) == 0 {
		data, _ =  os.read_entire_file("./data/font/RobotoMono.ttf", context.temp_allocator);
	} else {
		data, _ = os.read_entire_file(font_path, context.temp_allocator)
	}
	//data := #load("../../data/font/RobotoMono.ttf")
	//data := #load("./data/font/Inconsolata-Regular.ttf");

	info: fontinfo

	InitFont(&info, raw_data(data), 0)
	fc.scale = ScaleForPixelHeight(&info, cast(f32)FontSize)

	line_gap: i32

	GetFontVMetrics(&info, &fc.ascent, &fc.descent, &line_gap)

	fc.line_height = (cast(f32)(fc.ascent - fc.descent + line_gap) * fc.scale)

	codepoint := make([]rune, 96)
	codepoint[0] = 32
	for i in 0 ..< 95 {
		codepoint[i + 1] = cast(rune)i + 32
	}

	for glyph in 0 ..< 96 {
		x0, x1, y0, y1: i32
		glyph_index_in_font := FindGlyphIndex(&info, codepoint[glyph])
		GetGlyphBitmapBoxSubpixel(
			&info,
			glyph_index_in_font,
			fc.scale,
			fc.scale,
			0,
			0,
			&x0,
			&y0,
			&x1,
			&y1,
		)

		fc.glyph[glyph].width  = cast(f32)(x1 - x0)
		fc.glyph[glyph].height = cast(f32)(y1 - y0)
	}

	range := pack_range {
		font_size                        = cast(f32)FontSize,
		first_unicode_codepoint_in_range = 0,
		array_of_unicode_codepoints      = raw_data(codepoint),
		num_chars                        = 96,
		chardata_for_range               = make([^]packedchar, 96),
	}

	PackFontRanges(&ctx, raw_data(data), 0, &range, 1)

	char_data_range: [^]packedchar = range.chardata_for_range
	defer free(char_data_range, context.allocator)

	for i in 0 ..< 96 {
		q := char_data_range[i]
		fc.glyph[i].glyph = cast(u32)codepoint[i]
		fc.glyph[i].x_off = q.xoff
		fc.glyph[i].y_off = q.yoff
		fc.glyph[i].x = cast(f32)q.x0
		fc.glyph[i].y = cast(f32)q.y0
		fc.glyph[i].advance = q.xadvance
		//fc.glyph[i].width =  cast(f32)(q.x1 - q.x0);
		//fc.glyph[i].height = cast(f32)(q.y1 - q.y0);
		//fmt.println(fc.glyph[i]);
	}

	table_length   := GetKerningTableLength(&info)
	fc.kerning_size = cast(u32)table_length
	fc.kerning      = make([]f_kerning, table_length)

	table := make([]kerningentry, table_length)
	defer delete(table)

	GetKerningTable(&info, raw_data(table), table_length)

	for i in 0 ..< table_length {
		k := table[i]
		fmt.println(k)
		fc.kerning[i].first  = cast(u32)k.glyph1
		fc.kerning[i].second = cast(u32)k.glyph2
		fc.kerning[i].amount = cast(u32)k.advance
	}

	PackEnd(&ctx)

	return fc
}

f_get_kerning_from_codepoint :: proc(fc: ^FontCache, g1: u32, g2: u32) -> u32 {
	for i in 0 ..< fc.kerning_size {
		if fc.kerning[i].first == g1 && fc.kerning[i].second == g2 {
			return fc.kerning[i].amount
		}
	}
	return 0
}
