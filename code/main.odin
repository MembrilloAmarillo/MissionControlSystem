package OrbitMCS

import "base:runtime"

import "core:fmt"
import "core:math"
import "core:math/big"
import "core:math/linalg/glsl"
import "core:mem"
import vmem "core:mem/virtual"
import "core:net"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "core:encoding/xml"

import "vendor:glfw"
import vk "vendor:vulkan"

import "render"
import hash "simple_hash"
import "utils"
import xtce "xtce_parser"

// --------------------------------------------------- TODO -------------------------------------------- //
// 1. Keep working on xtce parser
// 2. PLUTO Language for procedures
// 3. Design UI structure for data
// 4. Communications UDP and TCP
// -----------------------------------------------------------------------------

CHECK_MEM_ERROR :: proc(error: vmem.Allocator_Error) {
 switch error {
  case .None:
  break
  case .Out_Of_Memory, .Invalid_Pointer, .Invalid_Argument, .Mode_Not_Implemented:
  {
   fmt.println("[ERROR] Allocation error ", error)
   panic("[ERROR] Mem error")
  }
  case:
  {}
 }
}

// --------------------------------------------------- signaling -------------------------------------------- //

import "core:c/libc"

handle_ctrl_c :: proc "c" (val: i32) {
 //fmt.println("CTRL-C Ocurred")
}

// --------------------------------------------------- Application data structures -------------------------------------------- //

APP_SHOW_FLAGS :: enum i32 {
 SHOW_NONE,
 SHOW_HOME,
 SHOW_TC,
 SHOW_TM,
 SHOW_CONN,
 SHOW_DB,
}

// -----------------------------------------------------------------------------

db_menu_items :: struct {
 // This is to have stored the current tab we are in
 //
 current_tab: ^Box,

 // This is a maybe, to better access all the elements,
 // still not sure if it is viable as it does lose hierarchy
 //
 menu_list:   [dynamic]utils.tuple(string, xml.Element),

 // This is the start node when listing all database, if we do not
 // keep in check where is the node start of the row it will have
 // really bad performance issues
 //
 start_node:  ^utils.node_tree(utils.tuple(string, xml.Element)),
}

// --------------------------------------------------------------- //

TC_menu_items :: struct {
 // This is to have stored the current tab we are in
 //
 current_tc:    ^Box,

 // Hash table containing the value (on string) of the arguments used for
 // each metacommand in order to send them later when the user requires
 //
 arg_value_map: hash.Table(string, string),
}

// --------------------------------------------------------------- //

net_state :: struct {
 ip:              string,
 port:            int,
 socket_type:     net.Any_Socket,
 buffer:          []u8,
 buffer_off:      int,
 total_bytes:     int,
 send_buffer:     bool,
 socket_function: enum {
  RECEIVE_SOCKET,
  SEND_SOCKET,
 },
}

//tcp_net_state :: net_state{ ip = "", port = 8080, socket_type = net.TCP_Socket{} }
//udp_net_state :: net_state{ ip = "", port = 8090, socket_type = net.UDP_Socket{} }

// --------------------------------------------------------------- //

box_constructor :: struct {
 rect:  Rect2D,
 text:  string,
 style: StyleParam,
 key:   ^byte,
 flags: UI_Options,
}

// --------------------------------------------------------------- //

orbitmcs_state :: struct {
 enable_debug:   bool,
 SHOW_FLAGS:     APP_SHOW_FLAGS,
 threading:      ^thread_pool,
 tcp_server:     ^net_state,
 udp_server:     ^net_state,
 tcp_client:     ^net_state,
 udp_client:     ^net_state,
 thread_lock:    sync.Mutex,
 menu_db:        db_menu_items,
 menu_tc:        TC_menu_items,
 tm_nodes:       ^utils.node_tree(utils.tuple(string, xml.Element)),
 tm_rec_buffer:  [dynamic]u8,
 tm_rec_sizes:   [dynamic]int,
 shutdown:       bool,
 hovering_boxes: utils.queue(box_constructor, 216), // IMPORTANT!!: If you put a bigger value (for example 4096) odin compiler (llvm function) will crash
}

// --------------------------------------------------------------- //

xtce_state :: struct {
 schema:        ^xtce.xsd_schema,
 system:        ^xtce.handler,
 schema_path:   string,
 system_path:   string,
 parse_proc:    proc(path: string, allocator: mem.Allocator) -> ^xtce.xsd_schema,
 validate_proc: proc(
  path: string,
  schema: ^xtce.xsd_schema,
  allocator: mem.Allocator,
 ) -> ^xtce.handler,
}

// --------------------------------------------------------------- //

PanelTree :: struct {
 parent, left, right, next, tail: ^PanelTree,
 pct_of_parent:                   f32,
 rect:                            Rect2D,
 axis:                            u32,
}

// --------------------------------------------------------------- //

handle_msg_tcp :: proc(t: net.TCP_Socket) {

}

// --------------------------------------------------------------- //

net_start_server :: proc(t: thread.Task) {
 net_state := cast(^net_state)t.data
 addr, ok := net.parse_ip4_address(net_state.ip)
 net_state.buffer = make([]u8, 2048)

 switch net_server in net_state.socket_type {
  case net.UDP_Socket:
  {
   endpoint := net.Endpoint {
    address = addr,
    port    = net_state.port,
   }
   send_addr, ok := net.parse_ip4_address("127.0.0.1")
   send_enpoint := net.Endpoint {
    address = send_addr,
    port    = 8091,
   }
   err: net.Network_Error
   net_state.socket_type, err = net.make_bound_udp_socket(addr, net_state.port)
   if err != nil {
    fmt.println("[ERROR] Failed listening on udp")
   }
   fmt.printfln("Listening on UDP: %s", net.endpoint_to_string(endpoint))
   for !app_state.shutdown {

    if net_state.socket_function == .SEND_SOCKET {
     if net_state.send_buffer {
      writen, err := net.send_udp(
       net_state.socket_type.(net.UDP_Socket),
       net_state.buffer[:net_state.buffer_off],
       send_enpoint,
      )
      if err != nil {
       fmt.println("[ERROR UDP] Could not send bytes", writen)
      }
      //fmt.println(app_state.udp_server.buffer)
      net_state.send_buffer = false

      net_state.total_bytes += auto_cast math.ceil(cast(f32)net_state.buffer_off / 8)
      //runtime.mem_zero(&app_state.udp_server.buffer, 2048)
      net_state.buffer_off = 0
     }
    } else {
     buff: [2048]u8
     bytes_read, endpoint, err_accept := net.recv_udp(
      net_state.socket_type.(net.UDP_Socket),
      buff[:],
     )
     if err_accept != nil {
      //fmt.println("[ERROR] Failed to accept UDP connection", endpoint, err_accept)
     } else {
      fmt.println(
       "[INFO] Accepting connection, bytes read",
       bytes_read,
       endpoint,
      )
      fmt.println("Buffer", buff[:bytes_read])
      //new_buf := make([]u8, bytes_read)
      //runtime.mem_copy(new_buf, buff, bytes_read)
      append(&app_state.tm_rec_buffer, ..buff[:bytes_read])
      append(&app_state.tm_rec_sizes, bytes_read)
      net_state.total_bytes += bytes_read
     }
    }
    //thread.create_and_start_with_poly_data(cli, handle_msg_tcp)
    //AddProcToPool(&app_state.threading, handle_msg_tcp, rawptr(&cli))
   }
   fmt.println("Closed socket")
  }
  case net.TCP_Socket:
  {
   if !ok {
    fmt.println("[ERROR] Wrong ip address", net_state.ip)
    return
   }
   endpoint := net.Endpoint {
    address = addr,
    port    = net_state.port,
   }
   if net_state.socket_function == .RECEIVE_SOCKET {
    sock, err := net.listen_tcp(endpoint)
    if err != nil {
     fmt.println("[ERROR] Failed listening on TCP")
    }
    fmt.printfln("Listening on TCP: %s", net.endpoint_to_string(endpoint))
    for !app_state.shutdown {
     cli, _, err_accept := net.accept_tcp(sock)
     if err_accept != nil {
      //fmt.println("[ERROR] Failed to accept TCP connection")
     } else {
      fmt.println("[INFO] Accepting connection", cli)
     }
    }
    fmt.println("Closed socket")
    net.close(sock)
   }
  }
 }
}

// --------------------------------------------------- Helper functions -------------------------------------------- //

push_panel_tree :: proc(p: ^PanelTree, parent: ^PanelTree) {
 if parent.next == nil {
  parent.next = p
 } else {
  b: ^PanelTree = parent.next
  for ; b != parent.tail && b != nil; b = b.right {}
  b.right = p
  p.left = b
 }
 parent.tail = p
 p.parent = parent
}

consume_app_state_events :: proc(state: ^orbitmcs_state) {
 for input, idx in ui_context.vulkan_iface.va_OsInput {
  if .F1 in input.type {
   state.enable_debug = !state.enable_debug
  }
 }
}

// --------------------------------------------------- OrbitMCS ui function -------------------------------------------- //

GetArgumentDeclSizeInBits :: proc(system: ^xtce.space_system, val: string) -> int {
 ref_arg_decl, ref_par_decl := xtce.GetArgumentDecl(system, val)
 size_in_bits := 0
 buff: [64]u8

 #partial switch arg_t in ref_arg_decl {
  case xtce.IntegerArgumentType:
  {
   size_in_bits = cast(int)arg_t.base.t_sizeInBits.t_restriction.integer
  }
  case xtce.FloatArgumentType:
  {
   size_in_bits = cast(int)arg_t.base.t_sizeInBits.t_restriction.t_restriction.integer
  }
  case xtce.EnumeratedArgumentType:
  {
   #partial switch encod_t in arg_t.base.base.t_choice_0 {
    case xtce.IntegerDataEncodingType:
    {
     size_in_bits = cast(int)encod_t.t_sizeInBits.t_restriction.integer
    }
   }
  }
  case xtce.ArrayArgumentType:
  {
   type_ref := arg_t.base.t_arrayTypeRef.t_restriction.val
   array_ref, par_ref := xtce.GetArgumentDecl(system, type_ref)
   #partial switch ref_t in array_ref {
    case xtce.IntegerArgumentType:
    {
     size_in_bits = cast(int)ref_t.base.t_sizeInBits.t_restriction.integer
    }
   }
  }
 }

 if size_in_bits > 0 {
  return size_in_bits
 }

 #partial switch arg_t in ref_par_decl {
  case xtce.IntegerParameterType:
  {
   size_in_bits = cast(int)arg_t.base.t_sizeInBits.t_restriction.integer
  }
  case xtce.FloatParameterType:
  {
   size_in_bits = cast(int)arg_t.base.t_sizeInBits.t_restriction.t_restriction.integer
  }
  case xtce.EnumeratedParameterType:
  {
   #partial switch encod_t in arg_t.base.base.t_choice_0 {
    case xtce.IntegerDataEncodingType:
    {
     size_in_bits = cast(int)encod_t.t_sizeInBits.t_restriction.integer
    }
   }
  }
  case xtce.ArrayParameterType:
  {
   type_ref := arg_t.base.t_arrayTypeRef.t_restriction.val
   array_ref, par_ref := xtce.GetArgumentDecl(system, type_ref)
   #partial switch ref_t in array_ref {
    case xtce.IntegerArgumentType:
    {
     size_in_bits = cast(int)ref_t.base.t_sizeInBits.t_restriction.integer
    }
    case xtce.EnumeratedArgumentType:
    {
     //size_bits = "EnumeratedVal"
     //#partial switch encod_t in ref_t.base.base.t_choice_0 {
     //  case xtce.IntegerDataEncodingType : {
     //    encoding = encod_t.t_encoding.t_restriction.val
     //  }
     //}
    }
   }
   #partial switch ref_t in par_ref {
    case xtce.IntegerParameterType:
    {
     size_in_bits = cast(int)ref_t.base.t_sizeInBits.t_restriction.integer
    }
    case xtce.EnumeratedParameterType:
    {
     //size_bits = "EnumeratedVal"
     //#partial switch encod_t in ref_t.base.base.t_choice_0 {
     //  case xtce.IntegerDataEncodingType : {
     //    encoding = encod_t.t_encoding.t_restriction.val
     //  }
     //}
    }
   }
  }
 }
 return size_in_bits
}

// --------------------------------------------------------------------------------------------------------------------- //

unpack_bits :: proc(buffer: []u8, bit_offset: ^u64, bit_size: u64) -> int {
 value := 0
 end_bit := bit_offset^ + bit_size

 assert(end_bit <= u64(len(buffer)) * 8, "Buffer underflow during unpack")

 for i: u64 = 0; i < bit_size; i += 1 {
  current_bit := bit_offset^ + i
  byte_pos := current_bit / 8
  bit_pos := current_bit % 8

  // MSB-first extraction (network convention)
  bit := (buffer[byte_pos] >> (7 - bit_pos)) & 0x01
  value = (value << 1) | int(bit)
 }

 bit_offset^ += bit_size
 return value
}


