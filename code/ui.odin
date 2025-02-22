package OrbitMCS

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg/glsl"
import "core:mem"
import vmem "core:mem/virtual"
import "core:slice"
import "core:sort"
import "core:strconv"
import "core:strings"
import textedit "core:text/edit"

import "vendor:glfw"

import "render"

import hash "simple_hash"

//import tracy "./third_party/odin-tracy"

import "utils"

// TODO:
// [] Take into account borders to not overlap with boxes inside the window panel
//

MAX_TEXT_STORE      :: #config(UI_TEXT_STORE_SIZE, 4096)
MAX_LAYOUT_STACK    :: #config(UI_LAYOUT_SIZE    , 1024)
MAX_ROOT_STACK      :: #config(UI_ROOT_SIZE      , 256 )
MAX_TABLE_HASH_SIZE :: #config(UI_TABLE_HASH_SIZE, 4096)
MAX_RENDER_STACK    :: #config(UI_RENDER_BOX_SIZE, 125 << 10)

DEFAULT_SCROLL_DELTA: f32 = 3

id :: distinct u64

MIN_WINDOW_WIDTH  :: 50
MIN_WINDOW_HEIGHT :: 100

UI_Opt :: enum int {
	NONE,
	X_CENTERED, // Button centered on X axis
	Y_CENTERED, // Button centered on Y axis
	SET_WIDTH_TO_TEXT, // Set box width to string length
	X_CENTERED_STRING, // Text centered on button width
	Y_CENTERED_STRING, // Text centered on button height
	DISABLE_HORIZONTAL_SCROLLBAR, // No horizontal scrollbar
	DISABLE_VERTICAL_SCROLLBAR, // No verticall scrollbar
	DISABLE_TITLE_BAR, // No title bar on begin frame
	INPUT_TEXT, // Box has the ability to get input text
	DRAW_RECT,
	DRAW_STRING,
	DRAW_BORDER,
	NO_CLICKABLE,
	NO_HOVER,
	CHECKBOX,
	HOVER_ANIMATION,
}

UI_Options :: distinct bit_set[UI_Opt;int]

LayoutType :: enum i32 {
	NONE     = 0,
	RELATIVE = 1,
	FIXED    = 2,
}

StyleParam :: struct {
	color_border:     glsl.vec4,
	color_rect00:     glsl.vec4,
	color_rect01:     glsl.vec4,
	color_rect10:     glsl.vec4,
	color_rect11:     glsl.vec4,
	color_text:       glsl.vec4,
	border_thickness: f32,
	corner_radius:    f32,
	edge_softness:    f32,
}

UI_Style :: struct {
	button:           StyleParam,
	background_panel: StyleParam,
	front_panel:      StyleParam,
	text:             StyleParam,
	input_field:      StyleParam,
	hover_box:        StyleParam,
}

EventResults :: struct {
	hover_on:        bool,
	left_click:      bool,
	right_click:     bool,
	left_click_hold: bool,
	click_position:  glsl.vec2,
}

Rect2D :: struct {
	top_left: glsl.vec2,
	size:     glsl.vec2, // width and height
}

UI_AnimationData :: struct {
	id              : u64,
	bouncing        : u32,
	animation_dt    : f32, 
	current         : f32, 
	target          : f32, 
	currentVelocity : f32, 
	smoothTime      : f32,
	maxSpeed        : f32,
	output          : f32
}

Box :: struct {
	first, next, prev, tail, parent: ^Box, // siblings
	rect:                            Rect2D,
	content_rect:                    glsl.vec2, // how much has been occupied
	scroll:                          glsl.vec2, // where does the scroll start
	title_string:                    string,
	key_text:                        string,
	text_position:                   glsl.vec2,
	text_store:                      [MAX_TEXT_STORE]u8,
	text_input:                      strings.Builder,
	flags:                           UI_Options,
	zindex:                          int,
	lay_type:                        LayoutType,
	id:                              u64,
	style:                           StyleParam,
	animation_progress:              f32,
	is_animating:                    bool,
}

UI_NilBox : Box = {
 first  = nil,
 next   = nil,
 prev   = nil,
 tail   = nil,
 parent = nil
}

axis_type :: enum u32 {
	axis_vertical   = 0,
	axis_horizontal = 1,
}

Layout :: struct {
	position:           glsl.vec2,
	size:               glsl.vec2,
	at:                 glsl.vec2, // where are we row/column - wise
	n_rows:             u32, // optional, in case we want it fixed
	n_columns:          u32, // optional, in case we want it fixed
	type:               LayoutType,
	axis:               axis_type "By default the layout will be done vertically",
	box_preferred_size: glsl.vec2,
	parent_box:         ^Box,
	parent_seed:        u64 "This id can be deferent from the parent box",
	padding:            glsl.vec2,
	string_padding:     glsl.vec2
}

Queue :: struct($T: typeid, $N: u32) where N > 1 {
	items:      [N]T,
	push_count: int,
	front:      int,
}

push_queue :: #force_inline proc(queue: ^$T/Queue($V, $N), val: V) {
	assert(queue.push_count < len(queue.items))
	queue.items[queue.push_count] = val
	queue.push_count += 1
}

get_front_queue :: #force_inline proc(queue: ^$T/Queue($V, $N)) -> V {
	assert(queue.push_count > 0)
	return queue.items[queue.front]
}

pop_queue :: #force_inline proc(queue: ^$T/Queue($V, $N)) {
	assert(queue.front < queue.push_count)
	//queue.push_count -= 1
	queue.front += 1
}

UI_State :: struct {

	hash_boxes:                 hash.Table(string, ^Box),
	hover_id:                   id,
	focus_id:                   id,
	first_frame:                bool,

	// per frame
	//
	set_dark_theme:             bool,
	theme:                      UI_Style,
	style:                      utils.Stack(StyleParam, MAX_LAYOUT_STACK),
	target_box:                 ^Box,
	press_target:               ^Box,
	hover_target:               ^Box,
	scroll_target:              ^Box,
	root_stack:                 utils.Stack(^Box, MAX_ROOT_STACK),
	render_root:                ^Box,
	layout_stack:               utils.Stack(^Layout, MAX_LAYOUT_STACK),
	option_stack:               utils.Stack(UI_Options, MAX_LAYOUT_STACK),
	last_zindex:                int,
	resizing:                   bool,
	mouse_pos:                  glsl.vec2,

	// Retained data
	//
	drag_data:                  glsl.vec2,
	drag_delta:                 glsl.vec2,
	boundary_drag:              glsl.vec2,
	text_store:                 [MAX_TEXT_STORE]u8,
	text_input:                 strings.Builder,
	text_edit:                  textedit.State,
	text_edit_off:              i32,

	// animation
	//
	animation_dt:               f32,
	animation_rate:             f32,
	is_animating:               bool,

	animation_data: hash.Table(string, ^UI_AnimationData),

	// Only one cursor active for the app
	//
	cursor_position:            glsl.vec2,
	vulkan_iface:               ^render.VulkanIface,
	arena:                      ^vmem.Arena,
	arena_temp:                 ^vmem.Arena,
	persistent_arena_allocator: runtime.Allocator,
	per_frame_arena_allocator:  runtime.Allocator,
	cursor_image_per_box:       hash.Table(string, glfw.CursorHandle),
}

// Global variable for UI context
ui_context: UI_State

// ------------------------------------------------------------------- //

slice_at_char :: proc(text: string, c: u8) -> string {
	new_slice := text

	idx_to_slice_from := 0
	for i := 0; i < len(text); i += 1 {
		t := text[i]
		if t == c {
			idx_to_slice_from = i
		}
	}

	new_slice = new_slice[idx_to_slice_from:]

	return new_slice
}

// ------------------------------------------------------------------- //

rgba_to_norm :: #force_inline proc(rgba: glsl.vec4) -> glsl.vec4 {
	return {rgba.x / 255, rgba.y / 255, rgba.z / 255, rgba[3] / 255}
}

// ------------------------------------------------------------------- //

hex_rgba_to_vec4 :: #force_inline proc(hex_rgba: u32) -> glsl.vec4 {
	vec: glsl.vec4
	vec[3] = cast(f32)((hex_rgba & 0x000000FF))
	vec[2] = cast(f32)((hex_rgba & 0x0000FF00) >> 8)
	vec[1] = cast(f32)((hex_rgba & 0x00FF0000) >> 16)
	vec[0] = cast(f32)((hex_rgba & 0xFF000000) >> 24)

	return vec
}

ui_pop_style :: proc() {
 if ui_context.style.push_count > 0 {
  utils.pop_stack(&ui_context.style)
 }
}

