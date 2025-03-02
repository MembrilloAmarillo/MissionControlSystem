package OrbitMCS

import "base:runtime"

import "core:fmt"
import "core:math"
import "core:math/big"
import "core:math/linalg/glsl"
import "core:mem"
import vmem "core:mem/virtual"
import "core:net"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:time"
import "core:thread"

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
 switch error
 {
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
 current_tab : ^Box,

 // This is a maybe, to better access all the elements,
 // still not sure if it is viable as it does lose hierarchy
 //
 menu_list   : [dynamic]utils.tuple(string, xml.Element),

 // This is the start node when listing all database, if we do not
 // keep in check where is the node start of the row it will have
 // really bad performance issues
 //
 start_node  : ^utils.node_tree(utils.tuple(string, xml.Element))
}

// --------------------------------------------------------------- //

net_state :: struct {
  ip : string,
  port : int,
  socket_type : net.Any_Socket,
}

//tcp_net_state :: net_state{ ip = "", port = 8080, socket_type = net.TCP_Socket{} }
//udp_net_state :: net_state{ ip = "", port = 8090, socket_type = net.UDP_Socket{} }

// --------------------------------------------------------------- //

box_constructor :: struct {
 rect : Rect2D,
 text : string,
 style : StyleParam,
 key : ^byte,
 flags : UI_Options
}

// --------------------------------------------------------------- //

orbitmcs_state :: struct {
 enable_debug: bool,
 SHOW_FLAGS  : APP_SHOW_FLAGS,
 threading   : ^thread_pool,
 tcp_server  : net_state,
 udp_server  : net_state,
 menu_db     : db_menu_items,
 shutdown    : bool,
 hovering_boxes : utils.queue(box_constructor, 216) // IMPORTANT!!: If you put a bigger value (for example 4096) odin compiler (llvm function) will crash
}

// --------------------------------------------------------------- //

xtce_state :: struct {
  schema : ^xtce.xsd_schema,
  system : ^xtce.handler,
  schema_path : string,
  system_path : string,
  parse_proc    : proc(path : string, allocator : mem.Allocator) -> ^xtce.xsd_schema,
  validate_proc : proc(path : string, schema : ^xtce.xsd_schema, allocator : mem.Allocator) -> ^xtce.handler,
}

// --------------------------------------------------------------- //

PanelTree :: struct {
 parent, left, right, next, tail: ^PanelTree,
 pct_of_parent:                   f32,
 rect:                            Rect2D,
 axis:                            u32,
}

// --------------------------------------------------------------- //

handle_msg_tcp :: proc(t : net.TCP_Socket) {

}

// --------------------------------------------------------------- //