// --------------------------------------------------------------------------------------------------------------------- //

pack_bits :: proc(buffer: []u8, bit_offset: ^u64, value, bit_size: u64) {
 for i in 0 ..< bit_size {
  byte_pos: u64 = bit_offset^ / 8.0
  bit_pos: u64 = bit_offset^ % 8.0

  bit: u8 = cast(u8)((value >> (bit_size - 1 - i)) & 0x01)

  //buffer[byte_pos] |= (bit << (7 - bit_pos))
  buffer[byte_pos] = (buffer[byte_pos] & ~(1 << (7 - bit_pos))) | (bit << (7 - bit_pos))

  bit_offset^ += 1
 }
}

// --------------------------------------------------------------------------------------------------------------------- //

orbit_show_tc_center :: proc(rect: Rect2D, handler: ^xtce.handler) {
 /*
    An Idea: I can have two columns, one to select the command, and the other one
    to show all the fields, that would make it really easy to navigate and far more
    efficient to use
  */
 @(static) command_to_show: xtce.MetaCommandType
 @(static) system_name: ^xtce.space_system
 ui_vspacer(15.)
 row := begin_next_layout_scrollable_section(0, get_layout_stack().box_preferred_size)

 tmp_stack: utils.Stack(^xtce.space_system, 256)
 utils.push_stack(&tmp_stack, &handler.system)

 for tmp_stack.push_count > 0 {
  system := utils.get_front_stack(&tmp_stack)
  utils.pop_stack(&tmp_stack)

  for it := system.next; it != nil; it = it.right {
   utils.push_stack(&tmp_stack, auto_cast it)
  }
  for CommandType in xtce.GetMetaCommandSetType(system.element) {
   #partial switch Command in CommandType {
    case xtce.MetaCommandType:
    {
     CommandName := Command.base.t_name.t_restriction.val
     NameConcat := strings.concatenate(
      {CommandName, "#_command_", CommandName, "_%p"},
      ui_context.per_frame_arena_allocator,
     )
     {
      set_next_layout_style(ui_context.theme.button)
      defer utils.pop_stack(&ui_context.style)
      box := make_box(
       NameConcat,
       {-1, -1},
       {-1, -1},
       UI_Options{.DRAW_STRING, .DRAW_RECT, .DRAW_BORDER, .HOVER_ANIMATION},
       cast(^byte)system,
      )
      set_next_hover_cursor(box, glfw.HAND_CURSOR)
      input := consume_box_event(box)

      event: EventResults

      if .LEFT_CLICK == input {
       event.left_click = true
       event.left_click_hold = true
       app_state.menu_tc.current_tc = box
       system_name = system
      }
      if .LEFT_CLICK_RELEASE == input {
       event.left_click = false
       event.left_click_hold = true
      }

      if box == ui_context.hover_target {
       event.left_click_hold = true
      }

      if event.left_click {
       command_to_show = Command
      }
     }
     ui_vspacer(2.)
    }
   }
  }
 }

 end_next_layout_scrollable_section()

 {
  set_layout_ui_parent_seed(app_state.menu_tc.current_tc)
  {
   layout := get_layout_stack()
   style := ui_context.theme.background_panel
   style.color_rect00 *= 0.96
   style.color_rect01 *= 0.96
   style.color_rect10 *= 0.96
   style.color_rect11 *= 0.96
   style.border_thickness = 0
   set_next_layout_style(style)
   defer pop_layout_style()
   make_box(
    "#_background_%p",
    rect.top_left + {rect.size.x * 0.4, layout.position.y - rect.top_left.y},
    {rect.size.x * 0.6, rect.size.y - layout.position.y},
    {.DRAW_RECT, .DRAW_BORDER, .NO_CLICKABLE, .NO_HOVER},
    cast(^byte)app_state.menu_tc.current_tc,
   )
  }

  ui_hspacer(25.)
  row_it: u32 = 0
  set_layout_reset_row()
  set_layout_next_column(1)
  label("-- Arguments --#_arg_fill_column_%d", cast(^byte)&row_it)
  row_it += 1
  set_layout_next_row(row_it)

  base_command := command_to_show.t_BaseMetaCommand
  base_command_list: [dynamic]xtce.MetaCommandType = make(
   [dynamic]xtce.MetaCommandType,
   ui_context.per_frame_arena_allocator,
  )
  append(&base_command_list, command_to_show)
  defer delete(base_command_list)

  base_command_type := xtce.GetBaseMetaCommand(
   system_name,
   command_to_show.t_BaseMetaCommand.t_metaCommandRef.t_restriction.val,
  )
  if len(base_command_type.base.t_name.t_restriction.val) > 0 {
   append(&base_command_list, base_command_type)
   for len(base_command_type.base.t_name.t_restriction.val) > 0 {
    base_command_type = xtce.GetBaseMetaCommand(
     system_name,
     base_command_type.t_BaseMetaCommand.t_metaCommandRef.t_restriction.val,
    )
    if len(base_command_type.base.t_name.t_restriction.val) > 0 {
     append(&base_command_list, base_command_type)
    }
   }
  }
  slice.reverse(base_command_list[:])
  for command in base_command_list {
   for &arg in command.t_ArgumentList.t_Argument {
    field_name := [?]string {
     arg.base.t_name.t_restriction.val,
     "#_arg_name",
     arg.base.t_name.t_restriction.val,
     "_%d",
    }
    ui_vspacer(2.)
    label(
     strings.concatenate(field_name[:], ui_context.per_frame_arena_allocator),
     cast(^byte)&row_it,
    )
    row_it += 1
    ui_vspacer(2.)
    set_layout_next_row(row_it)
    style := ui_context.theme.input_field
    style.color_border *= 0.2
    style.color_rect00 *= 0.90
    style.color_rect01 *= 0.90
    style.color_rect10 *= 0.90
    style.color_rect11 *= 0.90
    style.color_text *= 0.5
    set_next_layout_style(style)
    box := make_box_from_key(
     text = "Set Input#_input_field_%d",
     box_flags = UI_Options {
      .DRAW_RECT,
      .DRAW_BORDER,
      .DRAW_STRING,
      .INPUT_TEXT,
      .NO_HOVER,
     },
     key = cast(^byte)&row_it,
    )
    {
     set_next_hover_cursor(box, glfw.IBEAM_CURSOR)
     event := consume_box_event(box)
     if box == ui_context.target_box {
      event = .LEFT_CLICK
     }
    }
    {
     value: string
     pointer := uintptr(&arg)
     buffer: [1024]u8
     pointer_string := strconv.itoa(buffer[:], cast(int)pointer)
     val_bucket := hash.lookup_table_bucket(
      &app_state.menu_tc.arg_value_map,
      pointer_string,
     )
     for v in val_bucket {
      if len(v) > 0 {
       value = v
      }
     }
     if len(value) == 0 {
      hash.insert_table(
       &app_state.menu_tc.arg_value_map,
       pointer_string,
       strings.to_string(box.text_input),
      )
     } else {
      value = strings.to_string(box.text_input)
      hash.delete_key_value_table(
       &app_state.menu_tc.arg_value_map,
       pointer_string,
       value,
      )
      hash.insert_table(
       &app_state.menu_tc.arg_value_map,
       pointer_string,
       strings.to_string(box.text_input),
      )
     }
    }
    ui_pop_style()
    row_it += 1
    set_layout_next_row(row_it)
   }
  }
  unset_layout_ui_parent_seed()
 }

 // ============ Send Button ============== //
 {
  send_button_rect := rect
  send_button_rect.top_left += rect.size - {450, 50}
  send_button_rect.size = {400, 30}
  {
   style := ui_context.theme.button
   style.color_rect00 = rgba_to_norm(hex_rgba_to_vec4(0xEF6024FF))
   style.color_rect01 = rgba_to_norm(hex_rgba_to_vec4(0xEF6024FF))
   style.color_rect10 = rgba_to_norm(hex_rgba_to_vec4(0xEF6024FF))
   style.color_rect11 = rgba_to_norm(hex_rgba_to_vec4(0xEF6024FF))

   set_next_layout_style(style)
   defer pop_layout_style()
   box := make_box_no_key(
    "SEND",
    send_button_rect.top_left,
    send_button_rect.size,
    {.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .HOVER_ANIMATION},
   )
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

   if event.left_click {
    len_arg := 0
    for &arg in command_to_show.t_ArgumentList.t_Argument {
     value: string
     pointer := uintptr(&arg)
     buffer: [1024]u8
     pointer_string := strconv.itoa(buffer[:], cast(int)pointer)
     val_bucket := hash.lookup_table_bucket(
      &app_state.menu_tc.arg_value_map,
      pointer_string,
     )
     for v in val_bucket {
      if len(v) > 0 {
       value = v
      }
     }

     if app_state.udp_client.buffer_off >= 2047 {
      break
     }
     value_int := strconv.atoi(value)
     SizeInBits := GetArgumentDeclSizeInBits(
      system_name,
      arg.t_argumentTypeRef.t_restriction.val,
     )
     pack_bits(
      app_state.udp_client.buffer[:],
      auto_cast &app_state.udp_client.buffer_off,
      auto_cast value_int,
      auto_cast SizeInBits,
     )
     //libc.memcpy(&app_state.udp_client.buffer[app_state.udp_client.buffer_off], cast(rawptr)&value_int, auto_cast SizeInBits)
    }
    app_state.udp_client.send_buffer = true
   }
  }
 }
}


// ---------------------------------------------------------------------------------------------------------------------- //

push_hovering_boxes_for_rendering :: proc(
 rect: Rect2D,
 tex: string,
 st: StyleParam,
 key: ^byte = nil,
 flags: UI_Options = {.NONE},
) {
 box: box_constructor = {
  rect  = rect,
  text  = tex,
  style = st,
  key   = key,
  flags = flags,
 }

 utils.PushQueue(&app_state.hovering_boxes, box)
}

// ---------------------------------------------------------------------------------------------------------------------- //


// We set it as global as long as Im not sure where to put this
//
TmContainerExpandList: []bool

// ---------------------------------------------------------------------------------------------------------------------- //

get_param_from_ref_entry :: proc(
 system: string,
 it: ^utils.node_tree(utils.tuple(string, xml.Element)),
 xml_handler: ^xtce.handler,
) -> ^utils.node_tree(utils.tuple(string, xml.Element)) {
 type_decl_it: ^utils.node_tree(utils.tuple(string, xml.Element))
 loop : for attr in it.element.second.attribs {
  if attr.key == "parameterRef" {
   type_decl_it = xtce.SearchTypeDeclInSystem("UCF", attr.val, xml_handler)

   if type_decl_it != nil {
    for attr2 in type_decl_it.element.second.attribs {
     if attr2.key == "parameterTypeRef" {
      type_decl_it = xtce.SearchTypeDeclInSystem("UCF", attr2.val, xml_handler)
      break loop 
     }
    }
   }
  }
 }

 return type_decl_it
}

// ---------------------------------------------------------------------------------------------------------------------- //

// type_of_container :: can be xtce.BASE_CONTAINER_TYPE or xtce.CONTAINER_REF_ENTRY_TYPE
get_base_containers :: proc(
 node: ^utils.node_tree(utils.tuple(string, xml.Element)),
 type_of_container: string,
 xml_handler: ^xtce.handler,
) -> [dynamic]^utils.node_tree(utils.tuple(string, xml.Element)) {

 base_containers: [dynamic]^utils.node_tree(utils.tuple(string, xml.Element)) = make(
  [dynamic]^utils.node_tree(utils.tuple(string, xml.Element)),
  context.temp_allocator,
 )

 tmp_stack: BigStack(^utils.node_tree(utils.tuple(string, xml.Element)))
 big_stack_init(
  &tmp_stack,
  ^utils.node_tree(utils.tuple(string, xml.Element)),
  126 << 10,
  context.temp_allocator,
 )
 defer big_stack_delete(&tmp_stack, context.temp_allocator)

 push_stack(&tmp_stack, node)

 loop : for tmp_stack.push_count > 0 {
  it := get_front_stack(&tmp_stack)
  pop_stack(&tmp_stack)

  for it2 := it.next; it2 != nil; it2 = it2.right {
   push_stack(&tmp_stack, it2)
  }

  if it.element.first == type_of_container {
   type_decl_it: ^utils.node_tree(utils.tuple(string, xml.Element))
   for attr in it.element.second.attribs {
    if attr.key == "containerRef" {
     type_decl_it = xtce.SearchTypeDeclInSystem("UCF", attr.val, xml_handler)
     if type_decl_it != nil {
      append(&base_containers, type_decl_it)
      // Process this node in case it has an embedded base container
      //
      push_stack(&tmp_stack, type_decl_it)
     }
    }
   }
  }
 }

 return base_containers
}