get_default_ui_dark_style :: proc() -> UI_Style {

	style: UI_Style

	liquid_lava := rgba_to_norm(hex_rgba_to_vec4(0xEF6024FF))
	dark_void   := rgba_to_norm(hex_rgba_to_vec4(0x191b1cFF))
	//dark_void   := rgba_to_norm(hex_rgba_to_vec4(0x000000FF))
	dusty_grey  := rgba_to_norm(hex_rgba_to_vec4(0x878787FF))
	gluon_grey  := rgba_to_norm(hex_rgba_to_vec4(0x1f2223FF))
	slate_grey  := rgba_to_norm(hex_rgba_to_vec4(0x262626FF))
	snow        := rgba_to_norm(hex_rgba_to_vec4(0xdddee0FF))

	style.background_panel = {
		color_border     = liquid_lava,
		color_rect00     = dark_void,
		color_rect01     = dark_void,
		color_rect10     = dark_void,
		color_rect11     = dark_void,
		color_text       = snow,
		border_thickness = 0,
		corner_radius    = 6,
		edge_softness    = 0,
	}

	style.button = {
		color_border     = liquid_lava,
		color_rect00     = liquid_lava,
		color_rect01     = liquid_lava,
		color_rect10     = liquid_lava,
		color_rect11     = liquid_lava,
		color_text       = snow,
		border_thickness = 0,
		corner_radius    = 6,
		edge_softness    = 0,
	}

	//style.front_panel = style.background_panel
	//style.front_panel.border_thickness = 1

	style.front_panel = {
		color_border     = liquid_lava,
		color_rect00     = gluon_grey,
		color_rect01     = gluon_grey,
		color_rect10     = gluon_grey,
		color_rect11     = gluon_grey,
		color_text       = snow,
		border_thickness = 0,
		corner_radius    = 6,
		edge_softness    = 0,
	}

	style.input_field = style.background_panel
	style.text = style.input_field

	style.hover_box = style.button
	//style.hover_box.color_rect00 += style.hover_box.color_rect00 * 0.3
	//style.hover_box.color_rect10 += style.hover_box.color_rect01 * 0.3
	style.hover_box.color_rect01 += style.hover_box.color_rect10 * 0.8
	style.hover_box.color_rect11 += style.hover_box.color_rect11 * 0.8
	style.hover_box.color_border += style.hover_box.color_border * 0.7

	return style
}

get_default_ui_light_style :: proc() -> UI_Style {

	style: UI_Style

	black      := rgba_to_norm(hex_rgba_to_vec4(0x101e19FF))
	dark_blue  := rgba_to_norm(hex_rgba_to_vec4(0x496FC2FF))
	blue       := rgba_to_norm(hex_rgba_to_vec4(0x447EF2FF))
	gray       := rgba_to_norm(hex_rgba_to_vec4(0xeee8d5FF))
	white      := rgba_to_norm(hex_rgba_to_vec4(0xfdf6e3FF))
	light_blue := rgba_to_norm(hex_rgba_to_vec4(0x6393F2FF))

	style.background_panel = {
		color_border     = light_blue,
		color_rect00     = white,
		color_rect01     = white,
		color_rect10     = white,
		color_rect11     = white,
		color_text       = black,
		border_thickness = 0,
		corner_radius    = 3,
		edge_softness    = 0,
	}

	style.button = {
		color_border     = light_blue,
		color_rect00     = light_blue,
		color_rect01     = light_blue,
		color_rect10     = light_blue,
		color_rect11     = light_blue,
		color_text       = black,
		border_thickness = 0,
		corner_radius    = 6,
		edge_softness    = 0,
	}

	//style.front_panel = style.background_panel
	//style.front_panel.border_thickness = 1

	style.front_panel = {
		color_border     = light_blue,
		color_rect00     = gray,
		color_rect01     = gray,
		color_rect10     = gray,
		color_rect11     = gray,
		color_text       = black,
		border_thickness = 0,
		corner_radius    = 3,
		edge_softness    = 0,
	}

	style.input_field = {
		color_border     = gray,
		color_rect00     = white,
		color_rect01     = white,
		color_rect10     = gray,
		color_rect11     = gray,
		color_text       = black,
		border_thickness = 2,
		corner_radius    = 6,
		edge_softness    = 0,
	}
	style.text = style.input_field

	style.hover_box = style.button
	//style.hover_box.color_rect00 += style.hover_box.color_rect00 * 0.3
	//style.hover_box.color_rect01 += style.hover_box.color_rect01 * 0.3
	style.hover_box.color_rect01 += style.hover_box.color_rect01 * 0.3
	style.hover_box.color_rect11 += style.hover_box.color_rect11 * 0.3
	style.hover_box.color_border += style.hover_box.color_border * 0.7

	style.button = style.hover_box

	return style
}

// ------------------------------------------------------------------- //

set_next_box_layout :: proc(options: UI_Options) {
	utils.push_stack(&ui_context.option_stack, options)
}

// ------------------------------------------------------------------- //

pop_box_layout :: proc() {
	if ui_context.option_stack.push_count > 0 {
		utils.pop_stack(&ui_context.option_stack)
	}
}

// ------------------------------------------------------------------- //

set_next_layout :: proc(
	pos, size: glsl.vec2,
	n_rows: u32 = 0,
	n_columns: u32 = 0,
	type: LayoutType = .NONE,
) {
	new_lay, lay_error := new(Layout, ui_context.per_frame_arena_allocator)
	CHECK_MEM_ERROR(lay_error)
	new_lay^ = Layout {
		position  = pos,
		size      = size,
		at        = pos,
		n_rows    = n_rows,
		n_columns = n_columns,
		type      = type,
		axis      = axis_type.axis_vertical,
	}

	utils.push_stack(&ui_context.layout_stack, new_lay)
}

// ------------------------------------------------------------------- //

set_box_preferred_size :: proc(vec: glsl.vec2) {
	layout := get_layout_stack()
	layout.axis = axis_type.axis_vertical
	if layout != nil {
		layout.box_preferred_size = vec
	}
}

// ------------------------------------------------------------------- //

set_layout_next_column :: proc(column: u32) {
	layout := get_layout_stack()
	layout.axis = axis_type.axis_horizontal
	if layout != nil {
		if column >= layout.n_columns {
			layout.n_columns = column + 1
		}
		if layout.box_preferred_size == {0, 0} || column == 0 {
			size_partition := layout.size.x / cast(f32)layout.n_columns
			start_pos := size_partition * cast(f32)column
			layout.at.x = layout.position.x + start_pos
			//layout.at.x += layout.padding.x
			//layout.at.y    = layout.position.y
		} else {
			layout.at.x += layout.box_preferred_size.x
			//layout.at.x += layout.padding.x
		}
	}
}

// ------------------------------------------------------------------- //

// We put a default box_size in case the user forgets to set the preferred box size
// when using scrollable sections. I think is preferable to use this default box size
// rather than crashing or not creating the scrollable section at all
//
begin_next_layout_scrollable_section :: proc(max_rows: u32 = 0, box_size : glsl.vec2 = {300, 30}) -> int {
	layout := get_layout_stack()
	if layout != nil && layout.parent_box != &UI_NilBox {
		layout.at += layout.parent_box.scroll
	}
	if layout.at.y > layout.position.y {
  layout.at.y = layout.position.y
	}
	if layout.at.x > layout.position.x {
	 layout.at.x = layout.position.x
	}

	row_start_it := 0
 l_it         := 0
 if layout.at.y < layout.position.y {
  off : f32 = layout.position.y - layout.at.y
  if layout.box_preferred_size.y == 0 {
   row_start_it = auto_cast math.ceil(off / box_size.y)
  }
  else {
   row_start_it = auto_cast math.ceil(off / cast(f32)layout.box_preferred_size.y)
  }
 }

 return row_start_it
}

// ------------------------------------------------------------------- //

end_next_layout_scrollable_section :: proc(max_rows: u32 = 0) {
	//tracy.ZoneS(depth = 10)
	layout := get_layout_stack()
	if layout != nil && layout.parent_box != &UI_NilBox {
		layout.at -= layout.parent_box.scroll

		if layout.box_preferred_size != {0, 0} && max_rows > 0 {
			size: f32 = 0
			size = cast(f32)max_rows * layout.box_preferred_size.y
			parent_box := layout.parent_box

			padd_offset := (parent_box.rect.top_left.y - layout.position.y) + parent_box.rect.size.y
			pct :=  padd_offset / size
			scroll_bar_size := padd_offset * pct
			set_next_layout_style(ui_context.theme.button)
			offset := -parent_box.scroll.y
			//fmt.println("offset", offset)
			box := make_box_no_key(
				"scroll_bar",
				{layout.position.x + parent_box.rect.size.x - 20, layout.position.y + offset},
				{20, scroll_bar_size},
				{.DRAW_RECT, .DRAW_BORDER},
			)
			utils.pop_stack(&ui_context.style)
		} else {
			parent_box := layout.parent_box
			size: f32 = layout.at.y - layout.position.y

			padd_offset := (parent_box.rect.top_left.y - layout.position.y) + parent_box.rect.size.y
			pct :=  padd_offset / size
   offset := -parent_box.scroll.y
			scroll_bar_size := padd_offset
			if size > padd_offset {
			 scroll_bar_size -= (size - padd_offset)
			}
			set_next_layout_style(ui_context.theme.button)
			box := make_box_no_key(
				"scroll_bar",
				{layout.position.x + parent_box.rect.size.x - 15, layout.position.y + offset},
				{15, scroll_bar_size},
				{.DRAW_RECT, .DRAW_BORDER}
			)
			utils.pop_stack(&ui_context.style)
		}
	}
}

// ------------------------------------------------------------------- //

ui_vspacer :: proc( space : f32 ) {
	layout := get_layout_stack()
	if layout != nil {
		layout.at.y += space
	}
}

// ------------------------------------------------------------------- //