net_start_server :: proc( t : thread.Task ) {
  net_state := cast(^net_state)t.data
  addr, ok := net.parse_ip4_address(net_state.ip)
  app_state.tcp_server = net_state^
  if !ok {
    fmt.println("[ERROR] Wrong ip address", net_state.ip)
    return
  }

  endpoint := net.Endpoint{
    address = addr,
    port    = net_state.port
  }

  sock, err := net.listen_tcp(endpoint)
  if err != nil {
    fmt.println("[ERROR] Failed listening on TCP")
  }
  fmt.printfln("Listening on TCP: %s", net.endpoint_to_string(endpoint))
  for !app_state.shutdown {
   cli, _, err_accept := net.accept_tcp(sock)
   if err_accept != nil {
    fmt.println("[ERROR] Failed to accept TCP connection")
  }
  else {
   fmt.println("[INFO] Accepting connection", cli)
 }
		//thread.create_and_start_with_poly_data(cli, handle_msg_tcp)
  //AddProcToPool(&app_state.threading, handle_msg_tcp, rawptr(&cli))
}
fmt.println("Closed socket")
net.close(sock)
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

orbit_show_home :: proc() {}


// ---------------------------------------------------------------------------------------------------------------------- //

push_hovering_boxes_for_rendering :: proc(rect : Rect2D, tex : string, st : StyleParam, key : ^byte = nil, flags : UI_Options = { .NONE } ) {
 box : box_constructor = {
  rect  = rect,
  text  = tex,
  style = st,
  key   = key,
  flags = flags
}

utils.PushQueue(&app_state.hovering_boxes, box)
}

// ---------------------------------------------------------------------------------------------------------------------- //


// We set it as global as long as Im not sure where to put this
//
TmContainerExpandList : []bool

// ---------------------------------------------------------------------------------------------------------------------- //

// FIX PERFORMANCE: Instead of the displaying in a tree, just show it
// on an array.
//
orbit_show_db :: proc(rect: Rect2D, xml_handler: ^xtce.handler) {
 //if TRACY_ENABLE { tracy.ZoneS(depth = 10) }

 render.debug_time_add_scope("orbit_show_db", ui_context.vulkan_iface.ArenaAllocator)

 @(static) n_rows: u32 = 0
 // calculate total number of elements
 if n_rows == 0
 {
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
   case "TM Parameters": {

    set_layout_ui_parent_seed(clicked_tab)

    layout := get_layout_stack()
    limit_on_screen := false
    set_layout_next_row_col(0, 5)
    set_box_preferred_size({rect.size.x / 5, 30})
    set_layout_next_padding(15, 0)
    set_layout_string_padding(10, 0)

    row_start_it := begin_next_layout_scrollable_section(n_rows)

    l_it := 1
    row  := 1
    set_layout_next_row( auto_cast row)
    set_layout_next_column(0)

    system_node : ^utils.node_tree(^xtce.SpaceSystemType) = cast(^utils.node_tree(^xtce.SpaceSystemType))&xml_handler.system
    for system := system_node; system != nil && !limit_on_screen; system = system.next {
     for ParamType in xtce.GetSpaceSystemParameterSetTypes(system.element) {
      if layout.at.y + layout.box_preferred_size.y > (rect.top_left.y + rect.size.y) {
        limit_on_screen = true
      }

      #partial switch parameter in ParamType {
        case xtce.ParameterType : {
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
             make_box_from_key("#box_%d", layout.at + {4, 0}, {layout.parent_box.rect.size.x - 8, layout.box_preferred_size.y}, {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER}, cast(^byte)&l_it)
             ui_pop_style()
           }
           StringConcat := [?]string {
             parameter.base.t_name.t_restriction.val,
             "#_name_",
             parameter.base.t_name.t_restriction.val,
             "%d"
           }

           StringTypeConcat := [?]string {
             parameter.t_parameterTypeRef.t_restriction.val,
             "#_type_ref_",
             parameter.t_parameterTypeRef.t_restriction.val,
             "%d"
           }

           StringReadOnlyConcat := [?]string {
             parameter.t_ParameterProperties.t_readOnly.val ? "true" : "false",
             "#_readOnly_",
             parameter.t_ParameterProperties.t_readOnly.val ? "true" : "false",
             "%d"
           }

           StringInitialValueConcat := [?]string {
             len(parameter.t_initialValue.val) == 0 ? "-" : parameter.t_initialValue.val,
             "#_InitVal_",
             parameter.t_initialValue.val,
             "%d"
           }

           StringPersistenceConcat := [?]string {
             len(parameter.t_ParameterProperties.t_dataSource.t_enumeration_values[0]) == 0 ? "-" : parameter.t_ParameterProperties.t_dataSource.t_enumeration_values[0],
             "#_Persistence_",
             parameter.t_ParameterProperties.t_dataSource.t_enumeration_values[0],
             "%d"
           }

           label(strings.concatenate(StringConcat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
           set_layout_next_column(1)
           label(strings.concatenate(StringTypeConcat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
           set_layout_next_column(2)
           label(strings.concatenate(StringReadOnlyConcat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
           set_layout_next_column(3)
           label(strings.concatenate(StringInitialValueConcat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
           set_layout_next_column(4)
           label(strings.concatenate(StringPersistenceConcat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)

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
  label("Parameter Type#_param_type_%p",cast(^byte)clicked_tab)
  set_layout_next_column(2)
  label("Read Only#_read_only_%p", cast(^byte)clicked_tab)
  set_layout_next_column(3)
  label("Initial Value#_vaule_%p", cast(^byte)clicked_tab)
  set_layout_next_column(4)
  label("Source#_source_%p", cast(^byte)clicked_tab)
}
}
case "TC Arguments": {
  set_layout_ui_parent_seed(clicked_tab)

  layout := get_layout_stack()
  limit_on_screen := false
  set_layout_next_row_col(0, 5)
  set_box_preferred_size({rect.size.x / 5, 30})
  set_layout_next_padding(15, 0)
  set_layout_string_padding(10, 0)

  row_start_it := begin_next_layout_scrollable_section(n_rows)

  l_it := 1
  row  := 1
  set_layout_next_row( auto_cast row)
  set_layout_next_column(0)

  system_node : ^utils.node_tree(^xtce.SpaceSystemType) = cast(^utils.node_tree(^xtce.SpaceSystemType))&xml_handler.system
  for system := system_node; system != nil && !limit_on_screen; system = system.next {
    ArgTypeSet := xtce.GetArgumentTypeSet(system.element)
    for arg_type in ArgTypeSet {

      # partial switch argument in arg_type {

        case xtce.IntegerArgumentType : {
          if layout.at.y + layout.box_preferred_size.y > (rect.top_left.y + rect.size.y) {
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
              make_box_from_key("#box_%d", layout.at + {4, 0}, {layout.parent_box.rect.size.x - 8, layout.box_preferred_size.y}, {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER}, cast(^byte)&row)
              ui_pop_style()
            }

            fixed_int_val := xtce.GetFixedIntegerValueString(argument.base.t_initialValue)

            arg_name_concat := [?]string {
              argument.base.base.base.t_name.t_restriction.val,
              "#_BaseName_",
              argument.base.base.base.t_name.t_restriction.val,
              "_%d"
            }


            arg_type_concat := [?]string {
              "Integer",
              "#_type_Integer",
              "_%d"
            }

            arg_initial_value_concat := [?]string {
                fixed_int_val,//len(argument.base.t_initialValue) > 0 ? argument.base.t_initialValue : "-",
                "#_InitialValue_",
                fixed_int_val,
                "_%d"
              }

              buff1 : [64]u8
              buff2 : [64]u8
              min_val := len(fixed_int_val) > 0 ? fixed_int_val : "-"
              max_val := len(fixed_int_val) > 0 ? fixed_int_val : "-"

              arg_min_concat := [?]string {
                min_val,
                "#_minValue_",
                min_val,
                "_%d"
              }
              arg_max_concat := [?]string {
                max_val,
                "#_maxValue_",
                max_val,
                "_%d"
              }

              set_layout_next_column(0)
              label(strings.concatenate(arg_name_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
              set_layout_next_column(1)
              label(strings.concatenate(arg_type_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
              set_layout_next_column(2)
              label(strings.concatenate(arg_initial_value_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
              set_layout_next_column(3)
              label(strings.concatenate(arg_min_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
              set_layout_next_column(4)
              label(strings.concatenate(arg_max_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)

              row += 1
              set_layout_next_row(auto_cast row)
            }
            l_it += 1
          }
          case xtce.EnumeratedArgumentType : {
            if layout.at.y + layout.box_preferred_size.y > (rect.top_left.y + rect.size.y) {
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
                make_box_from_key("#box_%d", layout.at + {4, 0}, {layout.parent_box.rect.size.x - 8, layout.box_preferred_size.y}, {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER}, cast(^byte)&row)
                ui_pop_style()
              }

              arg_name_concat := [?]string {
                argument.base.base.base.t_name.t_restriction.val,
                "#_BaseName_",
                argument.base.base.base.t_name.t_restriction.val,
                "_%d"
              }


              arg_type_concat := [?]string {
                "Enumerated",
                "#_type_Integer",
                "_%d"
              }

              arg_initial_value_concat := [?]string {
                argument.base.t_initialValue.val,//len(argument.base.t_initialValue) > 0 ? argument.base.t_initialValue : "-",
                "#_InitialValue_",
                argument.base.t_initialValue.val,
                "_%d"
              }

              set_layout_next_column(0)
              label(strings.concatenate(arg_name_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
              set_layout_next_column(1)
              enum_box := make_box_from_key(text = strings.concatenate(arg_type_concat[:], ui_context.per_frame_arena_allocator), box_flags = UI_Options{.DRAW_STRING, .NO_CLICKABLE, .NO_HOVER} ,key = cast(^byte)&l_it)
              set_layout_next_column(2)
              label(strings.concatenate(arg_initial_value_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
              //set_layout_next_column(3)
              //label(strings.concatenate(arg_min_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
              //set_layout_next_column(4)
              //label(strings.concatenate(arg_max_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
              consume_box_event( enum_box )
              if enum_box == ui_context.hover_target {
               n_enum := len(argument.base.t_EnumerationList.t_Enumeration)
               box_size : glsl.vec2 = {400, 30}
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
               style.color_text   *= 1.6
               style.corner_radius = 6
               push_hovering_boxes_for_rendering({top_left, box_size}, "Enumeration List", style, cast(^byte)enum_box, UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER})
               //set_next_layout_style(style)
               //defer ui_pop_style()
               //box := make_box_from_key("EnumerationList#_hover_enum_show_list_%p", top_left, box_size, UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER}, cast(^byte)enum_box)
               for it in argument.base.t_EnumerationList.t_Enumeration {
                top_left.y += 30.
                //make_box_from_key(it.t_label.val, top_left, box_size, UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER}, box)
                push_hovering_boxes_for_rendering({top_left, box_size}, it.t_label.val, style, cast(^byte)enum_box, UI_Options{.DRAW_RECT, .DRAW_BORDER, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER})
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
    box : ^Box
    if box_conf.key == nil && len(box_conf.text) > 0 {
     box = make_box_no_key(box_conf.text, box_conf.rect.top_left, box_conf.rect.size, box_conf.flags)
   } else if len(box_conf.text) > 0 {
    set_layout_ui_parent_seed(cast(^Box)box_conf.key)
    defer unset_layout_ui_parent_seed()
    box = make_box_no_key(box_conf.text, box_conf.rect.top_left, box_conf.rect.size, box_conf.flags)
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
  label("Min Range#_min_range_%p",cast(^byte)clicked_tab)
  set_layout_next_column(4)
  label("Max Range#_max_range_%p", cast(^byte)clicked_tab)
} 
}
case "TM Containers" : {
  set_layout_ui_parent_seed(clicked_tab)

  layout := get_layout_stack()
  limit_on_screen := false
  set_layout_next_row_col(0, 5)
  set_box_preferred_size({rect.size.x / 5, 30})
  set_layout_next_padding(15, 0)
  set_layout_string_padding(10, 0)

  row_start_it := begin_next_layout_scrollable_section(n_rows)

  l_it := 1
  row  := 1
  set_layout_next_row( auto_cast row)
  set_layout_next_column(0)

  if len(TmContainerExpandList) == 0 {
   TmContainerExpandList = make([]bool, n_rows)
 }

 system_node : ^utils.node_tree(^xtce.SpaceSystemType) = cast(^utils.node_tree(^xtce.SpaceSystemType))&xml_handler.system
 for system := system_node; system != nil && !limit_on_screen; system = system.next {
  for ContainerSet in xtce.GetSequenceContainer(system.element) {

    if layout.at.y + layout.box_preferred_size.y > (rect.top_left.y + rect.size.y) {
      limit_on_screen = true
    }

    #partial switch SequenceContainer in ContainerSet {
      case xtce.SequenceContainerType : {
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
            "_%d"
          }

          base_container_concat := [?]string {
            len(SequenceContainer.t_BaseContainer.t_containerRef.t_restriction.val) > 0 ? SequenceContainer.t_BaseContainer.t_containerRef.t_restriction.val : "-",
            "#_ContainerBase_",
            SequenceContainer.t_BaseContainer.t_containerRef.t_restriction.val,
            "_%d"
          }

          label_box := make_box_from_key(strings.concatenate(container_concat[:], ui_context.per_frame_arena_allocator), box_flags = UI_Options{.DRAW_RECT, .DRAW_STRING, .HOVER_ANIMATION}, key = cast(^byte)&l_it)
          set_next_hover_cursor(label_box, glfw.HAND_CURSOR)
          label_box_input := consume_box_event(label_box)
           //@static left_click := false

           if .LEFT_CLICK == label_box_input {
             TmContainerExpandList[l_it] = !TmContainerExpandList[l_it]
           }

           set_layout_next_column(1)
           make_box_from_key(strings.concatenate(base_container_concat[:], ui_context.per_frame_arena_allocator), box_flags = UI_Options{.DRAW_STRING, .NO_CLICKABLE, .NO_HOVER}, key = cast(^byte)&l_it)
          // Lister panel for all parameters inside the telemetry container
          //
          if TmContainerExpandList[l_it] {
           set_layout_ui_parent_seed(label_box)
           set_layout_next_column(0)
           for EntryType in SequenceContainer.t_EntryList.t_choice_0 {
            #partial switch entry in EntryType {
              case xtce.ParameterRefEntryType : {
                entry_concat := [?]string {
                  "|> ",
                  len(entry.t_parameterRef.t_restriction.val) > 0 ? entry.t_parameterRef.t_restriction.val : "-",
                  "#_param_ref_",
                  entry.t_parameterRef.t_restriction.val,
                  "_%p"
                }
                //l_it += 1
                row  += 1
                set_layout_next_row(auto_cast row)
                make_box_from_key(strings.concatenate(entry_concat[:], ui_context.per_frame_arena_allocator), box_flags = UI_Options{.DRAW_RECT, .DRAW_STRING, .NO_CLICKABLE, .NO_HOVER},key = cast(^byte)label_box)
                //label(entry.t_parameterRef.t_restriction.val)
              }
              case xtce.ContainerRefEntryType : {}
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
  label("Base Container#_base_container_%p",cast(^byte)clicked_tab)
  set_layout_next_column(2)
  label("Read Only#_read_only_%p", cast(^byte)clicked_tab)
  set_layout_next_column(3)
  label("Initial Value#_vaule_%p", cast(^byte)clicked_tab)
  set_layout_next_column(4)
  label("Source#_source_%p", cast(^byte)clicked_tab)
}
}
case "TC Commands"  : {
  set_layout_ui_parent_seed(clicked_tab)
  layout := get_layout_stack()
  limit_on_screen := false 

  set_layout_next_row_col(0, 7)
  set_box_preferred_size({rect.size.x / 7, 30})
  set_layout_next_padding(15, 0)
  set_layout_string_padding(10, 0)

  row_start := begin_next_layout_scrollable_section(n_rows)

  l_it := 1
  row  := 1
  set_layout_next_row( auto_cast row)
  set_layout_next_column(0)

  for system := &xml_handler.system; system != nil && !limit_on_screen; system = auto_cast system.next {
    for CommandType in xtce.GetMetaCommandSetType(system.element) {
      if layout.at.y + layout.box_preferred_size.y > (rect.top_left.y + rect.size.y) {
        limit_on_screen = true
      }
      #partial switch command in CommandType {
        case xtce.MetaCommandType : {
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
              make_box_from_key(strings.concatenate({"#box_", command.base.t_name.t_restriction.val,"%d"}, ui_context.per_frame_arena_allocator), layout.at + {4, 0}, {layout.parent_box.rect.size.x - 8, layout.box_preferred_size.y}, {.DRAW_BORDER, .DRAW_RECT, .NO_CLICKABLE, .NO_HOVER}, cast(^byte)&l_it)
              ui_pop_style()
            }
            name_concat : = [?]string {
              command.base.t_name.t_restriction.val,
              "#_container_",
              command.base.t_name.t_restriction.val,
              "%d",
            }

            field_type := [?]string {
              "-",
              "#_field_",
              "%d",
            }

            field_name := [?]string {
              "-",
              "#_field_name",
              "%d",
            }

            encoding_concat := [?]string {
              "-",
              "#_encoding_",
              "%d",
            }

            size_bits := [?]string {
              "-",
              "#_size_bits_",
              "%d",
            }

            value_concat := [?]string {
              "-",
              "#_valu_concat_",
              "%d",
            }

            default_value_concat := [?]string {
              "-",
              "#_default_value_",
              "%d",
            }

            set_layout_next_column(0)
            container_box := label(strings.concatenate(name_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
            set_layout_next_column(1)
            label(strings.concatenate(field_type[:], ui_context.per_frame_arena_allocator),cast(^byte)&l_it)
            set_layout_next_column(2)
            label(strings.concatenate(field_name[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
            set_layout_next_column(3)
            label(strings.concatenate(encoding_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
            set_layout_next_column(4)
            label(strings.concatenate(size_bits[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
            set_layout_next_column(5)
            label(strings.concatenate(value_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)
            set_layout_next_column(6)
            label(strings.concatenate(default_value_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&l_it)

            // Check
            //
            {
              set_layout_ui_parent_seed(container_box)
              for arg in command.t_ArgumentList.t_Argument {
                l_it += 1
                row += 1
                set_layout_next_row(auto_cast row)
                // TODO: For encoding size and value we shall search for the type it 
                // references and return it here
                // argument_ref := SearchForArgument(system), NOTE: Can be any system
                //
                ref_arg_decl := xtce.GetIntegerArgumentDecl(system, arg.t_argumentTypeRef.t_restriction.val)
                container_name := strings.concatenate(name_concat[:], ui_context.per_frame_arena_allocator)
                field_name := [?]string {
                  arg.base.t_name.t_restriction.val,
                  "#_arg_name",
                  arg.base.t_name.t_restriction.val,
                  "_%d"
                }
                field_type := [?]string {
                  arg.t_argumentTypeRef.t_restriction.val,
                  "#_arg_type_",
                  
                  arg.t_argumentTypeRef.t_restriction.val,
                  "_%d"
                }
                default    := [?]string {
                  arg.t_initialValue.val,
                  "#_arg_init_value",
                  arg.t_initialValue.val,
                  "_%d"
                }
                buff : [64]u8
                size_in_bits_concat := [?]string {
                  strconv.itoa(buff[:], cast(int)ref_arg_decl.base.t_sizeInBits.t_restriction.integer),
                  "#_size_in_bits",
                  strconv.itoa(buff[:], cast(int)ref_arg_decl.base.t_sizeInBits.t_restriction.integer),
                  "_%d",
                }
                encoding_concat := [?]string {
                  "#_size_in_bits",
                  "_%d",
                }
                set_layout_next_column(0)
                label(container_name, cast(^byte)&row)
                set_layout_next_column(1)
                label(strings.concatenate(field_type[:], ui_context.per_frame_arena_allocator), cast(^byte)&row)
                set_layout_next_column(2)
                label(strings.concatenate(field_name[:], ui_context.per_frame_arena_allocator), cast(^byte)&row)
                set_layout_next_column(3)
                label(strings.concatenate(encoding_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&row)
                set_layout_next_column(4)
                label(strings.concatenate(size_in_bits_concat[:], ui_context.per_frame_arena_allocator), cast(^byte)&row)
                set_layout_next_column(5)
                //label(strings.concatenate(field_name, ui_context.per_frame_arena_allocator), container_box)
                set_layout_next_column(6)
                label(strings.concatenate(default[:], ui_context.per_frame_arena_allocator), cast(^byte)&row)
              }
            }

            row += 1
            set_layout_next_row(auto_cast row)
          }
        }
        case xtce.NameReferenceType : {}
        case xtce.BlockMetaCommandType : {}
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
      label("Field Type#_field_type_%p",cast(^byte)clicked_tab)
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
}
else if !ok {

 layout := get_layout_stack()
 limit_on_screen := false
 set_layout_next_row_col(n_rows, 3)
 set_box_preferred_size({rect.size.x / 3, 30})
 set_layout_next_padding(15, 0)
 set_layout_string_padding(10, 0)

 row_start_it := begin_next_layout_scrollable_section(n_rows)

 row_it := 1
 set_layout_next_row(auto_cast row_it)

 for i := row_start_it; i < len(app_state.menu_db.menu_list) && !limit_on_screen; i += 1 {
  node_it := &app_state.menu_db.menu_list[i]

  label_string_slice := [?]string {
   node_it.first,
   "#_label",
   node_it.first,
   "%p",
 }
 label_string := strings.concatenate(
   label_string_slice[:],
   ui_context.per_frame_arena_allocator,
   )

 val_0 := len(node_it.second.attribs) >= 1 ? node_it.second.attribs[0].val : "Nan0"
 val_1 := len(node_it.second.attribs) >= 2 ? node_it.second.attribs[1].val : "Nan1"

 col1_string_slice := [?]string {
   val_0,
   "#_label1",
   val_0,
   "%p",
 }
 col2_string_slice := [?]string {
   val_1,
   "#_label2",
   val_1,
   "%p",
 }
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
   make_box_from_key("#box_%d", layout.at + {4, 0}, {layout.parent_box.rect.size.x - 8, layout.box_preferred_size.y}, {.DRAW_RECT, .NO_CLICKABLE, .NO_HOVER}, cast(^byte)&row_it)
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
  SHOW_FLAGS   = APP_SHOW_FLAGS.SHOW_HOME,
  shutdown     = false,
  menu_db      = { current_tab = &UI_NilBox },
}

// --------------------------------------------------- Main function -------------------------------------------- //

main :: proc() {

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

app_state.threading = CreatePoolWithAllocator(2)
thread.pool_start(&app_state.threading.Pool)
defer thread.pool_stop_all_tasks(&app_state.threading.Pool)
 // This does not work properly dont know why
 //
 //defer thread.pool_destroy(&app_state.threading.Pool)

 xtce_state_arg : ^xtce_state = new(xtce_state)
 xtce_state_arg.parse_proc    = xtce.parse_xsd
 xtce_state_arg.validate_proc = xtce.validate_xml
 xtce_state_arg.schema_path   = "./data/SpaceSystem.xsd"
 xtce_state_arg.system_path   = "./data/UCF.xml"
 xtce_state_arg.schema        = new(xtce.xsd_schema)
 xtce_state_arg.system        = new(xtce.handler)

 task_proc : thread.Task_Proc = proc( t: thread.Task ) {
  fmt.println("Validating example")
  fmt.println(
   "---------------------------------------------------------------------------------------------",
   )
  state := cast(^xtce_state)t.data
  state.schema = state.parse_proc(state.schema_path, context.allocator)
  state.system = state.validate_proc(state.system_path, state.schema, context.allocator)
  fmt.println("Validation completed!!")
  fmt.println(
   "---------------------------------------------------------------------------------------------",
   )
}

AddProcToPool( app_state.threading, task_proc, rawptr(xtce_state_arg))

net_state_arg : ^net_state = new(net_state)
net_state_arg.ip = "127.0.0.1"
net_state_arg.port = 8080
net_state_arg.socket_type = net.TCP_Socket{}

AddProcToPool(app_state.threading, net_start_server, rawptr(net_state_arg))

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
  if vulkan_iface.va_Window.focused_windows
  {
   x, y := glfw.GetCursorPos(vulkan_iface.va_Window.w_window)
   if !ui_context.first_frame {
    if ui_context.mouse_pos.x == cast(f32)x && ui_context.mouse_pos.y == cast(f32)y && len(vulkan_iface.va_OsInput) == 0 {
      //glfw.WaitEvents()
      vk.DeviceWaitIdle(vulkan_iface.va_Device.d_LogicalDevice)
      continue
    }
  }
  else {
    ui_context.first_frame = false
  }
}
else if !ui_context.first_frame {
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
      if cursor_mov[axis] - max_child.rect.top_left[axis] > MIN_WINDOW_HEIGHT
      {
       max_child.rect.size[axis] = cursor_mov[axis] - max_child.rect.top_left[axis]
       max_child.pct_of_parent = (max_child.rect.size[axis] * max_child.pct_of_parent) / prev_size

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

      axis       := panel.axis
      panel_axis := p.axis

      p.rect.top_left[axis]       = rect_dim.top_left[axis] + child_off_dim[axis]
      p.rect.top_left[panel_axis] = rect_dim.top_left[panel_axis] + 2
      p.rect.size[panel_axis]     = rect_dim.size[panel_axis] - 4
      p.rect.size[axis]           = rect_dim.size[axis] * p.pct_of_parent
      child_off_dim              += p.rect.size

      if p.next != nil
      {
       push_stack(&tmp_stack, p)
     }
     else
     {
       if p == &command_panel
       {
        home_style := ui_context.theme.front_panel
        //home_style.color_rect00 = rgba_to_norm(hex_rgba_to_vec4(0xeee8d5ff))
        //home_style.color_rect01 = rgba_to_norm(hex_rgba_to_vec4(0xeee8d5ff))
        //home_style.color_rect10 = rgba_to_norm(hex_rgba_to_vec4(0xeee8d5ff))
        //home_style.color_rect11 = rgba_to_norm(hex_rgba_to_vec4(0xeee8d5ff))
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
    }
    else if p == &content_panel
    {
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
         label(xtce.GetSpaceSystemName(xtce_state_arg.system.system.element))

         set_layout_next_row(1)
         set_layout_next_column(0)
         label("Mission Control System Description")
         set_layout_next_column(1)
         label(xtce.GetSpaceSystemShortDescription(xtce_state_arg.system.system.element))

         set_layout_next_row(2)
         set_layout_next_column(0)
         label("Mission Control System Date")
         set_layout_next_column(1)
         label(xtce.GetSpaceSystemDate(xtce_state_arg.system.system.element))
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
      if begin( "Network Center#network_center%p", pointer = cast(^byte)p )
      {
       set_layout_next_row(0)
       set_layout_next_column(0)
       label("TCP Connection: #_tcp_label_%p", cast(^byte)p)
       set_layout_next_column(1)
       ip_label_arr := [?]string { app_state.tcp_server.ip, "#_ip_tcp_%p" }
       ip_label := strings.concatenate(ip_label_arr[:], ui_context.per_frame_arena_allocator)
       label(ip_label, cast(^byte)p)

       set_layout_next_row(1)
       set_layout_next_column(0)
       label("UDP Connection: #_udp_label_%p", cast(^byte)p)
     }
   }
   case APP_SHOW_FLAGS.SHOW_TC:
   {
    set_next_box_layout({.Y_CENTERED_STRING, .X_CENTERED})
    set_next_layout( p.rect.top_left, p.rect.size, 0, 1, LayoutType.FIXED )
    set_layout_next_padding( 40, 0 )
    set_box_preferred_size({0.5 * p.rect.size.x, 30})
    if begin( "TC Center#tc_center%p", pointer = cast(^byte)p )
    {
      /*
        An Idea: I can have two columns, one to select the command, and the other one 
        to show all the fields, that would make it really easy to navigate and far more
        efficient to use
      */
      ui_vspacer(15.)
      system := &xtce_state_arg.system.system
      row := begin_next_layout_scrollable_section(0, get_layout_stack().box_preferred_size)
      defer end_next_layout_scrollable_section()
      for ; system != nil; system = auto_cast system.next {
        for CommandType in xtce.GetMetaCommandSetType(system.element) {
          #partial switch Command in CommandType {
            case xtce.MetaCommandType : {
              CommandName := Command.base.t_name.t_restriction.val
              button(strings.concatenate({CommandName, "#_command_", CommandName, "_%p"}, ui_context.per_frame_arena_allocator), cast(^byte)system)
              ui_vspacer(2.)
            }
          }
        }
      }
    }
  }
  case APP_SHOW_FLAGS.SHOW_TM:
  {
    set_next_box_layout({.Y_CENTERED_STRING})
    set_next_layout( p.rect.top_left, p.rect.size, 4, 2, LayoutType.FIXED)
    set_box_preferred_size({300, 35})
    if begin( "Telemetry Center#TM_Center%p", pointer = cast(^byte)p )
    {
      set_layout_next_row(0)
      label("TM Log")
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
}
else if p == &debug_panel
{
  set_next_box_layout({.NONE})
  set_next_layout( p.rect.top_left, p.rect.size, 4, 2, LayoutType.FIXED )
  set_box_preferred_size({300, 35})
  if begin("Debug Panel#debug_panel%p", pointer = cast(^byte)&debug_panel)
  {
    label("[INFO] Information goes here...#debug_info_label%p", cast(^byte)p)
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
     begin_next_layout_scrollable_section(auto_cast (10 + len(render.Global_VulkanDebug.scope)))
     defer end_next_layout_scrollable_section(auto_cast (10 + len(render.Global_VulkanDebug.scope)))
     {
      buf: [128]byte
      allocated_slice := [?]string {
       "  - Allocated    : ", strconv.itoa(buf[:], ui_context.hash_boxes.allocated),
       "#_label_debug_alloc_%p"
     }
     allocated_str := strings.concatenate(allocated_slice[:], ui_context.per_frame_arena_allocator)

     slots_slice := [?]string {
       "  - Slots Fileed : ", strconv.itoa(buf[:], ui_context.hash_boxes.slots_filled),
       "#_label_debug_slots_%p"
     }
     slots_str := strings.concatenate(slots_slice[:], ui_context.per_frame_arena_allocator)

     count_slice := [?]string {
       "  - Count        : ", strconv.itoa(buf[:], ui_context.hash_boxes.count),
       "#_label_debug_count_%p"
     }
     count_str := strings.concatenate(count_slice[:], ui_context.per_frame_arena_allocator)

     per_frame_mem_used := [?]string {
       "Per frame memory used : ", strconv.itoa(buf[:], auto_cast ui_context.arena_temp.total_used),
       "#_frame_arena_debug_count_%p"
     }
     per_frame_mem_used_str := strings.concatenate(per_frame_mem_used[:], ui_context.per_frame_arena_allocator)
     persistent_mem_used := [?]string {
       "UI Persistent memory used : ", strconv.itoa(buf[:], auto_cast ui_context.arena.total_used),
       "#persistent_arena_debug_count_%p"
     }
     persistent_mem_used_str := strings.concatenate(persistent_mem_used[:], ui_context.per_frame_arena_allocator)

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
       strconv.append_float( buf[:], render.Global_VulkanDebug.duration[i], 'f', 6, 64 ),
       " ms",
       "_#label_%d",
     }
     text_ms := strings.concatenate( text[:], ui_context.per_frame_arena_allocator,)
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
    if ui_context.press_target != &UI_NilBox {
      str = ui_context.press_target.title_string
    }
    test := [?]string{"Box Target: ", str, "#target_%p"}
    label( strings.concatenate(test[:], ui_context.per_frame_arena_allocator), cast(^byte)&app_state )
  }
}
}

  // to render hovering boxes
  for app_state.hovering_boxes.IdxFront != app_state.hovering_boxes.IdxTail {
    box_conf := utils.GetFrontQueue(&app_state.hovering_boxes)
    utils.PopQueue(&app_state.hovering_boxes)
    box : ^Box
    if box_conf.key == nil && len(box_conf.text) > 0 {
     box = make_box_no_key(box_conf.text, box_conf.rect.top_left, box_conf.rect.size, box_conf.flags)
   } else if len(box_conf.text) > 0 {
     box = make_box_no_key(box_conf.text, box_conf.rect.top_left, box_conf.rect.size, box_conf.flags)
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
 end  := time.tick_now()
 diff := time.tick_diff(start, end)
 last_time = time.duration_milliseconds(diff)

 glfw.SwapBuffers(vulkan_iface.va_Window.w_window)
}
  // this is for other threads
  //
  app_state.shutdown = true
}