// ---------------------------------------------------------------------------------------------------------------------- //

get_param_entry_list :: proc(
 node: ^utils.node_tree(utils.tuple(string, xml.Element)),
 xml_handler: ^xtce.handler,
) -> [dynamic]utils.tuple(string, ^utils.node_tree(utils.tuple(string, xml.Element))) {
 parameters: [dynamic]utils.tuple(string, ^utils.node_tree(utils.tuple(string, xml.Element))) =
 make(
  [dynamic]utils.tuple(string, ^utils.node_tree(utils.tuple(string, xml.Element))),
  context.temp_allocator,
 )

 tmp_stack: BigStack(^utils.node_tree(utils.tuple(string, xml.Element)))
 big_stack_init(
  &tmp_stack,
  ^utils.node_tree(utils.tuple(string, xml.Element)),
  126 << 10,
  context.temp_allocator,
 )
 defer big_stack_delete(&tmp_stack, context.temp_allocator)

 push_stack(&tmp_stack, node)

 for tmp_stack.push_count > 0 {
  it := get_front_stack(&tmp_stack)
  pop_stack(&tmp_stack)

  for it2 := it.next; it2 != nil; it2 = it2.right {
   push_stack(&tmp_stack, it2)
  }

  if it.element.first == xtce.PARAMETER_REF_ENTRY_TYPE {
   type_decl_it := get_param_from_ref_entry("UCF", it, xml_handler)
   append(
    &parameters,
    utils.tuple(string, ^utils.node_tree(utils.tuple(string, xml.Element))) {
     it.element.second.attribs[0].val,
     type_decl_it,
    },
   )
  } else if it.element.first == xtce.CONTAINER_REF_ENTRY_TYPE {
   base_containers := get_base_containers(it, xtce.CONTAINER_REF_ENTRY_TYPE, xml_handler)
   for base in base_containers {
    push_stack(&tmp_stack, base)
   }
   delete(base_containers)
  } else if it.element.first == xtce.BASE_CONTAINER_TYPE {
   base_containers := get_base_containers(it, xtce.BASE_CONTAINER_TYPE, xml_handler)
   for base in base_containers {
    push_stack(&tmp_stack, base)
   }
   delete(base_containers)
  }
 }

 return parameters
}

// ---------------------------------------------------------------------------------------------------------------------- //

get_param_size :: proc(node: ^utils.node_tree(utils.tuple(string, xml.Element))) -> int {
 size := 0

 tmp_stack: BigStack(^utils.node_tree(utils.tuple(string, xml.Element)))
 big_stack_init(
  &tmp_stack,
  ^utils.node_tree(utils.tuple(string, xml.Element)),
  126 << 10,
  context.temp_allocator,
 )
 defer big_stack_delete(&tmp_stack, context.temp_allocator)

 push_stack(&tmp_stack, node)

 size_found := false

 for tmp_stack.push_count > 0 && !size_found {
  it := get_front_stack(&tmp_stack)
  pop_stack(&tmp_stack)

  for attr in it.element.second.attribs {
   if attr.key == "sizeInBits" {
    size = strconv.atoi(attr.val)
    size_found = true
   }
  }

  for it2 := it.next; it2 != nil; it2 = auto_cast it2.right {
   push_stack(&tmp_stack, it2)
  }
 }

 return size
}

// ---------------------------------------------------------------------------------------------------------------------- //

check_param_correctness :: proc(
 buffer: []u8,
 node: ^utils.node_tree(utils.tuple(string, xml.Element)),
 xml_handler: ^xtce.handler,
 row: ^int,
) -> bool
{
 tmp_stack: utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 4096)

 entry_list_params: [dynamic]utils.tuple(
  string,
  ^utils.node_tree(utils.tuple(string, xml.Element)),
 ) = make(
  [dynamic]utils.tuple(string, ^utils.node_tree(utils.tuple(string, xml.Element))),
  context.temp_allocator,
 )
 //defer delete(entry_list_params)

 restriction_criterias: [dynamic]utils.tuple(string, string) = make(
  [dynamic]utils.tuple(string, string),
  context.temp_allocator,
 ) // value, param name
 //defer delete(restriction_criterias)


 utils.push_stack(&tmp_stack, node)

 list := get_param_entry_list(node, xml_handler)
 append(&entry_list_params, ..list[:])
 delete(list)

 for tmp_stack.push_count > 0 {
  it := utils.get_front_stack(&tmp_stack)
  utils.pop_stack(&tmp_stack)

  for it2 := it.next; it2 != nil; it2 = it2.right {
   utils.push_stack(&tmp_stack, it2)
  }

  if it.element.first == xtce.COMPARISON_TYPE {
   restriction: utils.tuple(string, string)
   for attr in it.element.second.attribs {
    if attr.key == "value" {
     restriction.first = attr.val
    } else if attr.key == "parameterRef" {
     restriction.second = attr.val
    }
   }
   append(&restriction_criterias, restriction)
  }
 }

 current_buffer_off := 0
 is_container := true

 if len(entry_list_params) == 0 {
  return false
 }

 restriction_criterias_met : []bool = make([]bool, len(restriction_criterias), context.temp_allocator)
 //defer delete(restriction_criterias_met, context.temp_allocator)

 for entry in entry_list_params {
  size := get_param_size(entry.second)

  if current_buffer_off + size >= len(buffer) {
   is_container = false
   break
  }

  value := unpack_bits(buffer[:], auto_cast &current_buffer_off, auto_cast size)
  buffer_store: [64]u8
  buf := strconv.itoa(buffer_store[:], value)
  current_buffer_off += size

  for restriction, idx in restriction_criterias {
   if restriction.second == entry.first {
    if buf != restriction.first {
     is_container = false
    }
    else {
     restriction_criterias_met[idx] = true
    }
   }
  }

  if !is_container {
   break
  }
 }

 for res in restriction_criterias_met {
  if res == false {
   is_container = false
   break
  }
 }

 current_buffer_off = 0
 if is_container {

  {
   label_name := strings.concatenate(
    {"TM: ", node.element.second.attribs[0].val, "#_Sequence_Name_%p"},
   )
   style := ui_context.theme.text
   style.color_text = rgba_to_norm(hex_rgba_to_vec4(0x43302FF))
   set_next_layout_style(style)

   set_layout_next_font(22, "./data/font/RobotoMonoBold.ttf")
   label(label_name, cast(^byte)node)
   unset_layout_font()
   ui_pop_style()

   set_next_layout_horizontal()

   // Put values

   // reset layout for next row

   row^ += 1
   set_next_layout_vertical()
  }

  for entry in entry_list_params {
   size := get_param_size(entry.second)

   if current_buffer_off + size >= len(buffer) {
    break
   }

   value := unpack_bits(buffer[:], auto_cast &current_buffer_off, auto_cast size)
   buffer_store: [64]u8
   buf := strconv.itoa(buffer_store[:], value)

   // UI Processing
   {
    buff: [64]u8
    label_name := strings.concatenate(
     {
      entry.first,
      " -VALUE: ",
      buf,
      "  -SIZE: ",
      strconv.itoa(buff[:], size),
      " bits#_name_",
      strconv.itoa(buff[:], row^),
      "%p",
     },
    )
    style := ui_context.theme.text
    style.color_text = rgba_to_norm(hex_rgba_to_vec4(0x02343FF))
    set_next_layout_style(style)

    set_layout_next_font(16, "./data/font/RobotoMono.ttf")
    label(label_name, cast(^byte)entry.second)
    unset_layout_font()
    ui_pop_style()

    set_next_layout_horizontal()

    // Put values

    // reset layout for next row

    row^ += 1
    set_next_layout_vertical()
   }
  }
 }

 return is_container
}

// ---------------------------------------------------------------------------------------------------------------------- //

//TODO: OPTIMIZE
//
orbit_show_tm_received :: proc(rect: Rect2D, xml_handler: ^xtce.handler) {

 @(static) tm_update_node : bool = true

 render.debug_time_add_scope("TM Reception", ui_context.vulkan_iface.ArenaAllocator)

 if tm_update_node {
  tm_update_node = false
  tmp_stack: BigStack(^utils.node_tree(utils.tuple(string, xml.Element)))
  big_stack_init(
   &tmp_stack,
   ^utils.node_tree(utils.tuple(string, xml.Element)),
   64 << 10,
   context.temp_allocator,
  )
  defer big_stack_delete(&tmp_stack, context.temp_allocator)
  push_stack(&tmp_stack, &xml_handler.tree_eval)
  for tmp_stack.push_count > 0 {
   xml_node := get_front_stack(&tmp_stack)
   pop_stack(&tmp_stack)

   for it := xml_node.next; it != nil; it = it.right {
    push_stack(&tmp_stack, it)
   }
   if xml_node.element.first == xtce.SEQUENCE_CONTAINER_TYPE {
    if app_state.tm_nodes == nil {
     app_state.tm_nodes = xml_node
    }
    else {
     utils.push_node(xml_node, app_state.tm_nodes)
    }
   }
  }
 }

 layout := get_layout_stack()
 limit_on_screen := false

 row_start_it := begin_next_layout_scrollable_section(0, layout.box_preferred_size)
 defer end_next_layout_scrollable_section(0)

 buffer_off := 0
 row        := 0

 node_it := &xml_handler.tree_eval
 found_container := false

 // =========== Set UI Title ================= //
 {
  style := ui_context.theme.text
  style.color_text = rgba_to_norm(hex_rgba_to_vec4(0x432243FF))
  set_next_layout_style(style)

  set_layout_next_font(22, "./data/font/0xProtoNerdFontMono-Bold.ttf")
  label("TM LOGGER", cast(^byte) xml_handler)
  unset_layout_font()
  ui_pop_style()
 }

 sync.mutex_lock(&app_state.thread_lock)
 defer sync.mutex_unlock(&app_state.thread_lock)

 to_destroy := make([dynamic]bool, len(app_state.tm_rec_sizes), context.temp_allocator)

 for buffer_size, idx in app_state.tm_rec_sizes {

  buffer := app_state.tm_rec_buffer[buffer_off:buffer_off + buffer_size]
  buffer_off += buffer_size

  is_container := check_param_correctness(buffer, app_state.tm_nodes, xml_handler, &row)
  if is_container do continue;

  found_container = false
  for xml_node := app_state.tm_nodes.next; xml_node != nil && !found_container; xml_node = xml_node.right {
   found_container = check_param_correctness(buffer, xml_node, xml_handler, &row)
  }

  if !found_container {
   to_destroy[idx] = true
  }
 }

 buffer_off = 0
 for destroy, idx in to_destroy {
   size := app_state.tm_rec_sizes[idx] 

   if destroy {
      if idx < len(app_state.tm_rec_sizes) - 1 {
         dst_size := app_state.tm_rec_sizes[idx + 1] 
         dst_buffer_off := buffer_off + size
         copy(app_state.tm_rec_buffer[buffer_off:buffer_off + size],
            app_state.tm_rec_buffer[dst_buffer_off:dst_buffer_off + dst_size])
      }
      app_state.tcp_server.buffer_off -= size 
      app_state.tcp_server.total_bytes -= size
      unordered_remove(&app_state.tm_rec_sizes, idx)
      unordered_remove(&to_destroy, idx)
   }

   buffer_off += size 
 }
}

// ---------------------------------------------------------------------------------------------------------------------- //