ui_hspacer :: proc( space : f32 ) {
	layout := get_layout_stack()
	if layout != nil {
		layout.at.x += space
	}
}

// ------------------------------------------------------------------- //

@(deferred_out = unset_layout_ui_parent_seed)
set_layout_ui_parent_seed :: proc( box : ^Box ) {
 layout := get_layout_stack()
	if layout != nil && box != nil {
		layout.parent_seed = box.id
	}
}

// ------------------------------------------------------------------- //

unset_layout_ui_parent_seed :: proc() {
 layout := get_layout_stack()
 if layout != nil {
		layout.parent_seed = 0
	}
}

// ------------------------------------------------------------------- //

set_layout_next_row_col :: proc(n_rows, n_cols: u32) {
	layout := get_layout_stack()
	if layout != nil {
		layout.n_rows = n_rows
		layout.n_columns = n_cols
	}
}

// ------------------------------------------------------------------- //

set_layout_reset_column :: proc() {
	layout := get_layout_stack()
	if layout != nil {
		layout.at.x = layout.position.x
		layout.axis = axis_type.axis_horizontal
	}
}

// ------------------------------------------------------------------- //

set_layout_reset_row :: proc() {
	layout := get_layout_stack()
	if layout != nil {
		layout.at.y = layout.position.y
		layout.axis = axis_type.axis_vertical
	}
}

// ------------------------------------------------------------------- //

set_layout_next_padding :: proc( x_padd : f32 = 0, y_padd : f32 = 0 )
{
	layout := get_layout_stack()
	if layout != nil {
		layout.padding = { x_padd, y_padd }
	}
}

// ------------------------------------------------------------------- //

set_layout_string_padding :: proc( x_padd : f32 = 0, y_padd : f32 = 0 )
{
	layout := get_layout_stack()
	if layout != nil {
		layout.string_padding = { x_padd, y_padd }
	}
}

// ------------------------------------------------------------------- //

set_layout_next_row :: proc(row: u32) {
	layout := get_layout_stack()
	layout.axis = axis_type.axis_vertical
	if layout != nil {
		if row > layout.n_rows {
			layout.n_rows = row + 1
		}
		if layout.box_preferred_size == {0, 0} || row == 0 {
			size_partition := layout.size.y / cast(f32)layout.n_rows
			start_pos := size_partition * cast(f32)row
			layout.at.y = layout.position.y + start_pos
			//layout.at.y += layout.padding.y
			//layout.at.x    = layout.position.x
		} else {
			layout.at.y += layout.box_preferred_size.y
			//layout.at.y += layout.padding.y
		}
	}
}

// ------------------------------------------------------------------- //

set_next_layout_style :: proc(st: StyleParam) {
	utils.push_stack(&ui_context.style, st)
}

// ------------------------------------------------------------------- //

pop_layout_style :: proc() {
 if ui_context.style.push_count > 0 {
	 utils.pop_stack(&ui_context.style)
	}
}

// ------------------------------------------------------------------- //

get_layout_stack :: proc() -> ^Layout {
	//using ui_context.layout_stack;

	if (ui_context.layout_stack.push_count == 0) {
		return nil
	}
	return ui_context.layout_stack.items[ui_context.layout_stack.push_count - 1]
}

// ------------------------------------------------------------------- //

set_next_hover_cursor :: proc(box: ^Box, cursor_type: c.int) {
	buf: [32]u8
	cursor: glfw.CursorHandle
	cursor = hash.lookup_table(
		&ui_context.cursor_image_per_box,
		strconv.itoa(buf[:], auto_cast box.id),
	)

	if cursor == nil {
		cursor = glfw.CreateStandardCursor(cursor_type)
		hash.insert_table(
			&ui_context.cursor_image_per_box,
			strconv.itoa(buf[:], auto_cast box.id),
			cursor,
		)
	}
}

// ------------------------------------------------------------------- //

consume_box_event :: proc(box: ^Box) -> render.os_input_type {
 using render
 x, y := ui_context.mouse_pos.x, ui_context.mouse_pos.y

 layout := get_layout_stack()

 if point_intersect({cast(f32)x, cast(f32)y}, box.rect)
 {
  // FIX if there are two windows overlaping it will take the last one to render
  // as the scroll target (or both simultaneusly)
  //
  ui_context.scroll_target = box
  if ui_context.hover_target == &UI_NilBox || box.zindex > ui_context.hover_target.zindex {
   buf: [32]u8
   cursor := hash.lookup_table(
    &ui_context.cursor_image_per_box,
    strconv.itoa(buf[:], auto_cast box.id),
   )
   if cursor != nil {
    glfw.SetCursor(ui_context.vulkan_iface.va_Window.w_window, cursor)
   } else {
    cursor = glfw.CreateStandardCursor(glfw.ARROW_CURSOR)
    glfw.SetCursor(ui_context.vulkan_iface.va_Window.w_window, cursor)
   }
   ui_context.hover_target  = box
   box.is_animating = true
  }
 }

 for input, idx in ui_context.vulkan_iface.va_OsInput {
  if .LEFT_CLICK in input.type && !(.NO_CLICKABLE in box.flags) {
   click := input.mouse_click
   if point_intersect(click, box.rect) && (ui_context.press_target == &UI_NilBox || (box.zindex >= ui_context.press_target.zindex))
   {
    if box.zindex == 0 && box.lay_type != .FIXED {
     ui_context.last_zindex += 1
     box.zindex = ui_context.last_zindex
    }
    if !(.NO_CLICKABLE in box.flags) {
     ui_context.press_target = box
     ui_context.target_box = box
     ui_context.scroll_target = box
    }

    ui_context.drag_data = click

    return .LEFT_CLICK
   }
  }
  else if .LEFT_CLICK_RELEASE in input.type {
   //ui_context.hover_target = nil
   ui_context.press_target = &UI_NilBox
   ui_context.resizing = false
   ui_context.drag_delta = {0, 0}
   return .LEFT_CLICK_RELEASE
  }
  else if .RIGHT_CLICK in input.type {
   ui_context.hover_target =
   ui_context.hover_target != &UI_NilBox ? ui_context.hover_target : box
   return .RIGHT_CLICK
  }
  else if .ARROW_DOWN in input.type {
   if ui_context.scroll_target != &UI_NilBox {
    if input.scroll_off.y == 0 {
     ui_context.scroll_target.scroll.y -= DEFAULT_SCROLL_DELTA * 0.2
    } else {
     ui_context.scroll_target.scroll.y += input.scroll_off.y * 0.2
    }
   }
   return .ARROW_DOWN
  }
  else if .ARROW_UP in input.type {
   if ui_context.scroll_target != &UI_NilBox {
    if input.scroll_off.y == 0 {
     ui_context.scroll_target.scroll.y += DEFAULT_SCROLL_DELTA * 0.2
    } else {
     ui_context.scroll_target.scroll.y += input.scroll_off.y * 0.2
    }
   }
   return .ARROW_UP
  }
  else if .CHARACHTER in input.type {
  	strings.write_rune(&ui_context.text_input, input.codepoint)
  	unordered_remove(&ui_context.vulkan_iface.va_OsInput, idx)
  	return .CHARACHTER
  }
  else if .BACKSPACE in input.type {
   if box == ui_context.target_box && .INPUT_TEXT in ui_context.target_box.flags {
    strings.pop_rune(&ui_context.target_box.text_input)
   }
  }
 }
 return {}
}

// ------------------------------------------------------------------- //
// NOTE: strings.clone highly inneficient
//
get_key_from_string :: proc(text: string, key: rawptr) -> (string, string) {
	key_part: string
	i := 0
	for it := 0; it < len(text); it += 1 {
	 c := text[it]
		if c == '#' {
			break
		}
		i += 1
	}

	if i == len(text) {
		return text, text
	}

	key_part = text[i:]

	j := 0
	for it := 0; it < len(key_part); it += 1 {
	 c := key_part[it]
		if c == '%' {
			break
		}
		j += 1
	}
	if j == len(key_part) {
		return text, text
	}

	//place_holder: [256]u8
	//new_string := strings.builder_from_bytes(place_holder[:])
	// Study if using this provides us of not using string.clone()
	//
	new_string := strings.builder_make_len_cap(0, 1024, ui_context.per_frame_arena_allocator)

	strings.write_string(&new_string, key_part[:len(key_part) - 2])
	switch key_part[j + 1] {
	case 'p':
		{
			value := cast(u64)cast(uintptr)key
			strings.write_u64(&new_string, value)
		}
	case 'd':
		{
			value: int = (cast(^int)key)^
			strings.write_int(&new_string, value)
		}
	}

	string_ret := strings.to_string(new_string)
	return text[:i], string_ret
}

// ------------------------------------------------------------------- //

make_box :: proc {
	make_box_no_key,
	make_box_from_key,
}

// ------------------------------------------------------------------- //

make_box_from_key :: proc(
	text: string,
	top_left: glsl.vec2 = {-1, -1},
	width_height: glsl.vec2 = {-1, -1},
	box_flags: UI_Options = {.DRAW_RECT},
	key: ^$T,
) -> ^Box {

	//tracy.ZoneS(depth = 10)

	display_text, key_text := get_key_from_string(text, key)
	box := make_box_no_key(key_text, top_left, width_height, box_flags)
	box.title_string = display_text// strings.clone(display_text, ui_context.per_frame_arena_allocator)
	box.key_text     = key_text
	return box
}

// ------------------------------------------------------------------- //

make_box_no_key :: proc(
	text: string,
	top_left: glsl.vec2 = {-1, -1},
	width_height: glsl.vec2 = {-1, -1},
	box_flags: UI_Options = {.DRAW_RECT},
) -> ^Box {

	//tracy.ZoneS(depth = 10)

	using utils

	box: ^Box
	layout := get_layout_stack()
	if layout == nil {
		string_hash := hash.get_hash_from_key( text )
		bucket := hash.lookup_table_bucket(&ui_context.hash_boxes, text)
		for &v in bucket {
			if v != nil {
				if v.id == string_hash {
					box = v
				}
			}
		}
	} else {
	 parent_seed := layout.parent_seed // if it is not set is 0
	 if layout.parent_box == nil {
   string_hash := hash.get_hash_from_key( text )
   bucket := hash.lookup_table_bucket(&ui_context.hash_boxes, text, parent_seed)
 		for &v in bucket {
 			if v != nil {
 				if v.id == string_hash {
 					box = v
 				}
 			}
 		}
	 }
	 else {
	  string_hash := hash.get_hash_from_key( text, layout.parent_box.id )
	  // if there is a parent seed set, it has higher priority than it default set parent box
	  //
   bucket := hash.lookup_table_bucket(&ui_context.hash_boxes, text, layout.parent_seed > 0 ? layout.parent_seed : layout.parent_box.id)
		 for &v in bucket {
 			if v != nil {
 				if v.id == string_hash {
 					box = v
 				}
 			}
		 }
	 }

		//box = hash.lookup_table(&ui_context.hash_boxes, text, layout.parent_box.id)
	}

	if (box == nil) {
		fmt.println("[INFO] Box ", text, " not found, hashed")
		err: vmem.Allocator_Error
		box, err = new(Box, ui_context.persistent_arena_allocator)
		CHECK_MEM_ERROR(err)

		if layout == nil {
			box.id = hash.insert_table(&ui_context.hash_boxes, text, box)
		} else {
		 if layout.parent_box == nil {
		  box.id = hash.insert_table(&ui_context.hash_boxes, text, box)
		 }
		 else {
			 box.id = hash.insert_table(&ui_context.hash_boxes, text, box, layout.parent_box.id)
			}
		}

	 box.text_input = strings.builder_from_bytes(box.text_store[:])
	}

	box.parent = &UI_NilBox
	box.first  = &UI_NilBox
	box.tail   = &UI_NilBox
	box.next   = &UI_NilBox
	box.prev   = &UI_NilBox

	box.title_string = text //strings.clone(text, ui_context.per_frame_arena_allocator)
	box.key_text     = text

	// ============= Animations =================== 
	//
	if .HOVER_ANIMATION in box_flags {
		anim_data_bucket := hash.lookup_table_bucket(&ui_context.animation_data, text)
		anim_data : ^UI_AnimationData

		for &anim in anim_data_bucket {
			if anim != nil && anim.id == hash.get_hash_from_key(text)
			{
				anim_data = anim
				break
			}
		}
		if anim_data == nil {
			fmt.println("[INFO] Box Animation ", text, " not found, hashed")
			err: vmem.Allocator_Error
			anim_data = new(UI_AnimationData, ui_context.persistent_arena_allocator)
			CHECK_MEM_ERROR(err)
			anim_data.id = hash.insert_table(&ui_context.animation_data, text, anim_data)

			anim_data^ = UI_AnimationData {
				id           = anim_data.id,
				animation_dt = ui_context.animation_dt,
				current      = 0.0,
				target       = 1,
				currentVelocity = 0.0,
				smoothTime      = 0.15,
				maxSpeed        = 10000
			}
		}
	}

	top_l := top_left
	w_h := width_height

 if ui_context.root_stack.push_count == 0 {
	 box.rect = Rect2D{top_l, w_h}
	}

	if ui_context.root_stack.push_count > 0 {

		box_root := get_front_stack(&ui_context.root_stack)
		is_box_hashed := false

		if (box_root.first == &UI_NilBox) {
			box_root.first = box
			//box.zindex     = box_root.zindex + 1
		} else {
			b := box_root.tail
			//for ; b != box_root.tail && b != &UI_NilBox; b = b.next {
			//	if b == box {
			//		fmt.println("Box already in the tree, which makes no sense whatsoever", box.title_string)
			//	}
			//}
			b.next = box
			box.prev = b
		}

  box.zindex    = box_root.zindex
		box_root.tail = box
		box.parent    = box_root
		fixed_size := false

		if (top_l == {-1, -1} || w_h == {-1, -1}) {
			top_l = box_root.rect.top_left
			w_h = {
				box_root.rect.size.x,
				auto_cast ui_context.vulkan_iface.va_FontCache[1].line_height + 6,
			}
			// NOTE: Only do this when title bar enabled
			//
			if !(.DISABLE_TITLE_BAR in box_flags) {
				top_l.y += auto_cast ui_context.vulkan_iface.va_FontCache[0].line_height + 6
			}

		} else {
			fixed_size = true
		}

		box.rect = Rect2D{top_l, w_h}

		if .SET_WIDTH_TO_TEXT in box_flags {
			box.rect.size.x =
				calc_text_size(box.title_string, ui_context.vulkan_iface.va_FontCache[1]).x
		}

		layout: ^Layout = get_layout_stack()

		// NOTE: If fixed is true, layout not updated!!
		if layout != nil && fixed_size == false {
			// get box into correspondent layout position
			//
			box.rect.top_left = layout.at
			if layout.box_preferred_size != {0, 0} {
				box.rect.size = layout.box_preferred_size
			}

			// if it has columns/rows specified and no box preferred size
			// then equidistant position, if box size specified, then set that
			//
			if layout.n_columns >= 1 && layout.box_preferred_size == {0, 0} {
				box.rect.size.x = layout.size.x / cast(f32)layout.n_columns
			}

			if layout.n_rows >= 1 && layout.box_preferred_size == {0, 0} {
				box.rect.size.y = layout.size.y / cast(f32)layout.n_rows
			}

			// If yout have set a number of columns and rows, then
			// it will get updated when calling set_layout_next_row() or
			// set_layout_next_column(), however, if not set, it will
			// updated here with the size of the box. It is done this way
			// because if you call, consecutevily set layout row and then
			// set layout box, with a preferred box size, then the functions
			// will not update the the row and column, only the last one called
			//

			box.rect.top_left += layout.padding

			if layout.axis == axis_type.axis_horizontal && layout.n_columns == 0 {
				layout.at.x += box.rect.size.x
			}

			if layout.axis == axis_type.axis_vertical && layout.n_rows == 0 {
				layout.at.y += box.rect.size.y
			}

			if .DRAW_STRING in box_flags {
				box.text_position = box.rect.top_left + layout.string_padding
			}
		}

		if ui_context.root_stack.push_count > 0 {
			box_root := utils.get_front_stack(&ui_context.root_stack)

			if ui_context.option_stack.push_count > 0 {
				option := utils.get_front_stack(&ui_context.option_stack)
				if .DISABLE_VERTICAL_SCROLLBAR in option {
					//box_root.scroll = {box_root.scroll.x, 0}
				}
				if .DISABLE_HORIZONTAL_SCROLLBAR in option {
					//box_root.scroll = {0, box_root.scroll.y}
				}
			}
			//box.rect.top_left += box_root.scroll
		}
	}

	{
		lay := get_layout_stack()
		if lay != nil {
			box.lay_type = lay.type
		} else {
			box.lay_type = .NONE
		}
	}

	{
		if ui_context.option_stack.push_count > 0 {
			options := utils.get_front_stack(&ui_context.option_stack)
			if options != nil {
				box.flags += options
			}
		}
	}

	// Set up style param
	{
		if ui_context.style.push_count > 0 {
			style := utils.get_front_stack(&ui_context.style)
			box.style = style
		} else {
			box.style = ui_context.theme.background_panel
		}
	}

	box.flags += box_flags

	return box
}

// ------------------------------------------ Begin window function -------------------------------- //
// Begin will automatically defer to end function at the end of the scope
// So it is strongly recommended (and a must) that is called inside an if statement
//
@(deferred_out = end)
begin :: proc(
	text: string,
	top_left: glsl.vec2 = {-1, -1},
	width_height: glsl.vec2 = {-1, -1},
	pointer: ^byte = nil,
) -> (
	open: bool,
) {
	return window_begin(text, top_left, width_height, pointer)
}