// FIX PERFORMANCE: Instead of the displaying in a tree, just show it
// on an array.
//
orbit_show_db :: proc(rect: Rect2D, xml_handler: ^xtce.handler) {
 //if TRACY_ENABLE { tracy.ZoneS(depth = 10) }

 render.debug_time_add_scope("orbit_show_db", ui_context.vulkan_iface.ArenaAllocator)

 @(static) n_rows: u32 = 0
 // calculate total number of elements
 if n_rows == 0 {
  fmt.println("Recalculating number of rows")
  tmp_queue: utils.queue(^utils.node_tree(utils.tuple(string, xml.Element)), 4096)
  utils.PushQueue(&tmp_queue, &xml_handler.tree_eval)

  layout := get_layout_stack()

  for tmp_queue.IdxFront != tmp_queue.IdxTail {
   node_it := utils.GetFrontQueue(&tmp_queue)
   utils.PopQueue(&tmp_queue)

   append(&app_state.menu_db.menu_list, node_it.element)

   n_rows += 1
   for b := node_it.next; b != nil; b = b.right {
    utils.PushQueue(&tmp_queue, b)
   }
  }
 }

 // FIX: It has problems at some point when scrolling too fast or too far
 //
 {
  clicked_tab, ok := menu_begin(
   title = "Orbit DB#database_%p",
   top_left = rect.top_left,
   w_h = rect.size,
   key_pointer = cast(^byte)xml_handler,
   entries = {"TM Parameters", "TM Containers", "TC Arguments", "TC Commands"},
  )
  defer end_menu(true)

  if app_state.menu_db.current_tab != &UI_NilBox || ok {
   if ok {
    app_state.menu_db.current_tab = clicked_tab
   }
   switch app_state.menu_db.current_tab.title_string {
    case "TM Parameters":
    {

     set_layout_ui_parent_seed(clicked_tab)

     layout := get_layout_stack()
     limit_on_screen := false
     set_layout_next_row_col(0, 5)
     set_box_preferred_size({rect.size.x / 5, 30})
     set_layout_next_padding(15, 0)
     set_layout_string_padding(10, 0)

     row_start_it := begin_next_layout_scrollable_section(n_rows)

     l_it := 1
     row := 1
     set_layout_next_row(auto_cast row)
     set_layout_next_column(0)

     system_node: ^utils.node_tree(^xtce.SpaceSystemType) = cast(^utils.node_tree(
      ^xtce.SpaceSystemType,
     ))&xml_handler.system
     for system := system_node;
     system != nil && !limit_on_screen;
     system = system.next {
      for ParamType in xtce.GetSpaceSystemParameterSetTypes(system.element) {
       if layout.at.y + layout.box_preferred_size.y >
       (rect.top_left.y + rect.size.y) {
        limit_on_screen = true
       }

       #partial switch parameter in ParamType {
        case xtce.ParameterType:
        {
         if l_it >= row_start_it && !limit_on_screen {
          set_layout_next_column(0)

          if math.mod(cast(f32)row, 2.) == 0 {
           style := ui_context.theme.background_panel
           style.color_rect00 *= 0.9
           style.color_rect01 *= 0.9
           style.color_rect10 *= 0.9
           style.color_rect11 *= 0.9
           style.corner_radius = 6
           set_next_layout_style(style)
           make_box_from_key(
            "#box_%d",
            layout.at + {4, 0},
            {
             layout.parent_box.rect.size.x - 8,
             layout.box_preferred_size.y,
            },
            {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER},
            cast(^byte)&l_it,
           )
           ui_pop_style()
          }
          StringConcat := [?]string {
           parameter.base.t_name.t_restriction.val,
           "#_name_",
           parameter.base.t_name.t_restriction.val,
           "%d",
          }

          StringTypeConcat := [?]string {
           parameter.t_parameterTypeRef.t_restriction.val,
           "#_type_ref_",
           parameter.t_parameterTypeRef.t_restriction.val,
           "%d",
          }

          StringReadOnlyConcat := [?]string {
           parameter.t_ParameterProperties.t_readOnly.val ? "true" : "false",
           "#_readOnly_",
           parameter.t_ParameterProperties.t_readOnly.val ? "true" : "false",
           "%d",
          }

          StringInitialValueConcat := [?]string {
           len(parameter.t_initialValue.val) == 0 ? "-" : parameter.t_initialValue.val,
           "#_InitVal_",
           parameter.t_initialValue.val,
           "%d",
          }

          StringPersistenceConcat := [?]string {
           len(parameter.t_ParameterProperties.t_dataSource.t_enumeration_values[0]) == 0 ? "-" : parameter.t_ParameterProperties.t_dataSource.t_enumeration_values[0],
           "#_Persistence_",
           parameter.t_ParameterProperties.t_dataSource.t_enumeration_values[0],
           "%d",
          }

          label(
           strings.concatenate(
            StringConcat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(1)
          label(
           strings.concatenate(
            StringTypeConcat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(2)
          label(
           strings.concatenate(
            StringReadOnlyConcat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(3)
          label(
           strings.concatenate(
            StringInitialValueConcat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(4)
          label(
           strings.concatenate(
            StringPersistenceConcat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )

          row += 1
          set_layout_next_row(auto_cast row)
         }
        }
       }
       l_it += 1
      }
     }

     end_next_layout_scrollable_section(n_rows)

     {
      set_layout_next_row(0)
      set_layout_next_column(0)
      label("Parameter Name#_par_name_%p", cast(^byte)clicked_tab)
      set_layout_next_column(1)
      label("Parameter Type#_param_type_%p", cast(^byte)clicked_tab)
      set_layout_next_column(2)
      label("Read Only#_read_only_%p", cast(^byte)clicked_tab)
      set_layout_next_column(3)
      label("Initial Value#_vaule_%p", cast(^byte)clicked_tab)
      set_layout_next_column(4)
      label("Source#_source_%p", cast(^byte)clicked_tab)
     }
    }
    case "TC Arguments":
    {
     set_layout_ui_parent_seed(clicked_tab)

     layout := get_layout_stack()
     limit_on_screen := false
     set_layout_next_row_col(0, 5)
     set_box_preferred_size({rect.size.x / 5, 30})
     set_layout_next_padding(15, 0)
     set_layout_string_padding(10, 0)

     row_start_it := begin_next_layout_scrollable_section(n_rows)

     l_it := 1
     row := 1
     set_layout_next_row(auto_cast row)
     set_layout_next_column(0)

     system_node: ^utils.node_tree(^xtce.SpaceSystemType) = cast(^utils.node_tree(
      ^xtce.SpaceSystemType,
     ))&xml_handler.system
     for system := system_node;
     system != nil && !limit_on_screen;
     system = system.next {
      ArgTypeSet := xtce.GetArgumentTypeSet(system.element)
      for arg_type in ArgTypeSet {

       if layout.at.y + layout.box_preferred_size.y >
       (rect.top_left.y + rect.size.y) {
        limit_on_screen = true
       }

       #partial switch argument in arg_type {

        case xtce.IntegerArgumentType:
        {
         if layout.at.y + layout.box_preferred_size.y >
         (rect.top_left.y + rect.size.y) {
          limit_on_screen = true
         }

         if l_it >= row_start_it && !limit_on_screen {
          set_layout_next_column(0)

          if math.mod(cast(f32)l_it, 2.) == 0 {
           style := ui_context.theme.background_panel
           style.color_rect00 *= 0.95
           style.color_rect01 *= 0.95
           style.color_rect10 *= 0.95
           style.color_rect11 *= 0.95
           style.corner_radius = 6
           set_next_layout_style(style)
           make_box_from_key(
            "#box_%d",
            layout.at + {4, 0},
            {
             layout.parent_box.rect.size.x - 8,
             layout.box_preferred_size.y,
            },
            {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER},
            cast(^byte)&row,
           )
           ui_pop_style()
          }

          fixed_int_val := xtce.GetFixedIntegerValueString(
           argument.base.t_initialValue,
          )

          arg_name_concat := [?]string {
           argument.base.base.base.t_name.t_restriction.val,
           "#_BaseName_",
           argument.base.base.base.t_name.t_restriction.val,
           "_%d",
          }


          arg_type_concat := [?]string {
           "Integer",
           "#_type_Integer",
           "_%d",
          }

          arg_initial_value_concat := [?]string {
           fixed_int_val, //len(argument.base.t_initialValue) > 0 ? argument.base.t_initialValue : "-",
           "#_InitialValue_",
           fixed_int_val,
           "_%d",
          }

          buff1: [64]u8
          buff2: [64]u8
          min_val := len(fixed_int_val) > 0 ? fixed_int_val : "-"
          max_val := len(fixed_int_val) > 0 ? fixed_int_val : "-"

          arg_min_concat := [?]string {
           min_val,
           "#_minValue_",
           min_val,
           "_%d",
          }
          arg_max_concat := [?]string {
           max_val,
           "#_maxValue_",
           max_val,
           "_%d",
          }

          set_layout_next_column(0)
          label(
           strings.concatenate(
            arg_name_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(1)
          label(
           strings.concatenate(
            arg_type_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(2)
          label(
           strings.concatenate(
            arg_initial_value_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(3)
          label(
           strings.concatenate(
            arg_min_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(4)
          label(
           strings.concatenate(
            arg_max_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )

          row += 1
          set_layout_next_row(auto_cast row)
         }
         l_it += 1
        }
        case xtce.EnumeratedArgumentType:
        {
         if l_it >= row_start_it && !limit_on_screen {
          set_layout_next_column(0)
          if math.mod(cast(f32)l_it, 2.) == 0 {
           style := ui_context.theme.background_panel
           style.color_rect00 *= 0.95
           style.color_rect01 *= 0.95
           style.color_rect10 *= 0.95
           style.color_rect11 *= 0.95
           style.corner_radius = 6
           set_next_layout_style(style)
           make_box_from_key(
            "#box_%d",
            layout.at + {4, 0},
            {
             layout.parent_box.rect.size.x - 8,
             layout.box_preferred_size.y,
            },
            {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER},
            cast(^byte)&row,
           )
           ui_pop_style()
          }

          arg_name_concat := [?]string {
           argument.base.base.base.t_name.t_restriction.val,
           "#_BaseName_",
           argument.base.base.base.t_name.t_restriction.val,
           "_%d",
          }


          arg_type_concat := [?]string {
           "Enumerated",
           "#_type_Integer",
           "_%d",
          }

          arg_initial_value_concat := [?]string {
           argument.base.t_initialValue.val, //len(argument.base.t_initialValue) > 0 ? argument.base.t_initialValue : "-",
           "#_InitialValue_",
           argument.base.t_initialValue.val,
           "_%d",
          }

          set_layout_next_column(0)
          label(
           strings.concatenate(
            arg_name_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(1)
          enum_box := make_box_from_key(
           text = strings.concatenate(
            arg_type_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           box_flags = UI_Options {
            .DRAW_STRING,
            .NO_CLICKABLE,
            .NO_HOVER,
           },
           key = cast(^byte)&l_it,
          )
          set_layout_next_column(2)
          label(
           strings.concatenate(
            arg_initial_value_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          //set_layout_next_column(3)
          //label(strings.concatenate(arg_min_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
          //set_layout_next_column(4)
          //label(strings.concatenate(arg_max_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
          consume_box_event(enum_box)
          if enum_box == ui_context.hover_target {
           n_enum := len(
            argument.base.t_EnumerationList.t_Enumeration,
           )
           box_size: glsl.vec2 = {400, 30}
           top_left := enum_box.rect.top_left
           top_left += enum_box.rect.size
           //set_next_box_layout({.NONE})
           //set_next_layout(top_left, box_size, cast(u32)n_enum, 0, LayoutType.FIXED)
           //set_box_preferred_size({300, 30})
           //set_layout_string_padding(20, 0)
           style := ui_context.theme.background_panel
           style.color_rect00 *= 0.4
           style.color_rect01 *= 0.4
           style.color_rect10 *= 0.4
           style.color_rect11 *= 0.4
           style.color_text *= 1.6
           style.corner_radius = 6
           push_hovering_boxes_for_rendering(
            {top_left, box_size},
            "Enumeration List",
            style,
            cast(^byte)enum_box,
            UI_Options {
             .DRAW_RECT,
             .DRAW_BORDER,
             .DRAW_STRING,
             .NO_CLICKABLE,
             .NO_HOVER,
            },
           )
           //set_next_layout_style(style)
           //defer ui_pop_style()
           //box := make_box_from_key("EnumerationList#_hover_enum_show_list_%p", top_left, box_size, UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER}, cast(^byte)enum_box)
           for it in argument.base.t_EnumerationList.t_Enumeration {
            top_left.y += 30.
            //make_box_from_key(it.t_label.val, top_left, box_size, UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER}, box)
            push_hovering_boxes_for_rendering(
             {top_left, box_size},
             it.t_label.val,
             style,
             cast(^byte)enum_box,
             UI_Options {
              .DRAW_RECT,
              .DRAW_BORDER,
              .DRAW_STRING,
              .NO_CLICKABLE,
              .NO_HOVER,
             },
            )
           }
          }
          row += 1
          set_layout_next_row(auto_cast row)
         }
         l_it += 1
        }
        case xtce.ArrayArgumentType:
        {
         if l_it >= row_start_it && !limit_on_screen {
          set_layout_next_column(0)
          if math.mod(cast(f32)l_it, 2.) == 0 {
           style := ui_context.theme.background_panel
           style.color_rect00 *= 0.95
           style.color_rect01 *= 0.95
           style.color_rect10 *= 0.95
           style.color_rect11 *= 0.95
           style.corner_radius = 6
           set_next_layout_style(style)
           make_box_from_key(
            "#box_%d",
            layout.at + {4, 0},
            {
             layout.parent_box.rect.size.x - 8,
             layout.box_preferred_size.y,
            },
            {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER},
            cast(^byte)&row,
           )
           ui_pop_style()
          }

          arg_name_concat := [?]string {
           argument.base.base.t_name.t_restriction.val,
           "#_BaseName_",
           argument.base.base.t_name.t_restriction.val,
           "_%d",
          }


          arg_type_concat := [?]string {
           "ArrayArgument",
           "#_type_Array",
           "_%d",
          }

          arg_initial_value_concat := [?]string {
           "-",
           "#_InitialValue_",
           "-",
           "_%d",
          }

          set_layout_next_column(0)
          label(
           strings.concatenate(
            arg_name_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(1)
          enum_box := make_box_from_key(
           text = strings.concatenate(
            arg_type_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           box_flags = UI_Options {
            .DRAW_STRING,
            .NO_CLICKABLE,
            .NO_HOVER,
           },
           key = cast(^byte)&l_it,
          )
          set_layout_next_column(2)
          label(
           strings.concatenate(
            arg_initial_value_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          //set_layout_next_column(3)
          //label(strings.concatenate(arg_min_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
          //set_layout_next_column(4)
          //label(strings.concatenate(arg_max_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
          consume_box_event(enum_box)
          if enum_box == ui_context.hover_target {
           n_enum := len(argument.t_DimensionList.t_Dimension)
           box_size: glsl.vec2 = {400, 30}
           top_left := enum_box.rect.top_left
           top_left += enum_box.rect.size
           //set_next_box_layout({.NONE})
           //set_next_layout(top_left, box_size, cast(u32)n_enum, 0, LayoutType.FIXED)
           //set_box_preferred_size({300, 30})
           //set_layout_string_padding(20, 0)
           style := ui_context.theme.background_panel
           style.color_rect00 *= 0.4
           style.color_rect01 *= 0.4
           style.color_rect10 *= 0.4
           style.color_rect11 *= 0.4
           style.color_text *= 1.6
           style.corner_radius = 6
           push_hovering_boxes_for_rendering(
            {top_left, box_size},
            "Dimension List",
            style,
            cast(^byte)enum_box,
            UI_Options {
             .DRAW_RECT,
             .DRAW_BORDER,
             .DRAW_STRING,
             .NO_CLICKABLE,
             .NO_HOVER,
            },
           )
           //set_next_layout_style(style)
           //defer ui_pop_style()
           //box := make_box_from_key("EnumerationList#_hover_enum_show_list_%p", top_left, box_size, UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER}, cast(^byte)enum_box)
           for it in argument.t_DimensionList.t_Dimension {
            top_left.y += 30.
            //make_box_from_key(it.t_label.val, top_left, box_size, UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER}, box)
            start_index_concat: [dynamic]string = make(
             [dynamic]string,
             ui_context.per_frame_arena_allocator,
            )
            append(&start_index_concat, "Start Index: ")
            buffer: [64]u8
            #partial switch tt in
            it.t_StartingIndex.t_choice_0 {
             case xtce.xs_long:
             {
              append(
               &start_index_concat,
               strconv.itoa(
                buffer[:],
                cast(int)tt.integer,
               ),
              )
             }
             case xtce.ArgumentDiscreteLookupListType:
             {
              for it2 in tt.t_DiscreteLookup {
               append(
                &start_index_concat,
                strconv.itoa(
                 buffer[:],
                 cast(int)it2.t_value.integer,
                ),
               )
              }
             }
             case xtce.ArgumentDynamicValueType:
             {
              utils.TODO(
               "Sill have to do xtce.ArgumentDynamicValueType",
               strconv.itoa(buffer[:], #line),
              )
             }
            }

            start_index := strings.concatenate(
             start_index_concat[:],
             ui_context.per_frame_arena_allocator,
            )
            push_hovering_boxes_for_rendering(
             {top_left, box_size},
             start_index,
             style,
             cast(^byte)enum_box,
             UI_Options {
              .DRAW_RECT,
              .DRAW_BORDER,
              .DRAW_STRING,
              .NO_CLICKABLE,
              .NO_HOVER,
             },
            )
           }
          }
          row += 1
          set_layout_next_row(auto_cast row)
         }
         l_it += 1
        }
       }
      }
     }

     for app_state.hovering_boxes.IdxFront != app_state.hovering_boxes.IdxTail {
      box_conf := utils.GetFrontQueue(&app_state.hovering_boxes)
      utils.PopQueue(&app_state.hovering_boxes)
      box: ^Box
      if box_conf.key == nil && len(box_conf.text) > 0 {
       box = make_box_no_key(
        box_conf.text,
        box_conf.rect.top_left,
        box_conf.rect.size,
        box_conf.flags,
       )
      } else if len(box_conf.text) > 0 {
       set_layout_ui_parent_seed(cast(^Box)box_conf.key)
       defer unset_layout_ui_parent_seed()
       box = make_box_no_key(
        box_conf.text,
        box_conf.rect.top_left,
        box_conf.rect.size,
        box_conf.flags,
       )
      }
     }

     end_next_layout_scrollable_section(n_rows)
     {
      set_layout_next_row(0)
      set_layout_next_column(0)
      label("Argument Name#_container_name_%p", cast(^byte)clicked_tab)
      set_layout_next_column(1)
      label("Type#_type_%p", cast(^byte)clicked_tab)
      set_layout_next_column(2)
      label("Initial Value#_vaule_%p", cast(^byte)clicked_tab)
      set_layout_next_column(3)
      label("Min Range#_min_range_%p", cast(^byte)clicked_tab)
      set_layout_next_column(4)
      label("Max Range#_max_range_%p", cast(^byte)clicked_tab)
     }
    }
    case "TM Containers":
    {
     set_layout_ui_parent_seed(clicked_tab)

     layout := get_layout_stack()
     limit_on_screen := false
     set_layout_next_row_col(0, 5)
     set_box_preferred_size({rect.size.x / 5, 30})
     set_layout_next_padding(15, 0)
     set_layout_string_padding(10, 0)

     row_start_it := begin_next_layout_scrollable_section(n_rows)

     l_it := 1
     row := 1
     set_layout_next_row(auto_cast row)
     set_layout_next_column(0)

     if len(TmContainerExpandList) == 0 {
      TmContainerExpandList = make([]bool, n_rows)
     }

     system_node: ^utils.node_tree(^xtce.SpaceSystemType) = cast(^utils.node_tree(
      ^xtce.SpaceSystemType,
     ))&xml_handler.system
     for system := system_node;
     system != nil && !limit_on_screen;
     system = system.next {
      for ContainerSet in xtce.GetSequenceContainer(system.element) {

       if layout.at.y + layout.box_preferred_size.y >
       (rect.top_left.y + rect.size.y) {
        limit_on_screen = true
       }

       #partial switch SequenceContainer in ContainerSet {
        case xtce.SequenceContainerType:
        {
         if l_it >= row_start_it && !limit_on_screen {
          set_layout_next_column(0)

          style := ui_context.theme.background_panel
          style.color_rect00 *= 0.95
          style.color_rect01 *= 0.95
          style.color_rect10 *= 0.95
          style.color_rect11 *= 0.95
          style.corner_radius = 6
          set_next_layout_style(style)
          defer ui_pop_style()

          container_concat := [?]string {
           TmContainerExpandList[l_it] ? "v " : "> ",
           SequenceContainer.base.base.t_name.t_restriction.val,
           "#_BaseName_",
           SequenceContainer.base.base.t_name.t_restriction.val,
           "_%d",
          }

          base_container_concat := [?]string {
           len(SequenceContainer.t_BaseContainer.t_containerRef.t_restriction.val) > 0 ? SequenceContainer.t_BaseContainer.t_containerRef.t_restriction.val : "-",
           "#_ContainerBase_",
           SequenceContainer.t_BaseContainer.t_containerRef.t_restriction.val,
           "_%d",
          }

          label_box := make_box_from_key(
           strings.concatenate(
            container_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           box_flags = UI_Options {
            .DRAW_RECT,
            .DRAW_STRING,
            .HOVER_ANIMATION,
           },
           key = cast(^byte)&l_it,
          )
          set_next_hover_cursor(label_box, glfw.HAND_CURSOR)
          label_box_input := consume_box_event(label_box)
          //@static left_click := false

          if .LEFT_CLICK == label_box_input {
           TmContainerExpandList[l_it] =
           !TmContainerExpandList[l_it]
          }

          set_layout_next_column(1)
          make_box_from_key(
           strings.concatenate(
            base_container_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           box_flags = UI_Options {
            .DRAW_STRING,
            .NO_CLICKABLE,
            .NO_HOVER,
           },
           key = cast(^byte)&l_it,
          )
          // Lister panel for all parameters inside the telemetry container
          //
          if TmContainerExpandList[l_it] {
           set_layout_ui_parent_seed(label_box)
           set_layout_next_column(0)
           for EntryType in SequenceContainer.t_EntryList.t_choice_0 {
            #partial switch entry in EntryType {
             case xtce.ParameterRefEntryType:
             {
              entry_concat := [?]string {
               "|> ",
               len(entry.t_parameterRef.t_restriction.val) > 0 ? entry.t_parameterRef.t_restriction.val : "-",
               "#_param_ref_",
               entry.t_parameterRef.t_restriction.val,
               "_%p",
              }
              //l_it += 1
              row += 1
              set_layout_next_row(auto_cast row)
              make_box_from_key(
               strings.concatenate(
                entry_concat[:],
                ui_context.per_frame_arena_allocator,
               ),
               box_flags = UI_Options {
                .DRAW_RECT,
                .DRAW_STRING,
                .NO_CLICKABLE,
                .NO_HOVER,
               },
               key = cast(^byte)label_box,
              )
              //label(entry.t_parameterRef.t_restriction.val)
             }
             case xtce.ContainerRefEntryType:
             {}
            }
           }
          }
          row += 1
          set_layout_next_row(auto_cast row)
         }
        }
       }
       l_it += 1
      }
     }
     end_next_layout_scrollable_section(n_rows)
     {
      set_layout_next_row(0)
      set_layout_next_column(0)
      label("Container Name#_container_name_%p", cast(^byte)clicked_tab)
      set_layout_next_column(1)
      label("Base Container#_base_container_%p", cast(^byte)clicked_tab)
      set_layout_next_column(2)
      label("Read Only#_read_only_%p", cast(^byte)clicked_tab)
      set_layout_next_column(3)
      label("Initial Value#_vaule_%p", cast(^byte)clicked_tab)
      set_layout_next_column(4)
      label("Source#_source_%p", cast(^byte)clicked_tab)
     }
    }
    case "TC Commands":
    {
     set_layout_ui_parent_seed(clicked_tab)
     layout := get_layout_stack()
     limit_on_screen := false

     set_layout_next_row_col(n_rows, 7)
     set_box_preferred_size({rect.size.x / 7, 30})
     set_layout_next_padding(0, 0)
     set_layout_string_padding(15, 0)

     row_start := begin_next_layout_scrollable_section(n_rows)

     l_it := 1
     row := 1
     set_layout_next_row(auto_cast row)
     set_layout_next_column(0)

     tmp_stack: utils.Stack(^xtce.space_system, 256)
     utils.push_stack(&tmp_stack, &xml_handler.system)

     for tmp_stack.push_count > 0 {
      system := utils.get_front_stack(&tmp_stack)
      utils.pop_stack(&tmp_stack)

      for it := system.next; it != nil; it = it.right {
       utils.push_stack(&tmp_stack, auto_cast it)
      }

      for CommandType in xtce.GetMetaCommandSetType(system.element) {
       if layout.at.y + layout.box_preferred_size.y >
       (rect.top_left.y + rect.size.y) {
        limit_on_screen = true
       }
       #partial switch command in CommandType {
        case xtce.MetaCommandType:
        {
         defer l_it += 1
         if l_it >= row_start && !limit_on_screen {
          set_layout_next_column(0)
          ui_vspacer(2.)
          {
           style := ui_context.theme.background_panel
           style.color_rect00 *= 0.95
           style.color_rect01 *= 0.95
           style.color_rect10 *= 0.95
           style.color_rect11 *= 0.95
           style.corner_radius = 2
           set_next_layout_style(style)
           make_box_from_key(
            strings.concatenate(
             {
              "#box_",
              command.base.t_name.t_restriction.val,
              "%d",
             },
             ui_context.per_frame_arena_allocator,
            ),
            layout.at + {4, 0},
            {
             layout.parent_box.rect.size.x - 8,
             layout.box_preferred_size.y,
            },
            {
             .DRAW_BORDER,
             .DRAW_RECT,
             .NO_CLICKABLE,
             .NO_HOVER,
            },
            cast(^byte)&l_it,
           )
           ui_pop_style()
          }
          name_concat := [?]string {
           command.base.t_name.t_restriction.val,
           "#_container_",
           command.base.t_name.t_restriction.val,
           "%d",
          }

          field_type := [?]string{"-", "#_field_", "%d"}

          field_name := [?]string{"-", "#_field_name", "%d"}

          encoding_concat := [?]string{"-", "#_encoding_", "%d"}

          size_bits := [?]string{"-", "#_size_bits_", "%d"}

          value_concat := [?]string{"-", "#_valu_concat_", "%d"}

          default_value_concat := [?]string {
           "-",
           "#_default_value_",
           "%d",
          }

          set_layout_next_column(0)
          container_box := label(
           strings.concatenate(
            name_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(1)
          label(
           strings.concatenate(
            field_type[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(2)
          label(
           strings.concatenate(
            field_name[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(3)
          label(
           strings.concatenate(
            encoding_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(4)
          label(
           strings.concatenate(
            size_bits[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(5)
          label(
           strings.concatenate(
            value_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )
          set_layout_next_column(6)
          label(
           strings.concatenate(
            default_value_concat[:],
            ui_context.per_frame_arena_allocator,
           ),
           cast(^byte)&l_it,
          )

          // Check
          //
          {
           set_layout_ui_parent_seed(container_box)
           base_command := command.t_BaseMetaCommand
           base_command_list: [dynamic]xtce.MetaCommandType =
           make(
            [dynamic]xtce.MetaCommandType,
            ui_context.per_frame_arena_allocator,
           )
           append(&base_command_list, command)
           defer delete(base_command_list)

           base_command_type := xtce.GetBaseMetaCommand(
            system,
            command.t_BaseMetaCommand.t_metaCommandRef.t_restriction.val,
           )
           if len(
            base_command_type.base.t_name.t_restriction.val,
           ) >
           0 {
            append(&base_command_list, base_command_type)
            for len(
             base_command_type.base.t_name.t_restriction.val,
            ) >
            0 {
             base_command_type = xtce.GetBaseMetaCommand(
              system,
              base_command_type.t_BaseMetaCommand.t_metaCommandRef.t_restriction.val,
             )
             if len(
              base_command_type.base.t_name.t_restriction.val,
             ) >
             0 {
              append(
               &base_command_list,
               base_command_type,
              )
             }
            }
           }
           slice.reverse(base_command_list[:])
           for CommandType in base_command_list {
            for arg in CommandType.t_ArgumentList.t_Argument {
             //l_it += 1
             row += 1
             set_layout_next_row(auto_cast row)
             // TODO: For encoding size and value we shall search for the type it
             // references and return it here
             // argument_ref := SearchForArgument(system), NOTE: Can be any system
             //
             ref_arg_decl, ref_par_decl :=
             xtce.GetArgumentDecl(
              system,
              arg.t_argumentTypeRef.t_restriction.val,
             )
             container_name := strings.concatenate(
              name_concat[:],
              ui_context.per_frame_arena_allocator,
             )

             field_name: string =
             arg.base.t_name.t_restriction.val
             field_type: string =
             arg.t_argumentTypeRef.t_restriction.val
             default_name: string = arg.t_initialValue.val
             size_in_bits: string = "-"
             encoding: string = "-"

             buff: [64]u8
             #partial switch arg_t in ref_arg_decl {
              case xtce.IntegerArgumentType:
              {
               size_in_bits = strconv.itoa(
                buff[:],
                cast(int)arg_t.base.t_sizeInBits.t_restriction.integer,
               )
               field_type =
               arg_t.base.base.base.t_name.t_restriction.val
               #partial switch encod_t in
               arg_t.base.base.t_choice_0 {
                case xtce.IntegerDataEncodingType:
                {
                 encoding =
                 encod_t.t_encoding.t_restriction.val
                }
               }
              }
              case xtce.FloatArgumentType:
              {
               field_type =
               arg_t.base.base.base.t_name.t_restriction.val
               size_in_bits = strconv.itoa(
                buff[:],
                cast(int)arg_t.base.t_sizeInBits.t_restriction.t_restriction.integer,
               )
               #partial switch encod_t in
               arg_t.base.base.t_choice_0 {
                case xtce.FloatDataEncodingType:
                {
                 encoding =
                 encod_t.t_encoding.t_restriction.val
                }
               }
              }
              case xtce.EnumeratedArgumentType:
              {
               field_type =
               arg_t.base.base.base.t_name.t_restriction.val
               #partial switch encod_t in
               arg_t.base.base.t_choice_0 {
                case xtce.IntegerDataEncodingType:
                {
                 encoding =
                 encod_t.t_encoding.t_restriction.val
                 size_in_bits = strconv.itoa(
                  buff[:],
                  cast(int)encod_t.t_sizeInBits.t_restriction.integer,
                 )
                }
               }
              }
              case xtce.ArrayArgumentType:
              {
               field_type =
               arg_t.base.base.t_name.t_restriction.val
               type_ref :=
               arg_t.base.t_arrayTypeRef.t_restriction.val
               array_ref, par_ref :=
               xtce.GetArgumentDecl(
                system,
                type_ref,
               )
               #partial switch ref_t in array_ref {
                case xtce.IntegerArgumentType:
                {
                 size_in_bits = strconv.itoa(
                  buff[:],
                  cast(int)ref_t.base.t_sizeInBits.t_restriction.integer,
                 )
                 #partial switch encod_t in
                 ref_t.base.base.t_choice_0 {
                  case xtce.IntegerDataEncodingType:
                  {
                   encoding =
                   encod_t.t_encoding.t_restriction.val
                  }
                 }
                }
                case xtce.EnumeratedArgumentType:
                {
                 size_bits = "EnumeratedVal"
                 #partial switch encod_t in
                 ref_t.base.base.t_choice_0 {
                  case xtce.IntegerDataEncodingType:
                  {
                   encoding =
                   encod_t.t_encoding.t_restriction.val
                  }
                 }
                }
               }
              }
             }

             #partial switch arg_t in ref_par_decl {
              case xtce.IntegerParameterType:
              {
               size_in_bits = strconv.itoa(
                buff[:],
                cast(int)arg_t.base.t_sizeInBits.t_restriction.integer,
               )
               field_type =
               arg_t.base.base.base.t_name.t_restriction.val
               #partial switch encod_t in
               arg_t.base.base.t_choice_0 {
                case xtce.IntegerDataEncodingType:
                {
                 encoding =
                 encod_t.t_encoding.t_restriction.val
                }
               }
              }
              case xtce.FloatParameterType:
              {
               field_type =
               arg_t.base.base.base.t_name.t_restriction.val
               size_in_bits = strconv.itoa(
                buff[:],
                cast(int)arg_t.base.t_sizeInBits.t_restriction.t_restriction.integer,
               )
               #partial switch encod_t in
               arg_t.base.base.t_choice_0 {
                case xtce.FloatDataEncodingType:
                {
                 encoding =
                 encod_t.t_encoding.t_restriction.val
                }
               }
              }
              case xtce.EnumeratedParameterType:
              {
               field_type =
               arg_t.base.base.base.t_name.t_restriction.val
               #partial switch encod_t in
               arg_t.base.base.t_choice_0 {
                case xtce.IntegerDataEncodingType:
                {
                 encoding =
                 encod_t.t_encoding.t_restriction.val
                 size_in_bits = strconv.itoa(
                  buff[:],
                  cast(int)encod_t.t_sizeInBits.t_restriction.integer,
                 )
                }
               }
              }
              case xtce.ArrayParameterType:
              {
               field_type =
               arg_t.base.base.t_name.t_restriction.val
               type_ref :=
               arg_t.base.t_arrayTypeRef.t_restriction.val
               array_ref, par_ref :=
               xtce.GetArgumentDecl(
                system,
                type_ref,
               )
               #partial switch ref_t in array_ref {
                case xtce.IntegerArgumentType:
                {
                 size_in_bits = strconv.itoa(
                  buff[:],
                  cast(int)ref_t.base.t_sizeInBits.t_restriction.integer,
                 )
                 #partial switch encod_t in
                 ref_t.base.base.t_choice_0 {
                  case xtce.IntegerDataEncodingType:
                  {
                   encoding =
                   encod_t.t_encoding.t_restriction.val
                  }
                 }
                }
                case xtce.EnumeratedArgumentType:
                {
                 size_bits = "EnumeratedVal"
                 #partial switch encod_t in
                 ref_t.base.base.t_choice_0 {
                  case xtce.IntegerDataEncodingType:
                  {
                   encoding =
                   encod_t.t_encoding.t_restriction.val
                  }
                 }
                }
               }
               #partial switch ref_t in par_ref {
                case xtce.IntegerParameterType:
                {
                 size_in_bits = strconv.itoa(
                  buff[:],
                  cast(int)ref_t.base.t_sizeInBits.t_restriction.integer,
                 )
                 #partial switch encod_t in
                 ref_t.base.base.t_choice_0 {
                  case xtce.IntegerDataEncodingType:
                  {
                   encoding =
                   encod_t.t_encoding.t_restriction.val
                  }
                 }
                }
                case xtce.EnumeratedParameterType:
                {
                 size_bits = "EnumeratedVal"
                 #partial switch encod_t in
                 ref_t.base.base.t_choice_0 {
                  case xtce.IntegerDataEncodingType:
                  {
                   encoding =
                   encod_t.t_encoding.t_restriction.val
                  }
                 }
                }
               }
              }
             }

             field_name_concat := [?]string {
              field_name,
              "#_arg_name",
              field_name,
              "_%d",
             }
             field_type_concat := [?]string {
              field_type,
              "#_arg_type_",
              field_type,
              "_%d",
             }

             default := [?]string {
              default_name,
              "#_arg_init_value",
              default_name,
              "_%d",
             }

             size_in_bits_concat := [?]string {
              size_in_bits,
              "#_size_in_bits",
              size_in_bits,
              "_%d",
             }
             encoding_concat := [?]string {
              encoding,
              "#encoding_",
              encoding,
              "_%d",
             }
             set_layout_next_column(0)
             label(container_name, cast(^byte)&row)
             set_layout_next_column(1)
             label(
              strings.concatenate(
               field_type_concat[:],
               ui_context.per_frame_arena_allocator,
              ),
              cast(^byte)&row,
             )
             set_layout_next_column(2)
             label(
              strings.concatenate(
               field_name_concat[:],
               ui_context.per_frame_arena_allocator,
              ),
              cast(^byte)&row,
             )
             set_layout_next_column(3)
             label(
              strings.concatenate(
               encoding_concat[:],
               ui_context.per_frame_arena_allocator,
              ),
              cast(^byte)&row,
             )
             set_layout_next_column(4)
             label(
              strings.concatenate(
               size_in_bits_concat[:],
               ui_context.per_frame_arena_allocator,
              ),
              cast(^byte)&row,
             )
             set_layout_next_column(5)
             //label(strings.concatenate(field_name, ui_context.per_frame_arena_allocator), container_box)
             set_layout_next_column(6)
             label(
              strings.concatenate(
               default[:],
               ui_context.per_frame_arena_allocator,
              ),
              cast(^byte)&row,
             )
            }
           }
          }

          row += 1
          set_layout_next_row(auto_cast row)
         }
        }
        case xtce.NameReferenceType:
        {}
        case xtce.BlockMetaCommandType:
        {}
       }
      }
     }
     end_next_layout_scrollable_section(n_rows)
     {
      set_layout_next_row(0)
      set_layout_next_column(0)
      label("Container Name#_container_name_%p", cast(^byte)clicked_tab)
      set_layout_next_column(1)
      label("Field Type#_field_type_%p", cast(^byte)clicked_tab)
      set_layout_next_column(2)
      label("Field Name#_field_name_%p", cast(^byte)clicked_tab)
      set_layout_next_column(3)
      label("Encoding#_vaule_%p", cast(^byte)clicked_tab)
      set_layout_next_column(4)
      label("Size#_size_%p", cast(^byte)clicked_tab)
      set_layout_next_column(5)
      label("Value#_value_%p", cast(^byte)clicked_tab)
      set_layout_next_column(6)
      label("Default Value#_default_value_%p", cast(^byte)clicked_tab)
     }
    }
   }
  } else if !ok {

   layout := get_layout_stack()
   limit_on_screen := false
   set_layout_next_row_col(n_rows, 3)
   set_box_preferred_size({rect.size.x / 3, 30})
   set_layout_next_padding(15, 0)
   set_layout_string_padding(10, 0)

   row_start_it := begin_next_layout_scrollable_section(n_rows)

   row_it := 1
   set_layout_next_row(auto_cast row_it)

   for i := row_start_it;
   i < len(app_state.menu_db.menu_list) && !limit_on_screen;
   i += 1 {
    node_it := &app_state.menu_db.menu_list[i]

    label_string_slice := [?]string{node_it.first, "#_label", node_it.first, "%p"}
    label_string := strings.concatenate(
     label_string_slice[:],
     ui_context.per_frame_arena_allocator,
    )

    val_0 := len(node_it.second.attribs) >= 1 ? node_it.second.attribs[0].val : "Nan0"
    val_1 := len(node_it.second.attribs) >= 2 ? node_it.second.attribs[1].val : "Nan1"

    col1_string_slice := [?]string{val_0, "#_label1", val_0, "%p"}
    col2_string_slice := [?]string{val_1, "#_label2", val_1, "%p"}
    col1_string := strings.concatenate(
     col1_string_slice[:],
     ui_context.per_frame_arena_allocator,
    )
    col2_string := strings.concatenate(
     col2_string_slice[:],
     ui_context.per_frame_arena_allocator,
    )

    set_layout_next_column(0)

    if math.mod(cast(f32)row_it, 2.) == 0 {
     style := ui_context.theme.background_panel
     style.color_rect00 *= 0.9
     style.color_rect01 *= 0.9
     style.color_rect10 *= 0.9
     style.color_rect11 *= 0.9
     style.corner_radius = 6
     set_next_layout_style(style)
     make_box_from_key(
      "#box_%d",
      layout.at + {4, 0},
      {layout.parent_box.rect.size.x - 8, layout.box_preferred_size.y},
      {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER},
      cast(^byte)&row_it,
     )
     ui_pop_style()
    }

    label(col1_string, cast(^byte)node_it)
    set_layout_next_column(1)
    label(col2_string, cast(^byte)node_it)
    set_layout_next_column(2)
    label(label_string, cast(^byte)node_it)

    row_it += 1
    set_layout_next_row(auto_cast row_it)

    if layout.at.y > layout.position.y + layout.size.y {
     limit_on_screen = true
    }
   }
   end_next_layout_scrollable_section(n_rows)

   set_next_layout_style(ui_context.theme.hover_box)
   set_layout_next_row(0)
   set_layout_next_column(0)
   label("Parameter Name#_param_name_%p", cast(^byte)&ui_context)
   set_layout_next_column(1)
   label("Parameter Type#param_type_%p", cast(^byte)&ui_context)
   set_layout_next_column(2)
   label("XTCE Type#xtce_type_%p", cast(^byte)&ui_context)
   ui_pop_style()
  }
 }
}

// --------------------------------------------------- Main function -------------------------------------------- //

app_state: orbitmcs_state = {
 enable_debug = false,
 SHOW_FLAGS = APP_SHOW_FLAGS.SHOW_HOME,
 shutdown = false,
 menu_db = {current_tab = &UI_NilBox},
}

// --------------------------------------------------- Main function -------------------------------------------- //

main :: proc() {

 hash.init(&app_state.menu_tc.arg_value_map, 5 << 20)

 vulkan_iface: render.VulkanIface

 libc.signal(libc.SIGINT, handle_ctrl_c)

 //if TRACY_ENABLE { tracy.ZoneS(depth = 10) }

 main_arena: vmem.Arena
 CHECK_MEM_ERROR(vmem.arena_init_growing(&main_arena))

 // For debugging purposes, check memory usage
 //
 vulkan_iface.ArenaAllocator = vmem.arena_allocator(&main_arena)

 when ODIN_DEBUG {
  // Init memory tracking allocator
  //
  track: mem.Tracking_Allocator
  mem.tracking_allocator_init(&track, vulkan_iface.ArenaAllocator)
  vulkan_iface.ArenaAllocator = mem.tracking_allocator(&track)

  defer {
   fmt.println("Vulkan Context arena allocator")
   if len(track.allocation_map) > 0 {
    fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
    for _, entry in track.allocation_map {
     fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
    }
   }
   if len(track.bad_free_array) > 0 {
    fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
    for entry in track.bad_free_array {
     fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
    }
   }
   mem.tracking_allocator_destroy(&track)
  }
 }

 render.init_vulkan(&vulkan_iface)
 defer glfw.Terminate()
 defer glfw.DestroyWindow(vulkan_iface.va_Window.w_window)

 app_state.threading = CreatePoolWithAllocator(6)
 thread.pool_start(&app_state.threading.Pool)
 //defer thread.pool_stop_all_tasks(&app_state.threading.Pool)
 // This does not work properly dont know why
 //
 //defer thread.pool_destroy(&app_state.threading.Pool)

 xtce_state_arg: ^xtce_state = new(xtce_state)
 xtce_state_arg.parse_proc = xtce.parse_xsd
 xtce_state_arg.validate_proc = xtce.validate_xml
 xtce_state_arg.schema_path = "./data/SpaceSystem.xsd"
 xtce_state_arg.system_path = "./data/UCF.xml"
 xtce_state_arg.schema = new(xtce.xsd_schema)
 xtce_state_arg.system = new(xtce.handler)

 task_proc: thread.Task_Proc = proc(t: thread.Task) {
  fmt.println("Validating example")
  fmt.println(
   "---------------------------------------------------------------------------------------------",
  )
  state := cast(^xtce_state)t.data
  state.schema = state.parse_proc(state.schema_path, context.allocator)
  state.system = state.validate_proc(state.system_path, state.schema, context.allocator)
  xml.destroy(state.schema.document)
  fmt.println("Validation completed!!")
  fmt.println(
   "---------------------------------------------------------------------------------------------",
  )
 }

 AddProcToPool(app_state.threading, task_proc, rawptr(xtce_state_arg))

 net_state_arg: ^net_state = new(net_state)
 net_state_arg.ip = "127.0.0.1"
 net_state_arg.port = 8080
 net_state_arg.socket_type = net.TCP_Socket{}
 net_state_arg.socket_function = .RECEIVE_SOCKET

 app_state.tcp_server = net_state_arg

 AddProcToPool(app_state.threading, net_start_server, rawptr(net_state_arg))

 net_state_arg_tcp_send: ^net_state = new(net_state)
 net_state_arg_tcp_send.ip = "127.0.0.1"
 net_state_arg_tcp_send.port = 8081
 net_state_arg_tcp_send.socket_type = net.TCP_Socket{}
 net_state_arg_tcp_send.socket_function = .SEND_SOCKET

 app_state.tcp_client = net_state_arg_tcp_send

 AddProcToPool(app_state.threading, net_start_server, rawptr(net_state_arg_tcp_send))

 net_state_arg_udp: ^net_state = new(net_state)
 net_state_arg_udp.ip = "127.0.0.1"
 net_state_arg_udp.port = 8090
 net_state_arg_udp.socket_type = net.UDP_Socket{}
 net_state_arg_udp.socket_function = .SEND_SOCKET

 app_state.udp_client = net_state_arg_udp

 AddProcToPool(app_state.threading, net_start_server, rawptr(net_state_arg_udp))

 net_state_arg_udp_rec: ^net_state = new(net_state)
 net_state_arg_udp_rec.ip = "127.0.0.1"
 net_state_arg_udp_rec.port = 8091
 net_state_arg_udp_rec.socket_type = net.UDP_Socket{}
 net_state_arg_udp_rec.socket_function = .RECEIVE_SOCKET

 app_state.udp_server = net_state_arg_udp_rec

 AddProcToPool(app_state.threading, net_start_server, rawptr(net_state_arg_udp_rec))

 // Create the panel tree so we got a debug-like style editor
 //
 /*
	    *------*--------------*
	    |      |              |
	    |      |              |
	    |      |              |
	    |      *--------------|
	    |      |              |
	    *------*--------------*
      */
 UI_Tree: PanelTree = {
  pct_of_parent = 1.0,
  axis          = 0,
 }
 command_panel: PanelTree = {
  pct_of_parent = 0.15,
  axis          = 1,
 }
 right_panel: PanelTree = {
  pct_of_parent = 0.85,
  axis          = 1,
 }
 content_panel: PanelTree = {
  pct_of_parent = 0.8,
  axis          = 0,
 }
 debug_panel: PanelTree = {
  pct_of_parent = 0.2,
  axis          = 0,
 }

 push_panel_tree(&command_panel, &UI_Tree)
 push_panel_tree(&right_panel, &UI_Tree)
 push_panel_tree(&content_panel, &right_panel)
 push_panel_tree(&debug_panel, &right_panel)

 ui_init(&vulkan_iface)

 // TODO: Check if this messes something up
 //
 context.temp_allocator = ui_context.per_frame_arena_allocator

 last_time: f64 = 0

 {
  task, got_task := thread.pool_pop_done(&app_state.threading.Pool)
  if !got_task || (got_task && task.user_index != 0) {
   for !got_task || (got_task && task.user_index != 0) {
    task, got_task = thread.pool_pop_done(&app_state.threading.Pool)
   }
  }
 }

 for !glfw.WindowShouldClose(vulkan_iface.va_Window.w_window) {

  if !vulkan_iface.va_Window.focused_windows && !ui_context.first_frame {
   continue
  }
  start := time.tick_now()
  glfw.PollEvents()

  when false {
   // Check for rendering
   if vulkan_iface.va_Window.focused_windows {
    x, y := glfw.GetCursorPos(vulkan_iface.va_Window.w_window)
    if !ui_context.first_frame {
     if ui_context.mouse_pos.x == cast(f32)x &&
     ui_context.mouse_pos.y == cast(f32)y &&
     len(vulkan_iface.va_OsInput) == 0 {
      //glfw.WaitEvents()
      vk.DeviceWaitIdle(vulkan_iface.va_Device.d_LogicalDevice)
      continue
     }
    } else {
     ui_context.first_frame = false
    }
   } else if !ui_context.first_frame {
    // if it is not the first frame and is not focused
    // skip ui rendering
    //glfw.WaitEvents()
    vk.DeviceWaitIdle(vulkan_iface.va_Device.d_LogicalDevice)
    continue
   }
  }

  render.debug_time_add_scope("Main_loop")
  ui_begin()
  {
   w_width := cast(f32)vulkan_iface.va_SwapChain.sc_Extent.width
   w_height := cast(f32)vulkan_iface.va_SwapChain.sc_Extent.height

   // -------------------------------------------------- s.p. Panel Tree Generation ------------------------------------------- //
   // Generating the PanelTree for boundaries
   //
   {
    using utils

    UI_Tree.rect = {{0, 0}, {w_width, w_height}}
    UI_Tree.pct_of_parent = 100
    UI_Tree.axis = 0 // x-axis = 0, y-axis = 1
    rect_dim: Rect2D = {{0, 0}, {w_width, w_height}}

    tmp_stack: Stack(^PanelTree, 64)
    push_stack(&tmp_stack, &UI_Tree)
    for tmp_stack.push_count > 0 {
     panel := get_front_stack(&tmp_stack)
     pop_stack(&tmp_stack)
     rect_dim = panel.rect

     child_off_dim: glsl.vec2 = {0, 0}

     for it_panel := panel.tail;
     it_panel != nil && it_panel != panel.next;
     it_panel = it_panel.left {
      if it_panel.next != nil {
       push_stack(&tmp_stack, it_panel)
      }
      if it_panel.left != nil {
       axis := panel.axis
       panel_axis := it_panel.axis
       panel_rect := it_panel.rect
       boundary_rect := panel_rect
       boundary_rect.top_left[axis] -= 8
       boundary_rect.size[axis] = 16
       box := make_box(
        "Boundary Box#boundary_box_%p",
        boundary_rect.top_left,
        boundary_rect.size,
        UI_Options{},
        cast(^byte)it_panel,
       )
       set_next_hover_cursor(
        box,
        axis == 1 ? glfw.VRESIZE_CURSOR : glfw.HRESIZE_CURSOR,
       )
       input := consume_box_event(box)
       if input == .LEFT_CLICK || box == ui_context.press_target {

        min_child: ^PanelTree = it_panel
        max_child: ^PanelTree = it_panel.left
        x, y := ui_context.mouse_pos.x, ui_context.mouse_pos.y
        if input == .LEFT_CLICK {
         ui_context.boundary_drag = {
          min_child.pct_of_parent,
          max_child.pct_of_parent,
         }
        }

        cursor_mov: glsl.vec2 = {cast(f32)x, cast(f32)y}
        prev_size := max_child.rect.size[axis]
        if cursor_mov[axis] - max_child.rect.top_left[axis] >
        MIN_WINDOW_HEIGHT {
         max_child.rect.size[axis] =
         cursor_mov[axis] - max_child.rect.top_left[axis]
         max_child.pct_of_parent =
         (max_child.rect.size[axis] * max_child.pct_of_parent) /
         prev_size

         prev_size = min_child.rect.size[axis]
         max_size_new_size := min_child.rect.size[axis]
         max_size_new_size -=
         (cursor_mov[axis] - min_child.rect.top_left[axis])
         min_child.rect.size[axis] = max_size_new_size
         min_child.pct_of_parent =
         (max_size_new_size * min_child.pct_of_parent) / prev_size
        }
       }
      }
     }
    }
   }

   // -------------------------------------------------- s.p. UI Generation ------------------------------------------- //
   {
    using utils
    tmp_stack: Stack(^PanelTree, 64)
    push_stack(&tmp_stack, &UI_Tree)
    for tmp_stack.push_count > 0 {
     panel := get_front_stack(&tmp_stack)
     pop_stack(&tmp_stack)
     child_off_dim: glsl.vec2 = {0, 0}
     rect_dim := panel.rect
     for p := panel.next; p != nil; p = p.right {

      axis := panel.axis
      panel_axis := p.axis

      p.rect.top_left[axis] = rect_dim.top_left[axis] + child_off_dim[axis]
      p.rect.top_left[panel_axis] = rect_dim.top_left[panel_axis] + 2
      p.rect.size[panel_axis] = rect_dim.size[panel_axis] - 4
      p.rect.size[axis] = rect_dim.size[axis] * p.pct_of_parent
      child_off_dim += p.rect.size

      if p.next != nil {
       push_stack(&tmp_stack, p)
      } else {
       if p == &command_panel {
        home_style := ui_context.theme.background_panel
        home_style.color_rect00 *= 0.95
        home_style.color_rect01 *= 0.95
        home_style.color_rect10 *= 0.95
        home_style.color_rect11 *= 0.95
        set_next_layout_style(home_style)
        defer pop_layout_style()

        rect := p.rect
        set_next_box_layout({.Y_CENTERED_STRING})
        set_next_layout(rect.top_left, rect.size, 0, 0, LayoutType.FIXED)
        set_box_preferred_size({rect.size.x - 30, 30})
        set_layout_next_padding(15, 0)
        set_layout_string_padding(20, 0)
        if begin(
         "COMMANDS#panel_command_%p",
         {-1, -1},
         {-1, -1},
         cast(^byte)p,
        ) {
         if button("Home Page#Home_button_%p", cast(^byte)p).left_click {
          app_state.SHOW_FLAGS = APP_SHOW_FLAGS.SHOW_HOME
         }
         if button("Network#net_button_%p", cast(^byte)p).left_click {
          app_state.SHOW_FLAGS = APP_SHOW_FLAGS.SHOW_CONN
         }
         if button("Telemetry#tm_button_%p", cast(^byte)p).left_click {
          app_state.SHOW_FLAGS = APP_SHOW_FLAGS.SHOW_TM
         }
         if button("Commands#tcs_button_%p", cast(^byte)p).left_click {
          app_state.SHOW_FLAGS = APP_SHOW_FLAGS.SHOW_TC
         }
         if button("Database#Database_button_%p", cast(^byte)p).left_click {
          app_state.SHOW_FLAGS = APP_SHOW_FLAGS.SHOW_DB
         }
        }
       } else if p == &content_panel {
        switch app_state.SHOW_FLAGS {
         case APP_SHOW_FLAGS.SHOW_HOME:
         {
          set_next_box_layout({.Y_CENTERED_STRING})
          set_next_layout(
           p.rect.top_left,
           p.rect.size,
           4,
           2,
           LayoutType.FIXED,
          )
          set_box_preferred_size({p.rect.size.x * 0.6, 35})
          if begin(
           "General Information#general_info_%p",
           {-1, -1},
           {-1, -1},
           cast(^byte)p,
          ) {
           set_layout_next_row(0)
           set_layout_next_column(0)
           label("Mission Control System Name")
           set_layout_next_column(1)
           label(
            xtce.GetSpaceSystemName(
             xtce_state_arg.system.system.element,
            ),
           )

           set_layout_next_row(1)
           set_layout_next_column(0)
           label("Mission Control System Description")
           set_layout_next_column(1)
           label(
            xtce.GetSpaceSystemShortDescription(
             xtce_state_arg.system.system.element,
            ),
           )

           set_layout_next_row(2)
           set_layout_next_column(0)
           label("Mission Control System Date")
           set_layout_next_column(1)
           label(
            xtce.GetSpaceSystemDate(
             xtce_state_arg.system.system.element,
            ),
           )
          }
         }
         case APP_SHOW_FLAGS.SHOW_CONN:
         {
          set_next_box_layout({.Y_CENTERED_STRING})
          set_next_layout(
           p.rect.top_left,
           p.rect.size,
           4,
           2,
           LayoutType.FIXED,
          )
          set_box_preferred_size({300, 35})
          if begin(
           "Network Center#network_center%p",
           pointer = cast(^byte)p,
          ) {
           set_layout_next_row(0)
           set_layout_next_column(0)
           label("TCP Connection: #_tcp_label_%p", cast(^byte)p)
           set_layout_next_column(1)
           ip_label_arr := [?]string {
            app_state.tcp_server.ip,
            "#_ip_tcp_%p",
           }
           ip_label := strings.concatenate(
            ip_label_arr[:],
            ui_context.per_frame_arena_allocator,
           )
           label(ip_label, cast(^byte)p)

           set_layout_next_row(1)
           set_layout_next_column(0)
           label("UDP Connection: #_udp_label_%p", cast(^byte)p)
           set_layout_next_column(1)
           buff: [64]u8
           label(
            strings.concatenate(
             {
              "Rx: Bytes Received: ",
              strconv.itoa(
               buff[:],
               app_state.udp_server.total_bytes,
              ),
             },
             ui_context.per_frame_arena_allocator,
            ),
           )
          }
         }
         case APP_SHOW_FLAGS.SHOW_TC:
         {
          set_next_box_layout(
           {.Y_CENTERED_STRING, .X_CENTERED, .SCROLLABLE},
          )
          set_next_layout(
           p.rect.top_left,
           p.rect.size,
           0,
           2,
           LayoutType.FIXED,
          )
          set_layout_next_padding(20, 0)
          set_box_preferred_size({0.4 * p.rect.size.x, 30})
          if begin("TC Center#tc_center%p", pointer = cast(^byte)p) {
           orbit_show_tc_center(p.rect, xtce_state_arg.system)
          }
         }
         case APP_SHOW_FLAGS.SHOW_TM:
         {
          set_next_box_layout({.Y_CENTERED_STRING})
          set_next_layout(
           p.rect.top_left,
           p.rect.size,
           0,
           0,
           LayoutType.FIXED,
          )
          set_box_preferred_size({p.rect.size.x, 35})
          if begin(
           "Telemetry Center#TM_Center%p",
           pointer = cast(^byte)p,
          ) {
           orbit_show_tm_received(p.rect, xtce_state_arg.system)
          }
         }
         case APP_SHOW_FLAGS.SHOW_DB:
         {
          orbit_show_db(p.rect, xtce_state_arg.system)
         }
         case APP_SHOW_FLAGS.SHOW_NONE:
         {
         }
        }
       } else if p == &debug_panel {
        set_next_box_layout({.NONE})
        set_next_layout(
         p.rect.top_left,
         p.rect.size,
         4,
         2,
         LayoutType.FIXED,
        )
        set_box_preferred_size({300, 35})
        if begin(
         "Debug Panel#debug_panel%p",
         pointer = cast(^byte)&debug_panel,
        ) {
         label(
          "[INFO] Information goes here...#debug_info_label%p",
          cast(^byte)p,
         )
         //label("[INFO] Information goes here...#label_2_%p", cast(^byte)&debug_panel)
        }
       }
      }
     }
    }
   }
   if app_state.enable_debug {
    set_next_layout_style(ui_context.theme.background_panel)
    //defer utils.pop_stack(&ui_context.style)
    set_next_box_layout({.NONE})
    set_next_layout({30, 30}, {450, 350}, 0, 0, LayoutType.RELATIVE)
    if begin("DEBUG INFO#debug_info_panel_%p", pointer = cast(^byte)&app_state) {
     // Show ui hash table usage
     begin_next_layout_scrollable_section(
      auto_cast (10 + len(render.Global_VulkanDebug.scope)),
     )
     defer end_next_layout_scrollable_section(
      auto_cast (10 + len(render.Global_VulkanDebug.scope)),
     )
     {
      buf: [128]byte
      allocated_slice := [?]string {
       "  - Allocated    : ",
       strconv.itoa(buf[:], ui_context.hash_boxes.allocated),
       "#_label_debug_alloc_%p",
      }
      allocated_str := strings.concatenate(
       allocated_slice[:],
       ui_context.per_frame_arena_allocator,
      )

      slots_slice := [?]string {
       "  - Slots Fileed : ",
       strconv.itoa(buf[:], ui_context.hash_boxes.slots_filled),
       "#_label_debug_slots_%p",
      }
      slots_str := strings.concatenate(
       slots_slice[:],
       ui_context.per_frame_arena_allocator,
      )

      count_slice := [?]string {
       "  - Count        : ",
       strconv.itoa(buf[:], ui_context.hash_boxes.count),
       "#_label_debug_count_%p",
      }
      count_str := strings.concatenate(
       count_slice[:],
       ui_context.per_frame_arena_allocator,
      )

      per_frame_mem_used := [?]string {
       "Per frame memory used : ",
       strconv.itoa(buf[:], auto_cast ui_context.arena_temp.total_used),
       "#_frame_arena_debug_count_%p",
      }
      per_frame_mem_used_str := strings.concatenate(
       per_frame_mem_used[:],
       ui_context.per_frame_arena_allocator,
      )
      persistent_mem_used := [?]string {
       "UI Persistent memory used : ",
       strconv.itoa(buf[:], auto_cast ui_context.arena.total_used),
       "#persistent_arena_debug_count_%p",
      }
      persistent_mem_used_str := strings.concatenate(
       persistent_mem_used[:],
       ui_context.per_frame_arena_allocator,
      )

      if checkbox("Set Dark theme", cast(^byte)&app_state).left_click {
       ui_context.set_dark_theme = !ui_context.set_dark_theme
      }
      label("UI Hash table values: #hash_values_%p", cast(^byte)&app_state)
      label(allocated_str, cast(^byte)&app_state)
      label(slots_str, cast(^byte)&app_state)
      label(count_str, cast(^byte)&app_state)
      label(per_frame_mem_used_str, cast(^byte)&app_state)
      label(persistent_mem_used_str, cast(^byte)&app_state)
     }
     label("Information related to ui elements profiling: ")
     for i := 0; i < len(render.Global_VulkanDebug.scope); i += 1 {
      buf: [64]byte
      //fmt.println(Global_VulkanDebug.scope[i])
      text := [?]string {
       render.Global_VulkanDebug.scope[i],
       " : ",
       strconv.append_float(
        buf[:],
        render.Global_VulkanDebug.duration[i],
        'f',
        6,
        64,
       ),
       " ms",
       "_#label_%d",
      }
      text_ms := strings.concatenate(
       text[:],
       ui_context.per_frame_arena_allocator,
      )
      label(text_ms, cast(^u8)&i)
      //defer delete(text_ms, ui_context.per_frame_arena_allocator)
     }
     buf: [64]byte
     text := [?]string {
      "ui_context.last_zindex :",
      strconv.append_int(buf[:], cast(i64)ui_context.last_zindex, 10),
      "#label_%p",
     }
     text_ms := strings.concatenate(text[:], ui_context.per_frame_arena_allocator)
     label(text_ms, cast(^u8)&render.Global_VulkanDebug)
     str := "none"
     if ui_context.target_box != &UI_NilBox {
      str = ui_context.target_box.title_string
     }
     test := [?]string{"Box Target: ", str, "#target_%p"}
     label(
      strings.concatenate(test[:], ui_context.per_frame_arena_allocator),
      cast(^byte)&app_state,
     )
    }
   }
  }

  // to render hovering boxes
  for app_state.hovering_boxes.IdxFront != app_state.hovering_boxes.IdxTail {
   box_conf := utils.GetFrontQueue(&app_state.hovering_boxes)
   utils.PopQueue(&app_state.hovering_boxes)
   box: ^Box
   if box_conf.key == nil && len(box_conf.text) > 0 {
    box = make_box_no_key(
     box_conf.text,
     box_conf.rect.top_left,
     box_conf.rect.size,
     box_conf.flags,
    )
   } else if len(box_conf.text) > 0 {
    box = make_box_no_key(
     box_conf.text,
     box_conf.rect.top_left,
     box_conf.rect.size,
     box_conf.flags,
    )
   }
   box.zindex = ui_context.last_zindex + 1
   ui_context.last_zindex += 1
   box.parent = ui_context.render_root
   box.prev = ui_context.render_root.tail
   ui_context.render_root.tail = box
  }

  clear(&render.Global_VulkanDebug.scope)
  clear(&render.Global_VulkanDebug.duration)
  consume_app_state_events(&app_state)

  ui_build()
  render.draw_frame(&vulkan_iface)
  end := time.tick_now()
  diff := time.tick_diff(start, end)
  last_time = time.duration_milliseconds(diff)

  glfw.SwapBuffers(vulkan_iface.va_Window.w_window)
 }
 // this is for other threads
 //
 app_state.shutdown = true
}