window_begin :: proc(
	text: string,
	top_left: glsl.vec2 = {-1, -1},
	width_height: glsl.vec2 = {-1, -1},
	pointer: ^byte = nil,
) -> (
	open: bool,
) {
	layout: ^Layout = get_layout_stack()
	top_l := top_left
	w_h := width_height
	box: ^Box = &UI_NilBox

	if ui_context.option_stack.push_count == 0 {
		set_next_box_layout({.NONE})
	}

	if ui_context.vulkan_iface == nil {
		fmt.eprintln("[INFO ERROR] Did not setup the interface with vulkan, variable vulkan_iface")
		return false
	}

	if pointer == nil {
		box = hash.lookup_table(&ui_context.hash_boxes, text)
	} else {
		disp, text_k := get_key_from_string(text, pointer)
		box = hash.lookup_table(&ui_context.hash_boxes, text_k)
	}

	if box == nil {
	 box = &UI_NilBox
	}

	if box == &UI_NilBox {
		if layout == nil {
			//fmt.println("[INFO] No layout defined")
			if top_l == {-1, -1} {
				top_l = {40, 40}
			}
			if w_h == {-1, -1} {
				w_h = {300, 420}
			}
			set_next_layout(top_l, w_h)
			layout = get_layout_stack()
		} else {
			top_l = layout.position
			w_h = layout.size
		}
	} else {
		if layout == nil {
			if top_l == {-1, -1} {
				top_l = box.rect.top_left
			} else {
				box.rect.top_left = top_l
			}
			if w_h == {-1, -1} {
				w_h = box.rect.size
			} else {
				box.rect.size = w_h
			}
			set_next_layout(top_l, w_h, 0, 1, box.lay_type)
			layout = get_layout_stack()
		} else {
			if box.lay_type == .FIXED {
				top_l = layout.position
				w_h = layout.size
			} else {
				top_l = box.rect.top_left
				w_h = box.rect.size
				layout.position = box.rect.top_left
				layout.size = box.rect.size
			}
		}
	}

	begin_box: ^Box
	opt := utils.get_front_stack(&ui_context.option_stack)
	box_options := UI_Options{.DRAW_RECT, .DRAW_BORDER, .NO_HOVER}
	if !(.DISABLE_TITLE_BAR in opt) {
		box_options += {.DRAW_STRING}
	}

	if layout.type == .FIXED {
	 box_options += {.NO_CLICKABLE}
	}

	if pointer == nil {
		begin_box = make_box(text, top_l, w_h, box_options)
	} else {
		begin_box = make_box_from_key(
			text,
			top_l,
			w_h,
			box_options,
			pointer,
		)
	}

	utils.push_stack(&ui_context.root_stack, begin_box)

	layout.at = begin_box.rect.top_left

	layout.parent_box = begin_box

	{
		if !(.DISABLE_TITLE_BAR in opt) {
			layout.at.y = begin_box.rect.top_left.y
			layout.at.y += auto_cast ui_context.vulkan_iface.va_FontCache[0].line_height + 6
			layout.position.y = layout.at.y
		}
	}

	begin_box.lay_type = layout.type

	return true
}

//@(deferred_out = end_menu)
menu_begin :: proc(
	title: string,
	top_left: glsl.vec2 = {-1, -1},
	w_h: glsl.vec2 = {-1, -1},
	key_pointer: ^byte = nil,
	entries: ..string,
) -> (clicked_box: ^Box, ok : bool) {

 clicked_box = &UI_NilBox
 ok          = false

	title_tab: string
	if title[len(title) - 2:] == "%d" || title[len(title) - 2:] == "%p" {
		title_tab_slice := [?]string{title[:len(title) - 2], "menu_tab_", title[len(title) - 2:]}
		title_tab = strings.concatenate(title_tab_slice[:], ui_context.per_frame_arena_allocator)

	} else {
		title_tab_slice := [?]string{title, "_tab_"}
		title_tab = strings.concatenate(title_tab_slice[:], ui_context.per_frame_arena_allocator)
	}

	tab_stile := ui_context.theme.background_panel

	set_next_box_layout({.DISABLE_VERTICAL_SCROLLBAR, .DISABLE_TITLE_BAR})
	// NOTE: We hardcode 40 as height, but it should be the line height + something
	set_next_layout(top_left, {w_h.x, ui_context.vulkan_iface.va_FontCache[1].line_height + 6}, 0, auto_cast len(entries), LayoutType.FIXED)
	set_box_preferred_size({200, ui_context.vulkan_iface.va_FontCache[1].line_height + 6})
	set_next_layout_style(tab_stile)

	if window_begin(title_tab, pointer = key_pointer) {

		for entrie, idx in entries {
			set_layout_next_column(cast(u32)idx)
			if button(entrie).left_click {
    			clicked_box = get_layout_stack().parent_box.tail
    			ok = true
			}
		}

		layout := get_layout_stack()

		set_layout_reset_column()
		set_layout_reset_row()
		set_layout_next_row_col(0, 0)
		layout.at.y += layout.box_preferred_size.y
		box := make_box_from_key(
			"#frontup_panel_%p",
			layout.at,
			{w_h.x, 2},
			{.DRAW_RECT, .DRAW_BORDER},
			key_pointer,
		)

		end(true)
	}

	set_next_box_layout({.SET_WIDTH_TO_TEXT, .DISABLE_TITLE_BAR})
	// NOTE: We hardcode 60 as height, but it should be the line height + something
	set_next_layout(top_left + {0, ui_context.vulkan_iface.va_FontCache[1].line_height + 6}, w_h - {0, ui_context.vulkan_iface.va_FontCache[1].line_height - 12}, 0, 0, LayoutType.FIXED)
	//set_box_preferred_size({200, 30})
	set_next_layout_style(tab_stile)

	set_layout_ui_parent_seed(clicked_box)

	window_begin(title, pointer = key_pointer)

	return clicked_box, ok
}

// ------------------------------------------------------------------- //

end_menu :: proc(open: bool = false) {
	end(open)
}

// ------------------------------------------------------------------- //

point_intersect :: #force_inline proc(point: glsl.vec2, r2: Rect2D) -> bool {
	if (point.x >= r2.top_left.x &&
		   point.x <= r2.top_left.x + r2.size.x &&
		   point.y >= r2.top_left.y &&
		   point.y <= r2.top_left.y + r2.size.y) {
		return true
	}

	return false
}

// ----------------------------------------- end window --------------------------------------- //
// It always has to ve called after calling begin function
// Note that if begin function is called in an if( begin() ) ... fashion,
// it will automatically defer the end function at the end of scope
//
end :: proc(open: bool = false) {
	if !open {
		return
	}
	root_box := utils.get_front_stack(&ui_context.root_stack)

	if ((root_box.zindex < ui_context.last_zindex) || root_box.zindex == 0) && root_box.lay_type != .FIXED {
		ui_context.last_zindex += 1
		root_box.zindex = ui_context.last_zindex
	}

	if ui_context.render_root.first == &UI_NilBox || ui_context.render_root.first == nil  {
		ui_context.render_root.first = root_box
	} else {
		box := ui_context.render_root.first
		for ; box != ui_context.render_root.tail; box = box.next {
		}

		box.next = root_box
		root_box.prev = box
	}

	ui_context.render_root.tail = root_box
	root_box.parent = ui_context.render_root

	lay_opts: UI_Options
	if ui_context.option_stack.push_count > 0 {
		lay_opts = utils.get_front_stack(&ui_context.option_stack)
		utils.pop_stack(&ui_context.option_stack)
	}

	if ui_context.layout_stack.push_count > 0 {
		layout := get_layout_stack()
		root_box.content_rect = layout.at // - root_box.rect.top_left
		//vmem.release(get_layout_stack(), size_of(Layout))
		utils.pop_stack(&ui_context.layout_stack)
	}
	{
		box := root_box
		// TODO(sascha): Maybe reduce it to the parts of root_box where there is no content
		//
		input := consume_box_event(box)
		if input == .LEFT_CLICK || ui_context.press_target == box {
			if input == .LEFT_CLICK {
				ui_context.drag_delta = ui_context.drag_data
			} else {
				x, y := ui_context.mouse_pos.x, ui_context.mouse_pos.y
				ui_context.drag_delta = {cast(f32)x, cast(f32)y}
			}
			// this check is to resize the box
			// so we need to check for this part of the box
			//
			//if box.lay_type == .FIXED { break }
			if (ui_context.drag_data.x >= box.rect.top_left.x + box.rect.size.x - 20 &&
				   ui_context.drag_data.x <= box.rect.top_left.x + box.rect.size.x &&
				   ui_context.drag_data.y >= box.rect.top_left.y + box.rect.size.y - 20 &&
				   ui_context.drag_data.y <= box.rect.top_left.y + box.rect.size.y) {
				ui_context.resizing = true
				delta := (ui_context.drag_delta - ui_context.drag_data)
				ui_context.drag_data = ui_context.drag_delta
				ui_context.drag_delta = delta
			} else if ui_context.resizing {
				delta := (ui_context.drag_delta - ui_context.drag_data)
				ui_context.drag_data = ui_context.drag_delta
				ui_context.drag_delta = delta
			} else {
				if (ui_context.drag_delta != {0, 0} && !ui_context.resizing) {
					delta := (ui_context.drag_delta - ui_context.drag_data)
					ui_context.drag_data = ui_context.drag_delta
					ui_context.drag_delta = delta
				}
			}
		}
	}
	// We have more items than the current window height
	//
	if root_box.content_rect.y > root_box.rect.top_left.y + root_box.rect.size.y {
		event := consume_box_event(root_box)
		if event == .ARROW_UP {
			//root_box.scroll += {0, DEFAULT_SCROLL_DELTA}
		}
		if event == .ARROW_DOWN {
			//root_box.scroll -= {0, DEFAULT_SCROLL_DELTA}
		}
	} else {
		//root_box.scroll = {0, 0}
	}

	utils.pop_stack(&ui_context.root_stack)
	if ui_context.style.push_count > 0 {
		utils.pop_stack(&ui_context.style)
	}
}

// ------------------------------------------------------------------- //

checkbox :: proc( label: string, id: ^byte = nil ) -> EventResults {
 set_next_layout_style(ui_context.theme.button)
	defer utils.pop_stack(&ui_context.style)
	box: ^Box
	if id == nil {
		box = make_box(
			label,
			{-1, -1},
			{-1, -1},
			UI_Options{.DRAW_STRING, .CHECKBOX},
		)
	} else {
		box = make_box(
			label,
			{-1, -1},
			{-1, -1},
			UI_Options{.DRAW_STRING, .CHECKBOX},
			id,
		)
	}

	set_next_hover_cursor(box, glfw.HAND_CURSOR)

	input := consume_box_event(box)

	event: EventResults

	if .LEFT_CLICK == input {
		event.left_click = true
		event.left_click_hold = true
	}
	if .LEFT_CLICK_RELEASE == input {
		event.left_click = false
		event.left_click_hold = true
	}

	if box == ui_context.hover_target {
		event.left_click_hold = true
	}

	return event
}

// ------------------------------------------------------------------- //

button :: proc(label: string, id: ^byte = nil) -> EventResults {
	set_next_layout_style(ui_context.theme.button)
	defer utils.pop_stack(&ui_context.style)
	box: ^Box
	if id == nil {
		box = make_box(
			label,
			{-1, -1},
			{-1, -1},
			UI_Options{.DRAW_STRING, .DRAW_RECT, .DRAW_BORDER, .HOVER_ANIMATION},
		)
	} else {
		box = make_box(
			label,
			{-1, -1},
			{-1, -1},
			UI_Options{.DRAW_STRING, .DRAW_RECT, .DRAW_BORDER, .HOVER_ANIMATION},
			id,
		)
	}

	set_next_hover_cursor(box, glfw.HAND_CURSOR)

	input := consume_box_event(box)

	event: EventResults

	if .LEFT_CLICK == input {
		event.left_click = true
		event.left_click_hold = true
	}
	if .LEFT_CLICK_RELEASE == input {
		event.left_click = false
		event.left_click_hold = true
	}

	if box == ui_context.hover_target {
		event.left_click_hold = true
	}

	return event
}

// ------------------------------------------------------------------- //

label :: proc(label: string, id: ^byte = nil) {
	box: ^Box
	set_next_layout_style(ui_context.theme.text)
	defer utils.pop_stack(&ui_context.style)
	if id == nil {
		box = make_box_no_key(label, box_flags = UI_Options{.DRAW_STRING, .NO_CLICKABLE, .NO_HOVER})
	} else {
		box = make_box_from_key(
			label,
			box_flags = UI_Options{.DRAW_STRING, .NO_CLICKABLE, .NO_HOVER},
			key = id,
		)
	}
	event := consume_box_event(box)
}

// ------------------------------------------------------------------- //

input_field :: proc(label: string, id: ^byte = nil) {
	set_next_layout_style(ui_context.theme.input_field)
	defer utils.pop_stack(&ui_context.style)
	box: ^Box
	if id == nil {
		box = make_box(
			label,
			{-1, -1},
			{-1, -1},
			UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .INPUT_TEXT, .NO_HOVER},
		)
	} else {
		box = make_box(
			label,
			{-1, -1},
			{-1, -1},
			UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .INPUT_TEXT, .NO_HOVER},
			id,
		)
	}

	set_next_hover_cursor(box, glfw.IBEAM_CURSOR)
	event := consume_box_event(box)
	if box == ui_context.target_box {
		//ui_context.cursor_position = box.text_position
	}
}

// ------------------------------------------------------------------- //

calc_text_size :: proc(text: string, font_cache: render.FontCache) -> glsl.vec2 {
	max_text_offset: f32 = 0
	text_offset: f32 = 0

	height: f32 = 0
	line_height: f32 = auto_cast font_cache.line_height

	for i := 0; i < len(text); i += 1 {
		if text[i] == ' ' {
			text_offset += 6

			if i == len(text) - 1 && i > 0{
			 text_offset += font_cache.glyph[text[i-1] - 31].width
			}
		} else if text[i] == '\n' {
			max_text_offset = math.max(max_text_offset, text_offset)
			text_offset = 0
			height += line_height + 6
		} else if text[i] - 31 >= 96 || text[i] - 31 < 0 {
			text_offset += 10
		} else {
			glyph := font_cache.glyph[text[i] - 31]
			text_offset += glyph.advance

			if i == len(text) - 1 {
			 text_offset += glyph.width
			}
		}
	}

	// in case it have not entered on new line we do the max between them
	//
	return {math.max(max_text_offset, text_offset), height}
}

// ------------------------------------------------------------------- //

add_text :: proc(
	text: string,
	pos_start: glsl.vec2,
	width_height: glsl.vec2 = {0, 0},
	vulkan_iface: ^render.VulkanIface,
	style: StyleParam,
	font_cache: render.FontCache,
) {
	using render

	//	context.allocator = ui_context.per_frame_arena_allocator

	new_batch: Batch2D
	new_batch.vertices    = make([dynamic]Vertex2D, ui_context.per_frame_arena_allocator)
	new_batch.indices     = make([dynamic]u32, ui_context.per_frame_arena_allocator)
	new_batch.n_instances = make([dynamic]u32, ui_context.per_frame_arena_allocator)

	top_left_corner := pos_start
	n_instances: u32 = 0

	color := style.color_text

	n_indices := 6

	line_height := cast(f32)font_cache.line_height
	glyph_count := 0
	text_offset: f32 = 0

	for i := 0; i < len(text); i += 1 {

		if text[glyph_count] == ' ' {
			text_offset += 6
			//i -= 1
		} else if text[glyph_count] == '\n' {
			text_offset = 0
			top_left_corner.y += line_height + 6
			//i -= 1
		} else if text[glyph_count] - 31 >= 96 || text[glyph_count] - 31 < 0 {
			x_next := top_left_corner.x + text_offset
			y_next := top_left_corner.y
			append(
				&new_batch.vertices,
				Vertex2D {
					{x_next, y_next},
					{x_next + 8, y_next + line_height / 2},
					color,
					color,
					color,
					color,
					{3, 3},
					{3, 3},
					0.75,
					0.0,
					0,
				},
			)
			text_offset += 10
			n_instances += 1

		} else {
			glyph := font_cache.glyph[text[glyph_count] - 31]
			x_next := top_left_corner.x + text_offset + glyph.x_off + glyph.advance
			// (s.p) Workaround to avoid having the font not start centered in a pixel
			//
			x_next  = math.round_f32(x_next)
			y_next := top_left_corner.y + line_height + glyph.y_off

			bitmap_factor := glsl.vec2 {
				cast(f32)vulkan_iface.bitmap.width / cast(f32)font_cache.BitmapWidth,
				cast(f32)vulkan_iface.bitmap.height / cast(f32)font_cache.BitmapHeight,
			}

			bitmap_offset := font_cache.BitmapOffset

			glyph_start := glsl.vec2{glyph.x + bitmap_offset.x, glyph.y + bitmap_offset.y}

			glyph_end := glsl.vec2{(glyph_start.x + glyph.width), (glyph_start.y + glyph.height)}

			// This means the string is greater than the
			// max size defined by the user
			if text_offset + glyph.advance + glyph.x_off >= width_height.x && width_height.x > 0 {
				//text_offset -= font_cache.glyph[text[glyph_count-1] - 31].advance // glyph.width + glyph.x_off
				//n_instances -= 1
				break
			}

			append(
				&new_batch.vertices,
				Vertex2D {
					{x_next, y_next},
					{x_next + glyph.width, y_next + glyph.height},
					color,
					color,
					color,
					color,
					{glyph_start.x, glyph_start.y},
					{glyph_end.x, glyph_end.y},
					0,
					0,
					0,
				},
			)

			text_offset += glyph.advance// glyph.width + glyph.x_off

			n_instances += 1
		}

		glyph_count += 1
	}

	if (n_instances == 0) {return}

	append(&new_batch.indices, 0, 1, 3, 3, 2, 0)
	append(&new_batch.n_instances, n_instances)
	add_batch2D_instanced_to_group(vulkan_iface, &new_batch)

	//alloc_error := delete(new_batch.vertices)
	//CHECK_MEM_ERROR(alloc_error)
	//alloc_error  = delete(new_batch.indices)
	//CHECK_MEM_ERROR(alloc_error)
	//alloc_error  =delete(new_batch.n_instances)
	//CHECK_MEM_ERROR(alloc_error)
}

// ------------------------------------------------------------------- //

add_rect :: proc(
	top_left_corner: glsl.vec2,
	width_height: glsl.vec2,
	vulkan_iface: ^render.VulkanIface,
	style: StyleParam,
) {
	using render
	//	context.allocator = ui_context.per_frame_arena_allocator
	//Temp := vmem.arena_temp_begin(&ui_context.arena)
	//defer vmem.arena_temp_end(Temp)

	new_batch: Batch2D
	new_batch.vertices = make([dynamic]Vertex2D, ui_context.per_frame_arena_allocator)
	new_batch.indices = make([dynamic]u32, ui_context.per_frame_arena_allocator)
	new_batch.n_instances = make([dynamic]u32, ui_context.per_frame_arena_allocator)

	color_rect00 := style.color_rect00
	color_rect01 := style.color_rect01
	color_rect10 := style.color_rect10
	color_rect11 := style.color_rect11
	if style.border_thickness > 0 {
		color_rect00 = style.color_border
		color_rect01 = style.color_border
		color_rect10 = style.color_border
		color_rect11 = style.color_border
	}

	append(
		&new_batch.vertices,
		Vertex2D {
			top_left_corner,
			top_left_corner + width_height,
			color_rect00,
			color_rect01,
			color_rect10,
			color_rect11,
			{-2, -2},
			{-2, -2},
			style.corner_radius,
			style.edge_softness,
			style.border_thickness,
		},
	)

	append(&new_batch.indices, 0, 1, 3, 3, 2, 0)
	append(&new_batch.n_instances, 1)

	add_batch2D_instanced_to_group(vulkan_iface, &new_batch)

	//alloc_error := delete(new_batch.vertices)
	//CHECK_MEM_ERROR(alloc_error)
	//alloc_error = delete(new_batch.indices)
	//CHECK_MEM_ERROR(alloc_error)
	//alloc_error = delete(new_batch.n_instances)
	//CHECK_MEM_ERROR(alloc_error)
}

// ------------------------------------------------------------------- //

UI_SmoothDampAnim :: proc(animation_dt, current, target, currentVelocity, smoothTime, maxSpeed : f32) -> (smoothTime_t, currentVelocity_t, target_t, output_t : f32)
{
	smoothTime_t = math.max(smoothTime, 0.001) 
	omega       := 2. / smoothTime_t 
	x           := omega * animation_dt 
	exp         := 1. / (1. + x + 0.48 * x * x + 0.235 * x * x * x)
	change      := current - target
	originalTo  := target 

	maxChange   := maxSpeed * smoothTime_t
	change       = clamp(change, -maxChange, maxChange)
	target_t     = current - change

	temp        := (currentVelocity + omega * change) * animation_dt
	currentVelocity_t = (currentVelocity - omega * temp) * exp 

	output_t = target_t + (change + temp) * exp 

	if (originalTo - current > 0.) && (output_t > originalTo) {
		output_t = originalTo 
		currentVelocity_t = (output_t - originalTo) / animation_dt
	}

	return smoothTime_t, currentVelocity_t, target_t, output_t
}

// ------------------------------------------------------------------- //

ui_begin :: proc( animation_dt : f32 = 0.00833333333 ) {
	using render
	// Update the box position if it has been resized or moved
	// given the input from last frame
	// NOTE: Is important to do it after building everything as if
	// you try to resize when consuming the event box it will mess
	// up the relative positions of the child boxes

	ui_context.animation_dt = animation_dt
	ui_context.animation_rate = 1. - math.pow_f32(2., -30. * animation_dt)

	w_width := cast(f32)ui_context.vulkan_iface.va_SwapChain.sc_Extent.width
	w_height := cast(f32)ui_context.vulkan_iface.va_SwapChain.sc_Extent.height
	ui_context.render_root.rect = {{0, 0}, {w_width, w_height}}
	//ui_context.render_root.content_rect = {w_width, w_height}

	if ui_context.resizing && ui_context.press_target.lay_type != .FIXED {
		new_size := ui_context.press_target.rect.size + ui_context.drag_delta
		ui_context.press_target.rect.size = {
			math.min(w_width, math.max(new_size.x, MIN_WINDOW_WIDTH)),
			math.min(w_height, math.max(new_size.y, MIN_WINDOW_HEIGHT)),
		}
	} else if !ui_context.resizing &&
	   ui_context.drag_delta != {0, 0} &&
	   ui_context.press_target.lay_type != .FIXED {
		ui_context.press_target.rect.top_left += ui_context.drag_delta
	}

 	if ui_context.set_dark_theme {
	 ui_context.theme = get_default_ui_dark_style()
	} else {
	 ui_context.theme = get_default_ui_light_style()
	}
	x, y := glfw.GetCursorPos(ui_context.vulkan_iface.va_Window.w_window)
	ui_context.mouse_pos = {cast(f32)x, cast(f32)y}
}

// -----------------------------------------------------------------------------

BigStack :: struct($T: typeid) {
	items:      []T,
	push_count: int,
}

// -----------------------------------------------------------------------------

big_stack_init :: #force_inline proc(
	stk: ^$T/BigStack,
	$V: typeid,
	N: u32,
	allocator := context.allocator,
) {
	stk.items = make([]V, N, allocator)
	stk.push_count = 0
}

// -----------------------------------------------------------------------------
// NOTE: Important to note that it is a must to pass the *same* allocator as
// when you called the init function
//
big_stack_delete :: #force_inline proc(stk: ^$T/BigStack, allocator := context.allocator) {
	delete(stk.items, allocator)
}

// -----------------------------------------------------------------------------

push_stack :: #force_inline proc(stk: ^$T/BigStack($V), val: V) {
	assert(stk.push_count < len(stk.items))
	stk.items[stk.push_count] = val
	stk.push_count += 1
}

// -----------------------------------------------------------------------------

get_front_stack :: #force_inline proc(stk: ^$T/BigStack($V)) -> V {
	assert(stk.push_count > 0)
	return stk.items[stk.push_count - 1]
}

// -----------------------------------------------------------------------------

pop_stack :: #force_inline proc(stk: ^$T/BigStack($V)) {
	assert(stk.push_count > 0)
	stk.push_count -= 1
}

// -----------------------------------------------------------------------------

// ------------------------------------------------------------------- //

ui_build :: proc() {
	using render
	//tracy.ZoneS(depth = 10)
	debug_time_add_scope("ui_build", ui_context.vulkan_iface.ArenaAllocator)

	// First-depth-order traversal of our root box using stack
	//
	root_box: ^Box = ui_context.render_root
	//tmp_stack : utils.Stack(^Box, MAX_RENDER_STACK)
	tmp_stack: BigStack(^Box)
	big_stack_init(&tmp_stack, ^Box, MAX_RENDER_STACK, ui_context.per_frame_arena_allocator)

	push_stack(&tmp_stack, root_box)

	n_boxes := 0

	for tmp_stack.push_count > 0 {
	 n_boxes += 1
		box := get_front_stack(&tmp_stack)
		pop_stack(&tmp_stack)
		style := box.style

		// I put it_box.prev != box.tail in case I have some strange duplicacy
		{
		 it_box := box.tail
		 for ; it_box != box.first && it_box != nil && it_box != &UI_NilBox ; it_box = it_box.prev {
		 	 push_stack(&tmp_stack, it_box)
		 }

		 if box.first != nil && box.first != &UI_NilBox {
		 	push_stack(&tmp_stack, box.first)
		 }
		}

		if box == root_box {
			n := tmp_stack.push_count
			sort.quick_sort_proc(tmp_stack.items[:n], proc(a, b: ^Box) -> int {
				return int(b.zindex) - int(a.zindex)
			})
		}

		current_font_cache: render.FontCache

		if box.parent == root_box {
			current_font_cache = ui_context.vulkan_iface.va_FontCache[0]
		} else {
			current_font_cache = ui_context.vulkan_iface.va_FontCache[1]
		}

		// Adding draw data to render batch
		//
		if box != root_box {
			// TODO: Have to make it a variable inside a struct
			title_padding: f32 = 0
			if box.parent != root_box && !(.DISABLE_TITLE_BAR in box.flags) {
				title_padding = cast(f32)ui_context.vulkan_iface.va_FontCache[0].line_height + 6
			}

   is_window := false
			if box.parent == root_box {
    is_window = true
			}

			if ((box.rect.top_left.y >= box.parent.rect.top_left.y + title_padding) &&
			   (box.rect.top_left.y + box.rect.size.y <= box.parent.rect.top_left.y + box.parent.rect.size.y)) ||
			   is_window
			{
				/*
    if .HOVER_ANIMATION in box.flags {
     is_hover : f32 = 0.
     if box == ui_context.hover_target {
      is_hover = 1.
     }
     anim_t := (is_hover - box.animation_progress) * ui_context.animation_rate
   	 box.animation_progress += anim_t//math.max(0.00, math.min(math.abs(anim_t), 1.))
    } else {
     box.animation_progress = 1.
    }
   */

   	anim_rate : f32 = 1.
   	if .HOVER_ANIMATION in box.flags {
	   	box_animation : ^UI_AnimationData
	   	box_animation_bucket := hash.lookup_table_bucket(&ui_context.animation_data, box.key_text)

	   	for &anim in box_animation_bucket {
	   		if anim != nil && anim.id == hash.get_hash_from_key(box.key_text) {
	   			box_animation = anim
	   			break
	   		}
	   	}
	   	if box_animation != nil {
	   		anim_data : ^UI_AnimationData = box_animation

	   		anim_data.smoothTime, anim_data.currentVelocity, anim_data.target, anim_data.output = UI_SmoothDampAnim(
							anim_data.animation_dt,
							anim_data.current,
							anim_data.target,
							anim_data.currentVelocity,
							anim_data.smoothTime, 
							anim_data.maxSpeed
						)

						if box != ui_context.hover_target {
							if box.is_animating {
								anim_data.target = 0
							}
	   			if box.is_animating && anim_data.output <= anim_data.smoothTime {
	   				box.is_animating  = false
	   				anim_data.target  = 1
	   				anim_data.current = 0 
	   				anim_data.output  = 0
	   			}
	   			else if box.is_animating {
	   				anim_data.current = anim_data.output
	   			}

	   			if !box.is_animating {
	   				anim_data.output = 0
	   			}
	   		}
	   		else {
	   			anim_data.current = anim_data.output
	   		}

   			pre_box_size  := box.rect.size
   			box.rect.size += 10*(anim_data.output)
   			dt_change_size := box.rect.size - pre_box_size//glsl.vec2{abs(box.rect.size.x - pre_box_size.x), abs(box.rect.size.y - pre_box_size.y)}
   			box.rect.top_left -= dt_change_size / 2

	   		anim_rate = anim_data.output
	   	}
   	}

				if .DRAW_RECT in box.flags || ui_context.hover_target == box && !(.NO_HOVER in box.flags) {
					// I want it to have some kind of frame for the window, so the easiest way is just to check if it is a window, and if it is,
					// change the frame of the title
					//
					style_frame := style
					style.color_rect00.a *= anim_rate
					style.color_rect01.a *= anim_rate
					style.color_rect10.a *= anim_rate
					style.color_rect11.a *= anim_rate
					style.color_border.a *= anim_rate

					style_frame.border_thickness = 0

					// NOTE: This may be not the best place to place it
					// What I want to do here is to create some sort of shadow
					// so that it differenciates well from other boxes. I only
					// set it when layout_type is relative because is the only
					// way the boxes can overlap
					//
					if box.parent == root_box && box.lay_type == .RELATIVE {
						background_style := style_frame
						background_style.color_rect00 -= 0.8 * background_style.color_rect00
						background_style.color_rect01 -= 0.8 * background_style.color_rect01
						background_style.color_rect10 -= 0.8 * background_style.color_rect10
						background_style.color_rect11 -= 0.8 * background_style.color_rect11
						add_rect(
							box.rect.top_left + {10, 10},
							box.rect.size,
							ui_context.vulkan_iface,
							background_style,
						)
					}

					add_rect(box.rect.top_left, box.rect.size, ui_context.vulkan_iface, style)

					if box.parent == root_box && !(.DISABLE_TITLE_BAR in box.flags) {
						style_frame = style
						style_frame.color_rect00 *= 0.9 //rgba_to_norm(hex_rgba_to_vec4(0x5B5F97FF))
						style_frame.color_rect11 *= 0.9 //rgba_to_norm(hex_rgba_to_vec4(0x5B5F97FF))
						style_frame.color_rect01 *= 0.9 //rgba_to_norm(hex_rgba_to_vec4(0x5B5F97FF))
						style_frame.color_rect10 *= 0.9 //rgba_to_norm(hex_rgba_to_vec4(0x5B5F97FF))
						//style_frame.corner_radius = 0
						//style_frame.edge_softness = 0

						line_height := cast(f32)current_font_cache.line_height + 6
						add_rect(
							box.rect.top_left,
							{box.rect.size.x, line_height},
							ui_context.vulkan_iface,
							style_frame,
						)
					}
				}

				if .DRAW_BORDER in box.flags {
					style.border_thickness = 1.//ui_context.theme.front_panel.border_thickness
					add_rect(box.rect.top_left, box.rect.size, ui_context.vulkan_iface, style)
					// This has to be done as setting up border thickness before calling draw_rect
					// it will create a hollow rect
					//
				}

				if .CHECKBOX in box.flags {
				 style.border_thickness = ui_context.theme.front_panel.border_thickness
					add_rect(box.rect.top_left + 5, {box.rect.size.y - 10, box.rect.size.y - 10}, ui_context.vulkan_iface, style)
				}

				// NOTE: the arena allocator keeps accumulating a little bit of memory
				// even after telling it to free, maybe it has to accumulate a bigger chunk
				// of memory (maybe a page size) to free the whole chunk
				//
				if ui_context.target_box == box {
					if .INPUT_TEXT in box.flags && len(strings.to_string(ui_context.text_input)) > 0 {
					 strings.write_string(&box.text_input, strings.to_string(ui_context.text_input))
					}
				}
				if .DRAW_STRING in box.flags && !(box.parent == root_box && (.DISABLE_TITLE_BAR in box.flags)) {
					// Check for string centering
					//
					text_size: glsl.vec2
					{
						options := box.flags
						str_render := box.title_string
						if .INPUT_TEXT in box.flags && strings.builder_len(box.text_input) > 0 {
							str_render = strings.to_string(box.text_input)
						}
						text_size = calc_text_size(str_render, current_font_cache)
						//box.text_position = box.rect.top_left
						if .X_CENTERED_STRING in options || box.parent == root_box {
							line_height: f32 = cast(f32)current_font_cache.line_height
							box.text_position.x = math.floor(
								box.rect.top_left.x + (box.rect.size.x / 2 - text_size.x / 2),
							)
							box.text_position.y = math.floor(box.rect.top_left.y) // - (line_height - 6) / 2);
						} else {
							//box.text_position.x += 16 // Hardcoded padding. NOTE: Update it and make it cofigurable
							box.text_position.x = math.floor(box.text_position.x)
						}
						box.text_position.y = math.floor(box.text_position.y)

						box.rect.size.y = math.max(box.rect.size.y, text_size.y)

						if .Y_CENTERED_STRING in options && box.parent != root_box {
							box.text_position.y += 0// math.floor((box.rect.size.y / 2) - cast(f32)current_font_cache.line_height / 2)
						}

					}
					str_render := box.title_string
					if .INPUT_TEXT in box.flags && strings.builder_len(box.text_input) > 0 {
						str_render = strings.to_string(box.text_input)
					}

					if box.parent == root_box {
						style.color_text = style.color_text
					}

     if .CHECKBOX in box.flags {
      box.text_position.x += box.rect.size.y + 10
     }

					add_text(
						str_render,
						box.text_position,
						box.rect.size,
						ui_context.vulkan_iface,
						style,
						current_font_cache,
					)

					if box == ui_context.target_box && .INPUT_TEXT in box.flags {
						style.border_thickness = 1
						style.corner_radius = 1
						style.color_border = rgba_to_norm({60, 100, 100, 255})
						ui_context.cursor_position = box.text_position
						ui_context.cursor_position.x += text_size.x
						ui_context.cursor_position.y += box.rect.size.y * 0.25
						add_rect(
							ui_context.cursor_position,
							{2, box.rect.size.y - box.text_position.y * 0.5},
							ui_context.vulkan_iface,
							style,
						)
					}
				}
			}
		}
	}
	//big_stack_delete(&tmp_stack, temp_allocator)

	end_batch2D_instance_group(ui_context.vulkan_iface)

	// Reset per frame variables
	//

	strings.builder_reset(&ui_context.text_input)

	ui_context.hover_target            = &UI_NilBox
	ui_context.render_root.first       = &UI_NilBox
	ui_context.render_root.prev        = &UI_NilBox
	ui_context.render_root.next        = &UI_NilBox
	ui_context.render_root.parent      = &UI_NilBox
	ui_context.render_root.tail        = &UI_NilBox
	ui_context.layout_stack.push_count = 0
	ui_context.root_stack.push_count   = 0
	ui_context.option_stack.push_count = 0
	ui_context.style.push_count        = 0
	//ui_context.last_zindex             = 0

	clear(&ui_context.vulkan_iface.va_OsInput)
	// [s.p] Free per frame ui memory
	{
	 vmem.arena_free_all(ui_context.arena_temp)
		err := mem.free_all(ui_context.per_frame_arena_allocator)
		CHECK_MEM_ERROR(err)
	}
}

// ------------------------------------------------------------------- //

ui_init :: proc( vulkan_iface: ^render.VulkanIface ) {

	// Permanent arena
	//
	{
		ui_context.arena = new(vmem.Arena)
		err := vmem.arena_init_growing(ui_context.arena)
		CHECK_MEM_ERROR(err)
		ui_context.persistent_arena_allocator = vmem.arena_allocator(ui_context.arena)
	}
	// temporal (per-frame) arena
	//
	{
		ui_context.arena_temp = new(vmem.Arena)
		err := vmem.arena_init_growing(ui_context.arena_temp)
		CHECK_MEM_ERROR(err)
		ui_context.per_frame_arena_allocator = vmem.arena_allocator(ui_context.arena_temp)
	}

 ui_context.press_target = &UI_NilBox
 ui_context.hover_target = &UI_NilBox
 ui_context.target_box   = &UI_NilBox
 ui_context.scroll_target= &UI_NilBox

	ui_context.render_root  = new(Box, ui_context.persistent_arena_allocator)
	ui_context.last_zindex  = 0
	ui_context.text_input   = strings.builder_from_bytes(ui_context.text_store[:])
	ui_context.first_frame  = true
	ui_context.vulkan_iface = vulkan_iface

	hash.init(&ui_context.animation_data, MAX_TABLE_HASH_SIZE, ui_context.persistent_arena_allocator)
	hash.init(&ui_context.hash_boxes, MAX_TABLE_HASH_SIZE, ui_context.persistent_arena_allocator)
	hash.init(
		&ui_context.cursor_image_per_box,
		MAX_TABLE_HASH_SIZE,
		ui_context.persistent_arena_allocator,
	)

}

