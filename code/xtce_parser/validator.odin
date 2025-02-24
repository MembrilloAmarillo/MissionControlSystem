package xtce_parser

import "base:runtime"
import "core:encoding/xml"
import "core:fmt"
import "core:hash"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"
import "core:strconv"
import "core:text/regex"

import my_hash "../simple_hash"

import utils "../utils"

// -----------------------------------------------------------------------------

restriction_type :: struct {
  base : string,
  enumeration : [dynamic] string,
}

// -----------------------------------------------------------------------------

choice :: distinct utils.node_tree(xml.Attributes)

// -----------------------------------------------------------------------------

// NOTE(s.p): we only allow one simple type definition inside a complex type,
// this is only because xtce files have no such case where multiple simple cases
// are defined inside a complex type. As we are only targeting xtce files, I am
// going to not change this definition. Probably in a another project could do so
//
complex_content :: struct {
  nested_type_name : string,
  extension        : string,
  sequence         : [dynamic]xml.Element,
  attr             : [dynamic]xml.Attribute,
  choices          : ^choice,
  simple_type      : restriction_type,
  nested_content   : ^complex_content
}

// sometimes can happen that we define a simple type inside a complext type
// or even a complex type inside a complex type, but in this case, we just
// add its elements to the sequence and attribs, for the case of a nested
// simple type def, we have to define a restriction type inside our complex
// content

// -----------------------------------------------------------------------------

content_type :: union {
  complex_content,
  restriction_type,
}

// -----------------------------------------------------------------------------

key_type :: struct {
  xpath: string,
  field: string,
}

// -----------------------------------------------------------------------------

schema_type_def :: struct {
  type_name:  string,
  type_val:   string,
  annotation: string,
  base:       string,
  content:    content_type,
  is_key:     bool,
  key:        key_type,
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

has_namespace :: #force_inline proc(namespace: string, ident: string) -> bool {
  for c, idx in namespace {
    if idx >= len(ident) {
      return false
    }
    if cast(u8)c != ident[idx] {
      return false
    }
  }
  return true
}

// -----------------------------------------------------------------------------

search_and_get_first_from_bucket :: proc(schema: ^xsd_schema, key: string) -> schema_type_def {
  el_bucket := my_hash.lookup_table_bucket(&schema.xsd_hash, key)

  for el in el_bucket {
    if len(el.type_val) > 0 {
      return el
    }
  }

  return schema_type_def{}
}

// -----------------------------------------------------------------------------

check_extension :: proc(
  schema: ^xsd_schema,
  parent_type_def: schema_type_def,
  element: string,
) -> (
  schema_type_def,
  bool,
) {
  type_definition: schema_type_def
  type_found: bool = false

  if len(parent_type_def.base) > 0 {

    base_type := parent_type_def.base[len("xtce:"):]
    type: schema_type_def
    el_definition: string

    for len(base_type) > 0 && !type_found {
      when ODIN_DEBUG {
        fmt.println("Using Base", base_type)
      }
      type = search_and_get_first_from_bucket(schema, base_type)
      //fmt.println(type)
      // s.p.: Now that we have the type definition from the base,
      // we need to check if the elements inside have a coincidence with the element
      base_type = type.base
      if len(base_type) > len("xtce:") {
        base_type = base_type[len("xtce:"):]
      }
      //fmt.println("[INFO] Base:", base_type)
      #partial switch content in type.content {
      case complex_content:
        {
          choice := check_for_choice(schema, content, element)
          if len(choice.type_name) > 0 {
            type_found = true
            type_definition = choice
            break
          }

          for el, idx in content.attr {
            if type_found && el.key == "type" {
              type_definition = search_and_get_first_from_bucket(
                schema,
                el.val[len("xtce:"):],
              )
              break
            }
            else if el.key != "type"{
              type_found = false
            }
            if el.val == element {
              // We have found element name definition, we know have to wait for next
              // iteration so we get the type of the element and search it to store it and
              // return it
              type_found = true
            }
          }
        }
      case restriction_type:
        {}
      }
    }
  } else {
    fmt.println("[ERROR] Element does not have base")
    type_found = false
  }

  return type_definition, type_found
}

// -----------------------------------------------------------------------------

// s.p: The idea behind this is that if we find an element with <choice> attribute, e.g.:
// <complexType name = "my_type">
//  <choice minOccurs="1" maxOccurs="2">
//      <element> ... </element>
//      ...
//      <choice>
//      ...
//      </choice>
//  </choice>
//  We iterate through each element and store it in a choice tree
// Note:
// The minOccurs="2" attribute specifies that at least two elements must be present.
// The maxOccurs="unbounded" attribute allows for any number of elements greater than or equal to two.
//
traverse_complex_type_choice_selection :: proc(
  schema: ^xsd_schema,
  element: ^schema_type_def,
  xml_it: ^xml.Element,
  allocator := context.allocator,
) -> xml.Element {
  using utils

  // choice is only available when <complexType> is set
  //
  content := &element.content.(complex_content)
  choice_root: ^choice = content.choices
  node_it : ^choice

  for node_it = auto_cast choice_root.next; node_it.right != nil; node_it = auto_cast node_it.right {}

  xml_it_id: xml.Element_ID
  // get xml_it id for better processing
  //
  {
    parent := schema.document.elements[xml_it.parent]
    for v in parent.value {
      #partial switch content in v {
      case xml.Element_ID:
        {
          child := schema.document.elements[v.(xml.Element_ID)]
          if child.ident == xml_it.ident {
            xml_it_id = v.(xml.Element_ID)
          }
        }
      }
    }
  }

  // We will return the next element after traversing all choices
  //
  element_ret: xml.Element = xml_it^

  q_node: Stack(xml.Element, 2056)
  push_stack(&q_node, xml_it^)

  q_node_it: Stack(^choice, 2056)
  push_stack(&q_node_it, node_it)

  on_simple_type := false

  node_it.element = xml_it.attribs

  for q_node.push_count > 0 {
    it := get_front_stack(&q_node)
    pop_stack(&q_node)

    if it.ident == "choice" || it.ident == "element" || it.ident == "simpleType" {
      node_it = get_front_stack(&q_node_it)
      pop_stack(&q_node_it)
    }

    element_ret = it
    parent := schema.document.elements[it.parent]

    values := it.value[:]
    slice.reverse(values)

    for &v in values {
      #partial switch el in v {
      case xml.Element_ID:
        {
          child_el := schema.document.elements[el]
          {
            if child_el.ident == "element" && it.ident == "choice" && len(child_el.attribs) > 0 {

              node: ^node_tree(xml.Attributes) = new(node_tree(xml.Attributes), allocator)
              node.element = child_el.attribs
              push_node(node, cast(^node_tree(xml.Attributes))node_it)
              on_simple_type = false

              push_stack(&q_node_it, auto_cast node)
              push_stack(&q_node, child_el)

            } else if child_el.ident == "choice" {
              node: ^node_tree(xml.Attributes) = new(node_tree(xml.Attributes), allocator)
              // Here we store minOccurs and maxOccurs
              //
              node.element = child_el.attribs
              push_node(node, cast(^node_tree(xml.Attributes))node_it)
              node_it = cast(^choice)node

              on_simple_type = false

              push_stack(&q_node_it, auto_cast node)
              push_stack(&q_node, child_el)

            } else if child_el.ident == "simpleType" || on_simple_type {
              on_simple_type = true
              push_stack(&q_node_it, node_it)
              push_stack(&q_node, child_el)
              if it.ident == "restriction" || it.ident == "enumeration" || it.ident == "simpleType" {
                append(&node_it.element, xml.Attribute{key = child_el.ident, val = "embedded"})
                append(&node_it.element,..child_el.attribs[:])
              }
            }
          }
        }
      case string:
        {}
      }
    }
  }


  when ODIN_DEBUG {

    queue_attr: queue(^choice, 2056)
    PushQueue(&queue_attr, choice_root)

    for queue_attr.IdxFront != queue_attr.IdxTail {
      it := GetFrontQueue(&queue_attr)
      PopQueue(&queue_attr)

      fmt.print("Depth ", it.depth, " ")
      if it.next == nil {
        fmt.println(it.element)
      }
      else {
        fmt.println("choice", it.element)
      }

      for child := it.next; child != nil; child = child.right {
        PushQueue(&queue_attr, cast(^choice)child)
      }
    }
  }


  return element_ret
}

// -----------------------------------------------------------------------------

hash_schema :: proc(schema: ^xsd_schema, allocator := context.allocator) -> schema_type_def {

  schema_root_el: schema_type_def

  if len( schema.document.elements ) == 0  {
    fmt.println("[ERROR] Schema passed has no elements inside!!")
    return schema_root_el
  }

  xsd_element_it := schema.document.elements[0]

  current_type_def: schema_type_def

  xsd_element_stack: BigStack(xml.Element)

  big_stack_init(&xsd_element_stack, xml.Element, 256 * 1024, context.temp_allocator)
  defer big_stack_delete(&xsd_element_stack, context.temp_allocator)
  push_stack(&xsd_element_stack, xsd_element_it)

  //TODO: Add root element checking to add space system types and keys
  //
  is_root_element := false

  nested_complex_simple_type := false
  nested_complex_complex_type := false

  for xsd_element_stack.push_count > 0 {
    element := get_front_stack(&xsd_element_stack)
    pop_stack(&xsd_element_stack)

    when ODIN_DEBUG {
      fmt.println(element)
    }

    parent := schema.document.elements[element.parent]

    // This is the root element, we only have one, at least on xtce schema
    //
    if element.parent == 0 && element.ident == "element" {
      current_type_def.type_name = element.attribs[0].val
      current_type_def.type_val = element.attribs[1].val
      //my_hash.insert_table(&schema.xsd_hash, current_type_def.type_name, current_type_def)
      schema_root_el = current_type_def
      //current_type_def = schema_type_def {};
      is_root_element = true
      //continue
    }

    if (element.ident == "complexType" || element.ident == "simpleType") &&
       len(current_type_def.type_name) > 0 && len(element.attribs) > 0 { // this last comprobation is to know that is not a nested type

      when ODIN_DEBUG {
        fmt.println("New schema type added:")
        fmt.println("\t- Type name     :", current_type_def.type_name)
        fmt.println("\t- Type value    :", current_type_def.type_val)
        fmt.println("\t- Annotation    :", current_type_def.annotation)
        fmt.println("\t- Base extension:", current_type_def.base)
        fmt.println("\t- Content type  :", current_type_def.content)
        fmt.println("\t- Key xpath     :", current_type_def.key.xpath)
        fmt.println("\t- Key field name:", current_type_def.key.field)
      }

      if is_root_element {
        is_root_element = false
      }
      else {
        #partial switch &content in current_type_def.content {
          case complex_content : {
            type_name := content.nested_type_name
            if content.nested_content != nil {
              type_def := schema_type_def {
                type_name = type_name,
                type_val  = "complexType",
                base      = content.extension,
                content   = content.nested_content^
              }
              content.nested_content = nil
              my_hash.insert_table(&schema.xsd_hash, type_name, type_def)
              //append(&content.sequence, xml.Attribute{key = type_name, val = type_name})
              append(&content.attr, xml.Attribute{key = "name", val = type_name})
              append(&content.attr, xml.Attribute{key = "type", val = strings.concatenate({"xtce:",type_name})})
            }
          }
        }
        my_hash.insert_table(&schema.xsd_hash, current_type_def.type_name, current_type_def)

        // Restart values to default
        //
        current_type_def = schema_type_def{}
        nested_complex_simple_type = false
        nested_complex_complex_type = false
      }
    }

    // This means we found a nested type definition
    //
    if (element.ident == "complexType") &&
       len(element.attribs) == 0 &&
       len(current_type_def.type_name) > 0 {
      nested_complex_complex_type = true
      when ODIN_DEBUG {
        fmt.println("Found nested type for type:", current_type_def.type_name)
      }
    } else if (element.ident == "simpleType") && len( element.attribs ) == 0 && len(current_type_def.type_name) > 0 {
      nested_complex_simple_type = true
      when ODIN_DEBUG {
        fmt.println("Found nested type for type:", current_type_def.type_name)
      }
    }

    if element.ident == "complexType" && nested_complex_complex_type {
      content :=  &current_type_def.content.(complex_content)
      content.nested_content = new(complex_content, allocator)
      if parent.ident == "element" {
        content.nested_type_name = parent.attribs[0].val
      }
      tmp_stack : utils.Stack(xml.Element, 1024)
      utils.push_stack(&tmp_stack, element)
      for tmp_stack.push_count > 0 {
        el_it := utils.get_front_stack(&tmp_stack)
        utils.pop_stack(&tmp_stack)

        if el_it.ident == "element" {
          append(&content.nested_content.sequence, el_it)
          append_elems(&content.nested_content.attr, ..el_it.attribs[:])
        }
        else if el_it.ident == "attribute" {
          append(&content.nested_content.sequence, el_it)
          append_elems(&(content.nested_content.attr), ..el_it.attribs[:])
        }

        values := el_it.value
        for v in values {
          #partial switch c in v {
            case xml.Element_ID : {
              child_el_it := schema.document.elements[c]
              utils.push_stack(&tmp_stack, child_el_it)
            }
          }
        }
      }
      nested_complex_complex_type = false
      continue
    }
    else if element.ident == "complexType" && !nested_complex_complex_type {
      current_type_def.type_name = len(element.attribs) > 0 ? element.attribs[0].val : {}
      current_type_def.type_val = "complexType"
      current_type_def.content = complex_content{}
    }
    else if element.ident == "simpleType" && !nested_complex_simple_type {
      current_type_def.type_name = len(element.attribs) > 0 ? element.attribs[0].val : {}
      current_type_def.type_val = "simpleType"
      current_type_def.content = restriction_type{}
    } else if element.ident == "documentation" && len(current_type_def.type_val) > 0 {
      #partial switch v in element.value[0] {
      case string:
        current_type_def.annotation = element.value[0].(string)
      case xml.Element_ID:
        fmt.println("[ERROR] documentation identifier shall be of type xml.String")
        fmt.println(v)
      }
    }
    else if element.ident == "restriction" {
      if len(element.attribs) != 1 {
        fmt.println("[ERROR] Supposed to be only 1 attribute related to base restriction, found", element.attribs)
      }
      else {
        if current_type_def.type_val == "complexType" && nested_complex_simple_type {
          content := &current_type_def.content.(complex_content)
          content.simple_type.base = element.attribs[0].val
        } else if current_type_def.type_val == "simpleType" {
          content := &current_type_def.content.(restriction_type)
          content.base = element.attribs[0].val
        }
      }
    } else if element.ident == "enumeration" && len(current_type_def.type_val) > 0 && parent.ident == "restriction" {
      if current_type_def.type_val == "complexType" && nested_complex_simple_type {
        content := &current_type_def.content.(complex_content)
        append(&content.simple_type.enumeration, element.attribs[0].val)
      } else if current_type_def.type_val == "simpleType" {
        content := &current_type_def.content.(restriction_type)
        append(&content.enumeration, element.attribs[0].val)
      }
    } else if element.ident == "extension" && len(current_type_def.type_val) > 0 {
      if nested_complex_complex_type {
        content := &current_type_def.content.(complex_content)
        content.nested_content.extension = element.attribs[0].val
      }
      else if nested_complex_simple_type {
        content := &current_type_def.content.(complex_content)
        content.simple_type.base = element.attribs[0].val
      }
      else {
        current_type_def.base = element.attribs[0].val
      }
    } else if element.ident == "element" && len(current_type_def.type_val) > 0 {
      if current_type_def.type_val == "complexType" {
        content : ^complex_content = &current_type_def.content.(complex_content)
        if nested_complex_complex_type {
          content = content.nested_content
        }
        append(&(content.sequence), element)
        append_elems(&(content.attr), ..element.attribs[:])
      } else if current_type_def.type_val == "simpleType" {
        when ODIN_DEBUG {
          fmt.println("[INFO] Parent was simple type:", element)
          fmt.println(current_type_def)
        }
      }
    } else if element.ident == "attribute" && len(current_type_def.type_val) > 0 {
      if current_type_def.type_val == "complexType" {
        content := &current_type_def.content.(complex_content)
        if nested_complex_complex_type {
          content = content.nested_content
        }
        append(&(content.sequence), element)
        append_elems(&(content.attr), ..element.attribs[:])
      } else if current_type_def.type_val == "simpleType" {
        when ODIN_DEBUG {
          fmt.println("[INFO] Parent was simple type:", element)
          fmt.println(current_type_def)
        }
      }
    } else if element.ident == "choice" && len(current_type_def.type_val) > 0 {
      if current_type_def.type_val == "complexType" {

        content := &current_type_def.content.(complex_content)
        if content.choices == nil {
          content.choices = new(choice, allocator)
          content.choices.next = auto_cast new(choice, allocator)
        }
        else {
          b : ^choice = auto_cast content.choices.next
          for ; b.right != nil; b = cast(^choice)b.right {}
          b.right = auto_cast new(choice, allocator)
        }
        element = traverse_complex_type_choice_selection(
          schema,
          &current_type_def,
          &element,
          schema.allocator,
        )
      }
    } else if element.ident == "key" && len(current_type_def.type_val) > 0 {
      current_type_def.is_key = true
    } else if element.ident == "field" && current_type_def.is_key {
      current_type_def.key.field = element.attribs[0].val
    } else if element.ident == "selector" && current_type_def.is_key {
      current_type_def.key.xpath = element.attribs[0].val
    }

    values := element.value[:]
    slice.reverse(values)
    for &v in values {
      #partial switch el in v {
      case xml.Element_ID:
        {
          schema_el := schema.document.elements[v.(xml.Element_ID)]
          push_stack(&xsd_element_stack, schema_el)
        }
      case string:
        {}
      }
    }
  }

  // NOTE(s.p): As I wait to find the next "complexType" or "simpleType", the last element is never stored inside the loop
  // so I simply check that there exists a type and then insert it on the hash table
  //
  if len(current_type_def.type_name) > 0 {
    my_hash.insert_table(&schema.xsd_hash, current_type_def.type_name, current_type_def)
  }

  fmt.println("Number of slots used on hash table:", schema.xsd_hash.count)

  return schema_root_el
}

check_for_choice :: proc(
  schema: ^xsd_schema,
  content: complex_content,
  type: string,
) -> schema_type_def {

  type_def: schema_type_def
  found_el := false
  if content.choices == nil {
    return {}
  }
  if content.choices.next != nil {
    stack: utils.Stack(^choice, 2056)

    utils.push_stack(&stack, content.choices)

    for stack.push_count > 0 && !found_el {
      v := utils.get_front_stack(&stack)
      utils.pop_stack(&stack)
      // if it is a leaf, we have stored an element
      //
      if v.next == nil {
        for attr in v.element {
          //fmt.println(attr)
          if found_el {
            when ODIN_DEBUG {
              fmt.println("[INFO] Found type", attr.val, "for element", attr)
            }
            if (has_namespace("xtce", attr.val)) {
              type_def = search_and_get_first_from_bucket(
                schema,
                attr.val[len("xtce:"):],
              )
            } else {
              type_def = schema_type_def {
                type_name = attr.val,
                type_val  = "xs",
              }
            }
            break
          }
          if attr.val == type {
            found_el = true
          }
        }
      }

      if found_el {
        break
      }

      for b := v.next; b != nil; b = b.right {
        utils.push_stack(&stack, auto_cast b)
      }
    }
  }
  return type_def
}

load_node_in_system :: proc( node : utils.node_tree(utils.tuple(string, xml.Element)), schema_tree : utils.node_tree(utils.tuple(string, schema_type_def)) )
{

}

// ----------------------------------------------------------------------------------------------------------------- //

validate_xml :: proc( path_to_file: string, schema: ^xsd_schema, allocator := context.allocator ) -> ^handler
{
  schema_root_el: schema_type_def

  xml_handler : ^handler = new(handler, schema.allocator)

  // Initialize database hash table
  //
  my_hash.init(&xml_handler.table, 126 << 10, schema.allocator)

  // Store xsd schema
  //
  schema_root_el = hash_schema(schema)

  temp_arena := vmem.arena_temp_begin(&schema.arena)
  temp_alloc := vmem.arena_allocator(temp_arena.arena)

  // Here it is stored the tree evaluation of the whole xtce user file
  //
  xtce_user_tree : utils.node_tree(utils.tuple(string, xml.Element))
  schema_tree    : utils.node_tree(utils.tuple(string, schema_type_def))

  // s.p.: now we start going through all elements in the xml file provided by the user
  //
  {
    file_tokens: xml.Tokenizer

    // Read file
    //
    content, success := os.read_entire_file(path_to_file, temp_alloc)

    // Store tokens
    //
    xml.init(&file_tokens, string(content), path_to_file)

    // Parse document given the content
    //
    document, error := xml.parse(
      string(content),
      xml.Options{flags = {.Error_on_Unsupported}, expected_doctype = "xtce:SpaceSystem"},
    )

    // This is the root element of our file
    //
    element_it := document.elements[0]
    xml_element_stack: BigStack(xml.Element)

    //parent_type_def : schema_type_def

    big_stack_init(&xml_element_stack, xml.Element, 256 * 1024, temp_alloc)
    defer big_stack_delete(&xml_element_stack, temp_alloc)
    push_stack(&xml_element_stack, element_it)

    parent_stack_values: BigStack(schema_type_def)
    big_stack_init(&parent_stack_values, schema_type_def, 8 << 10, temp_alloc)
    defer big_stack_delete(&parent_stack_values, temp_alloc)

    xtce_user_tree.element = {"SpaceSystem", element_it}

    node_values : BigStack(^utils.node_tree(utils.tuple(string, xml.Element)))
    big_stack_init(&node_values, ^utils.node_tree(utils.tuple(string, xml.Element)), 256 * 1024, temp_alloc)
    defer big_stack_delete(&node_values, temp_alloc)
    push_stack(&node_values, &xtce_user_tree)

    //TODO: Add root element checking to add space system types and keys
    //
    is_root_element := true

    for xml_element_stack.push_count > 0 {
      element := get_front_stack(&xml_element_stack)
      pop_stack(&xml_element_stack)

      when ODIN_DEBUG {
        fmt.println("[LOG] Validating element", element)
      }

      parent := document.elements[element.parent]
      parent_type_def: schema_type_def
      if parent_stack_values.push_count > 0 {
        parent_type_def = get_front_stack(&parent_stack_values)
        when ODIN_DEBUG {
          fmt.println("[LOG] Using parent:", parent_type_def)
        }
      }

      // s.p.: There is one thing that happens now, imagine this scenario (first read):
      /*
        -- Reads: xtce:SpaceSystem
        This is the root element, so we check that it is the same as our schema root element:
        -- Find( SpaceSystem ) --
        Now it returns SpaceSystem schema_type_def, with type xtce:SpaceSystemType.
        -- Find( SpaceSystemType ) --
        Now it returns SpaceSystemType schema_type_def.

        Now we go to the next type (e.g. xtce:TelemetryMetadata):

        We iterate through SpaceSystemType attributes and we find TelemetryMetadata, with type
        xtce:TelemetryMetadataType, from that, we now:
        -- Find( TelemetryMetadataType ) --

        Use this TelemetryMetadataType def as our 'in-use' type for the next child
      */
      if (is_root_element || schema_root_el.type_name == element.ident[len("xtce:"):]) {
        fmt.println(schema_root_el)
        space_type := schema_root_el.type_val[len("xtce:"):]
        space_type_definition := search_and_get_first_from_bucket(schema, space_type)
        if len(space_type_definition.type_name) > 0 {
          parent_type_def = space_type_definition
          when ODIN_DEBUG {
            fmt.println(
              "[INFO] Found type",
              space_type_definition.type_name,
              "for element",
              element.ident,
            )
          }
        }
        is_root_element = false
      } else {
        if len(parent_type_def.type_name) == 0 {
          fmt.println(
            "[ERROR] Root element not defined, expected as root element:",
            schema_root_el,
          )
          fmt.println("[ERROR] Element given was", element)
          panic("Not root element found, exiting...")
        }

        type := element.ident[len("xtce:"):]
        type_def: schema_type_def
        #partial switch content in parent_type_def.content {
        case complex_content:
          {
            // check for elements
            //
            found_el := false
            for attr in content.attr {
              if found_el {
                when ODIN_DEBUG {
                  fmt.println(
                    "[INFO] Found type",
                    attr.val,
                    "for element",
                    element,
                  )
                }
                if (has_namespace("xtce", attr.val)) {
                  type_def = search_and_get_first_from_bucket(
                    schema,
                    attr.val[len("xtce:"):],
                  )
                } else {
                  type_def = schema_type_def {
                    type_name = attr.val,
                    type_val  = "xs",
                  }
                }
                break
              }
              if attr.val == type {
                found_el = true
              }
            }
            if !found_el {

              choice_type := check_for_choice(schema, content, type)

              if len(choice_type.type_val) > 0 {
                found_el = true
                type_def = choice_type
              }

              if !found_el {
                // TODO: Extension checking
                //
                when ODIN_DEBUG {
                  fmt.println("[LOG] Searching in base...")
                }
                base_type, found := check_extension(schema, parent_type_def, type)
                if found {
                  when ODIN_DEBUG {
                    fmt.println(
                      "[INFO] Found type",
                      base_type.type_name,
                      "for element",
                      element,
                    )
                  }
                  type_def = base_type
                } else {
                  when ODIN_DEBUG {
                    fmt.println("[ERROR] Element", element, "not found")
                  }
                }
              }
            }
          }
        case restriction_type:
          {
            found_el := false
            fmt.println("Elements: ")
            for el in content.enumeration {
              fmt.println(el)
              if el == type {
                found_el = true
                when ODIN_DEBUG {
                  fmt.println("[INFO] Found type", el, "for element", element)
                }
                type_def = search_and_get_first_from_bucket(
                  schema,
                  el[len("xtce:"):],
                )
                break
              }
            }
            if !found_el {
              when ODIN_DEBUG {
                fmt.println("[ERROR] Element", element, "not found")
              }
            }
          }
        }
        parent_type_def = type_def
      }

      values := element.value[:]
      slice.reverse(values)

      if (parent_stack_values.push_count > 0) {
        pop_stack(&parent_stack_values)
      }

      // Now we check that the attr of the type are valid with respect
      // the attributes we have defined
      // NOTE: Is important to know that an attr can be an user-defined
      // type, and we should then, check that the user-defined type is conformant
      // inside the parameter called. I think that, if the type is valid, we could
      // assume that the parameter definition can take that type as is. In that case
      // we should then just not try to validate the type definition of our parameters/arguments
      // definitions.
      //
      #partial switch content in parent_type_def.content {
      case complex_content:
        {
          for el_attr in element.attribs {
            attr_found := false
            for attr in content.attr {
              if el_attr.key == attr.val {
               attr_found = true
               break
              }
            }
            if !attr_found {
             when ODIN_DEBUG {
              fmt.println(
                "[ERROR] Could not find attr:",
                el_attr,
                "in type",
                content.attr,
              )
             }
            }
          }
        }
      case restriction_type:
        {}
      }

      // We insert n_child times the new type definition
      // This is necessary (well, maybe not, but it works) so that we can have the parent type
      // for each child, knowing that the child can (or cannot) have
      // more childs
      //


      for val in element.value {
        #partial switch type_in_value in val {
        case xml.Element_ID:
          {
            push_stack(&parent_stack_values, parent_type_def)
          }
        case string:
          {
            //fmt.println("[LOG] Value:", val, "for type:", element.ident)
          }
        }
      }

      xtce_node_it := get_front_stack(&node_values)
      xtce_node_it.element.first = strings.clone( parent_type_def.type_name, schema.allocator )
      pop_stack(&node_values)
      for &v in values {
        #partial switch type_in_value in v {
        case xml.Element_ID:
          {
            child_el: xml.Element = document.elements[v.(xml.Element_ID)]
            push_stack(&xml_element_stack, child_el)

            new_node := new(utils.node_tree(utils.tuple(string, xml.Element)), schema.allocator)
            new_node.element = {"", child_el}

            utils.push_node(new_node, xtce_node_it)
            push_stack(&node_values, new_node)
          }
        case string:
          {}
        }
      }
    }
  }

  system_node : ^utils.node_tree(^SpaceSystemType) = cast(^utils.node_tree(^SpaceSystemType))&xml_handler.system
  xml_handler.tree_eval = xtce_user_tree
  {
    is_root_system := true
    node_values : BigStack(^utils.node_tree(utils.tuple(string, xml.Element)))
    big_stack_init(&node_values, ^utils.node_tree(utils.tuple(string, xml.Element)), 256 * 1024, temp_alloc)
    defer big_stack_delete(&node_values, temp_alloc)

    node_values_dst : BigStack(^utils.node_tree(utils.tuple(string, xml.Element)))
    big_stack_init(&node_values_dst, ^utils.node_tree(utils.tuple(string, xml.Element)), 256 * 1024, temp_alloc)
    defer big_stack_delete(&node_values_dst, temp_alloc)

    push_stack(&node_values, &xml_handler.tree_eval)
    push_stack(&node_values_dst, &xml_handler.tree_eval)

    for node_values.push_count > 0 {
      node_it := get_front_stack(&node_values)
      pop_stack(&node_values)

      node_it_dst := get_front_stack(&node_values_dst)
      pop_stack(&node_values_dst)

      node_it_dst = node_it

      switch( node_it_dst.element.first ) {
       case SPACE_SYSTEM_TYPE: {
        if is_root_system {
         is_root_system = false
         system_node.next = new(utils.node_tree(^SpaceSystemType), schema.allocator)
         system_node.element = new(SpaceSystemType, schema.allocator)
        }
        else {
         if auto_cast system_node != &xml_handler.system {
          //system_node = system_node.parent
         }
         sys_node := new(utils.node_tree(^SpaceSystemType), schema.allocator)
         utils.push_node(sys_node, system_node)
         sys_node.parent     = system_node
         system_node.next    = sys_node
         // Now we go into this one
         system_node         = sys_node
         system_node.element = new(SpaceSystemType, schema.allocator)
        }

        for attr in node_it_dst.element.second.attribs {
         if attr.key == "name" {
          system_node.element.base.t_name.t_restriction = xs_normalized_string_get_default()
          system_node.element.base.t_name.t_restriction.val = attr.val
         }
         if attr.key == "shortDescription" {
          system_node.element.base.base.t_shortDescription.t_restriction = xs_string_get_default()
          system_node.element.base.base.t_shortDescription.t_restriction.val = attr.val
         }
        }
       }
       case LONG_DESCRIPTION_TYPE : {
        for attr in node_it_dst.element.second.attribs {
         system_node.element.base.base.t_LongDescription.t_restriction = xs_string_get_default()
         system_node.element.base.base.t_LongDescription.t_restriction.val = attr.val
        }
       }
       case HEADER_TYPE : {
        for attr in node_it_dst.element.second.attribs {
         if attr.key == "date" {
          system_node.element.t_Header.t_date = xs_string_get_default()
          system_node.element.t_Header.t_date.val = attr.val
         }
         if attr.key == "version" {
          system_node.element.t_Header.t_version = xs_string_get_default()
          system_node.element.t_Header.t_version.val = attr.val
         }
        }
       }
       /* -------------------------- COMMAND META DATA HANDLING ------------------------------------ */
       case COMMAND_META_DATA_TYPE: {
        type : CommandMetaDataType = {
         t_ParameterTypeSet    = LoadParameterTypeSetType( node_it_dst ),
        	t_ArgumentTypeSet     = LoadArgumentTypeSetType( node_it_dst ),
        	t_MetaCommandSet      = LoadMetaCommandSetType( node_it_dst ),
        	t_CommandContainerSet = LoadCommandContainerSetType( node_it_dst ),
        	t_StreamSet           = LoadStreamSetType( node_it_dst ),
        	t_AlgorithmSet        = LoadAlgorithmSetType( node_it_dst ),
        }

       	LoadParameterSetType( node_it_dst, &type.t_ParameterSet )

        system_node.element.t_CommandMetaData = type
       }
       /* -------------------------- SERVICE SET TYPE HANDLING ------------------------------------ */
       case SERVICE_SET_TYPE: {}
       /* ------------------------- TELEMETRY META DATA HANDLING ----------------------------------- */
       case AGGREGATE_PARAMETER_TYPE: {
        aggregate_type : AggregateParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case AGGREGATE_DATA_TYPE: {}
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
        LoadAggregateDataType( node_it_dst, &aggregate_type.base )
       }
       case ARRAY_PARAMETER_TYPE: {
        array_type : ArrayParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case ARRAY_DATA_TYPE_TYPE: {}
          case DIMENSION_LIST_TYPE: {}
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
       }
       case ABSOLUTE_TIME_PARAMETER_TYPE: {
        absolute_time_type : AbsoluteTimeParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case ABSOLUTE_TIME_DATA_TYPE: {}
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
       }
       case RELATIVE_TIME_PARAMETER_TYPE: {
        relative_time_type : RelativeTimeParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case TIME_ALARM_TYPE: {}
          case TIME_CONTEXT_ALARM_LIST_TYPE: {}
          case RELATIVE_TIME_DATA_TYPE: {}
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
       }
       case BOOLEAN_PARAMETER_TYPE: {
        bool_type : BooleanParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case BOOLEAN_ALARM_TYPE: {}
          case BOOLEAN_CONTEXT_ALARM_LIST_TYPE: {}
          case BOOLEAN_DATA_TYPE: {}
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
       }
       case FLOAT_PARAMETER_TYPE: {
        float_type : FloatParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case NUMERIC_ALARM_TYPE: {}
          case NUMERIC_CONTEXT_ALARM_LIST_TYPE: {}
          case FLOAT_DATA_TYPE: {}
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
       }
       case BINARY_PARAMETER_TYPE: {
        bin_type : BinaryParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case BINARY_ALARM_TYPE: {}
          case BINARY_CONTEXT_ALARM_LIST_TYPE: {}
          case BINARY_DATA_TYPE: {}
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
       }
       case INTEGER_PARAMETER_TYPE: {
        int_type : IntegerParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case NUMERIC_ALARM_TYPE: {
            LoadNumericAlarmType( n, &int_type.t_DefaultAlarm)
          }
          case NUMERIC_CONTEXT_ALARM_LIST_TYPE: {}
          case INTEGER_DATA_TYPE: {
           LoadIntegerDataType( n, &int_type.base )
          }
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
        // (s.p) store the base
        //
        LoadIntegerDataType(node_it_dst, &int_type.base)
        append(&system_node.element.t_TelemetryMetaData.t_ParameterTypeSet.t_choice_0.t_IntegerParameterType7, int_type)
       }
       case ENUMERATED_PARAMETER_TYPE: {
        enum_type : EnumeratedParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case ENUMERATION_ALARM_TYPE: {
            LoadEnumerationAlarmType(node_it_dst, &enum_type.t_DefaultAlarm)
          }
          case ENUMERATION_CONTEXT_ALARM_LIST_TYPE: {
            LoadEnumerationContextAlarmListType( node_it_dst, &enum_type.t_ContextAlarmList)
          }
          case ENUMERATED_DATA_TYPE: {
            LoadEnumeratedDataType(node_it_dst, &enum_type.base)
          }
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
        LoadEnumeratedDataType(node_it_dst, &enum_type.base)
       }
       case STRING_PARAMETER_TYPE: {
        string_type : StringParameterType
        t : utils.Stack(^utils.node_tree(utils.tuple(string, xml.Element)), 2000)
        utils.push_stack(&t, node_it_dst)
        for t.push_count > 0 {
         n := utils.get_front_stack(&t)
         utils.pop_stack(&t)
         //fmt.println(n.element.second)
         switch( n.element.first ) {
          case STRING_ALARM_TYPE: {}
          case STRING_CONTEXT_ALARM_LIST_TYPE: {}
          case STRING_DATA_TYPE: {}
         }
         for b := n.next; b != nil; b = b.right {
          utils.push_stack(&t, b)
         }
        }
       }
       case PARAMETER_SET_TYPE: {
        type : ParameterSetType

        LoadParameterSetType(node_it_dst, &type)
        system_node.element.t_TelemetryMetaData.t_ParameterSet = type
       }
       case CONTAINER_SET_TYPE: {
        type : ContainerSetType
        LoadContainerSetType(node_it_dst, &type)
        system_node.element.t_TelemetryMetaData.t_ContainerSet = type
       }
       case MESSAGE_SET_TYPE:   {}
       case STREAM_SET_TYPE:    {}
       case ALGORITHM_SET_TYPE: {}
      }

      //load_node_in_system(node_it_dst)

      for b := node_it.next; b != nil; b = b.right {
        push_stack(&node_values, b)
        push_stack(&node_values_dst, b)
      }
    }
  }

  return xml_handler
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadNameType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> NameType {
  type : NameType = {
    t_restriction = xs_normalized_string_get_default()
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == "name" {
        type.t_restriction.val = at.val
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

internal_DepthFirstSearch_Node :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)), key : string ) -> (xml.Attribute, ^utils.node_tree(utils.tuple(string, xml.Element))) {

  attribute : xml.Attribute
  node_ret  : ^utils.node_tree(utils.tuple(string, xml.Element))

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  attr_not_found := true
  for ; stack.push_count > 0 && attr_not_found;  {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == key {
        attribute = at
        node_ret  = n
        attr_not_found = false
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return attribute, node_ret

}

// ----------------------------------------------------------------------------------------------------------------- //

LoadLongDescriptionType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> LongDescriptionType {
  type : LongDescriptionType = {
    t_restriction = xs_string_get_default()
  }

  attr, _ := internal_DepthFirstSearch_Node( node, "LongDescription")

  if len(attr.key) > 0 {
    type.t_restriction.val = attr.val
  }

  return type
}


// ----------------------------------------------------------------------------------------------------------------- //

LoadAliasType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> AliasType {
  type : AliasType = {
    t_nameSpace = xs_string_get_default(),
    t_alias     = xs_string_get_default()
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == "nameSpace" {
        type.t_nameSpace.val = at.val
      }
      else if at.key == "alias" {
        type.t_alias.val = at.val
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }
  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadAliasSetType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> AliasSetType {
  type : AliasSetType

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == "Alias" {
        alias := LoadAliasType( n )
        append(&type.t_Alias, alias)
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadAncillaryDataType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> AncillaryDataType {
  type : AncillaryDataType = {
    t_name     = xs_string_get_default(),
    t_mimeType = xs_string_get_default(),
    t_href     = xs_any_URI_get_default()
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == "base" {
        type.base = at.val
      }
      else if at.key == "name" {
        type.t_name.val = at.val
      }
      else if at.key == "mimeType" {
        type.t_mimeType.val = at.val
      }
      else if at.key == "href" {
        type.t_href.val = transmute([]u8)at.val
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadAncillaryDataSetType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> AncillaryDataSetType {
  type : AncillaryDataSetType

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == "AncillaryData" {
        append( &type.t_AncillaryData, LoadAncillaryDataType(n) )
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadShortDescriptionType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> ShortDescriptionType {
  type : ShortDescriptionType = {
    t_restriction = xs_string_get_default()
  }

  attr, _ := internal_DepthFirstSearch_Node( node, "ShortDescription")
  if len(attr.key) > 0 {
    type.t_restriction.val = attr.val
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadDescriptionType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> DescriptionType {
  type : DescriptionType = {
    t_LongDescription  = LoadLongDescriptionType( node ),
    t_AliasSet         = LoadAliasSetType( node ),
    t_AncillaryDataSet = LoadAncillaryDataSetType( node ),
    t_shortDescription = LoadShortDescriptionType( node )
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadNameDescriptionType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> NameDescriptionType {
  type : NameDescriptionType = {
    base = LoadDescriptionType( node ),
    t_name = LoadNameType( node )
  }
  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadUnitFormType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> UnitFormType {
  type : UnitFormType = {
    t_restriction = xs_string_get_default()
  }

  // FIX: Is not in the correct allocator
  //
  type.t_enumeration_values = make([]string, len(t_UnitFormType_Enumeration[:]))

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    idx := 0
    for at in element.attribs {
      if slice.contains(t_UnitFormType_Enumeration[:], at.val) {
        type.t_enumeration_values[idx] = at.val
        idx += 1
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadUnitType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> UnitType {
  type : UnitType = {
    t_power       = xs_double_get_default(),
    t_factor      = xs_string_get_default(),
    t_description = LoadShortDescriptionType(node),
    t_form        = LoadUnitFormType(node)
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == "power" {
        type.t_power.val = strconv.atof(at.val)
      }
      else if at.key == "factor" {
        type.t_factor.val = at.val
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }
  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadUnitSetType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> UnitSetType {
  type : UnitSetType

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == "Unit" {
        unit_type := LoadUnitType( n )
        append(&type.t_Unit, unit_type)
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadNameReferenceType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)), name : string ) -> NameReferenceType {
  type : NameReferenceType = {
    t_restriction = xs_normalized_string_get_default()
  }

  attr, _ := internal_DepthFirstSearch_Node( node, name )

  if len(attr.key) > 0 {
    type.t_restriction.val = attr.val
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadBaseDataType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> BaseDataType {
  type : BaseDataType = {
    base = LoadNameDescriptionType( node ),
    t_UnitSet = LoadUnitSetType( node ),
    t_baseType = LoadNameReferenceType( node, "baseType" )
  }
  // (s.p) Now we store the choice selection for that base type
  //
  element := node.element.second

  return type
}


// ----------------------------------------------------------------------------------------------------------------- //

LoadFloatingPointNotationType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> FloatingPointNotationType {
  type : FloatingPointNotationType = {
    t_restriction = xs_string_get_default(),
    t_enumeration_values = make([]string, len(t_FloatingPointNotationType_Enumeration))
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    idx := 0
    for at in element.attribs {
      if slice.contains( t_FloatingPointNotationType_Enumeration[:], at.key ) {
        type.t_enumeration_values[idx] = at.key
        idx += 1
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadNonNegativeLongType :: proc() -> NonNegativeLongType {
  type : NonNegativeLongType = {
    t_restriction = xs_long_get_default()
  }
  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadRadixType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> RadixType {
  type : RadixType = {
    t_restriction = xs_string_get_default(),
    t_enumeration_values = make([]string, len(t_RadixType_Enumeration))
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    idx := 0
    for at in element.attribs {
      if slice.contains( t_RadixType_Enumeration[:], at.val ) {
        type.t_enumeration_values[idx] = at.val
        idx += 1
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}
// ----------------------------------------------------------------------------------------------------------------- //

LoadNumberFormatType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> NumberFormatType {
  type : NumberFormatType = {
    t_numberBase = LoadRadixType(node),
    t_minimumFractionDigits = LoadNonNegativeLongType(),
    t_maximumFractionDigits = LoadNonNegativeLongType(),
    t_minimumIntegerDigits  = LoadNonNegativeLongType(),
    t_maximumIntegerDigits  = LoadNonNegativeLongType(),
    t_negativeSuffix        = xs_string_get_default(),
    t_positiveSuffix        = xs_string_get_default(),
    t_negativePrefix        = xs_string_get_default(),
    t_positivePrefix        = xs_string_get_default(),
    t_showThousandsGrouping = xs_boolean_get_default(),
    t_notation              = LoadFloatingPointNotationType( node ),
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    for at in element.attribs {
      if at.key == "numberBase" {
        type.t_numberBase.t_restriction.val = at.val
      }
      else if at.key == "minimumFractionDigits" {
        type.t_minimumFractionDigits.t_restriction.integer = auto_cast strconv.atoi(at.val)
      }
      else if at.key == "maximumFractionDigits" {
        type.t_maximumFractionDigits.t_restriction.integer = auto_cast strconv.atoi(at.val)
      }
      else if at.key == "minimumIntegerDigits" {
        type.t_minimumIntegerDigits.t_restriction.integer = auto_cast strconv.atoi(at.val)
      }
      else if at.key == "maximumIntegerDigits" {
        type.t_maximumIntegerDigits.t_restriction.integer = auto_cast strconv.atoi(at.val)
      }
      else if at.key == "negativeSuffix" {
        type.t_negativeSuffix.val = at.val
      }
      else if at.key == "positiveSuffix" {
        type.t_positiveSuffix.val = at.val
      }
      else if at.key == "negativePrefix" {
        type.t_negativePrefix.val = at.val
      }
      else if at.key == "positivePrefix" {
        type.t_positiveSuffix.val = at.val
      }
      else if at.key == "showThousandsGrouping" {
        type.t_showThousandsGrouping.val = at.val == "true" ? true : false
      }
      else if at.key == "notation" {
        type.t_notation.t_restriction.val = at.val
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}
// ----------------------------------------------------------------------------------------------------------------- //

LoadToStringType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> ToStringType {
  type : ToStringType

  type.t_NumberFormat = LoadNumberFormatType( node )

  return type
}


// ----------------------------------------------------------------------------------------------------------------- //


 LoadPositiveLongType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> PositiveLongType {
  type : PositiveLongType = {
    t_restriction = xs_long_get_default()
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadBaseAlarmType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> BaseAlarmType {
  type : BaseAlarmType = {
    t_AncillaryDataSet = LoadAncillaryDataSetType( node ),
    t_name             = xs_string_get_default(),
    t_shortDescription = LoadShortDescriptionType( node )
  }

  attr, _ := internal_DepthFirstSearch_Node( node, "name" )

  type.t_name.val = attr.val

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadAlarmType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> AlarmType {
  type : AlarmType =  {
    base = LoadBaseAlarmType( node ),
    t_minViolations  = LoadPositiveLongType( node ),
    t_minConformance = LoadPositiveLongType( node ),
  }

  attr, node := internal_DepthFirstSearch_Node( node, "minViolations" )
  type.t_minViolations.t_restriction.integer = auto_cast strconv.atoi(attr.val)

  for it, idx in node.element.second.attribs {
    if it.val == "minConformace" {
     type.t_minConformance.t_restriction.integer = auto_cast strconv.atoi(attr.val)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadFloatRangeType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), el : string ) -> FloatRangeType {
  type : FloatRangeType = {
    t_minInclusive = xs_double_get_default(),
    t_maxInclusive = xs_double_get_default(),
    t_minExclusive = xs_double_get_default(),
    t_maxExclusive = xs_double_get_default()
  }

  attr, n := internal_DepthFirstSearch_Node( node, el )

  for attr in n.element.second.attribs {
    switch attr.key {
      case "minInclusive" : {
        type.t_minInclusive.val = strconv.atof(attr.val)
      }
      case "minExclusive" : {
        type.t_minExclusive.val = strconv.atof(attr.val)
      }
      case "maxInclusive" : {
        type.t_maxInclusive.val = strconv.atof(attr.val)
      }
      case "maxExclusive" : {
        type.t_maxExclusive.val = strconv.atof(attr.val)
      }
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadRangeFormType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)), el : string ) -> RangeFormType {
  type : RangeFormType = {
    t_restriction = xs_string_get_default(),
    t_enumeration_values = make([]string, len(t_RangeFormType_Enumeration))
  }

  attr, n := internal_DepthFirstSearch_Node(node, el)

  idx := 0
  for it in n.element.second.attribs {
    if slice.contains( t_RangeFormType_Enumeration[:], it.val ) {
      type.t_enumeration_values[idx] = it.val
      idx += 1
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadAlarmRangesType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> AlarmRangesType {
  type : AlarmRangesType = {
    base            = LoadBaseAlarmType(node),
    t_WatchRange    = LoadFloatRangeType(node, "WatchRange"),
    t_WarningRange  = LoadFloatRangeType(node, "WarningRange"),
    t_DistressRange = LoadFloatRangeType(node, "DistressRange"),
    t_CriticalRange = LoadFloatRangeType(node, "CriticalRange"),
    t_SevereRange   = LoadFloatRangeType(node, "SeverRange"),
    t_rangeForm     = LoadRangeFormType(node, "rangeForm")
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadChangeAlarmRangesType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> ChangeAlarmRangesType {
  type : ChangeAlarmRangesType

  utils.TODO(#procedure, "Not implemented yet")

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //


LoadAlarmMultiRangesType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> AlarmMultiRangesType {
  type : AlarmMultiRangesType

  utils.TODO(#procedure, "Not implemented yet")

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadNumericAlarmType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)), data : ^NumericAlarmType) {
  type : NumericAlarmType =  {
    base = LoadAlarmType( node ),
    t_StaticAlarmRanges = LoadAlarmRangesType( node ),
    t_ChangeAlarmRanges = LoadChangeAlarmRangesType( node ),
    t_AlarmMultiRanges  = LoadAlarmMultiRangesType( node )
  }
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadParameterRefTypes :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> [dynamic]ParameterRefType {
 types : [dynamic]ParameterRefType

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   element := n.element.second

   idx := 0
   for at in element.attribs {
     if at.key == "parameterRef" {
       member := LoadNameReferenceType( n, at.key )
       param_ref : ParameterRefType = {
        t_parameterRef = member
       }
       append(&types, param_ref)
     }
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return types
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadPhysicalAddressType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> PhysicalAddressType {
 type : PhysicalAddressType = {
  t_sourceName = xs_string_get_default(),
  t_sourceAddress = xs_string_get_default()
 }

 attrName, _ := internal_DepthFirstSearch_Node(node, "sourceName")
 attrAddr, _ := internal_DepthFirstSearch_Node(node, "sourceAddress")

 _, node_SubAddr := internal_DepthFirstSearch_Node(node, "SubAddress")

 if node_SubAddr != nil {
  type.t_SubAddress = new(PhysicalAddressType)
  type.t_SubAddress^ = LoadPhysicalAddressType( node_SubAddr )
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadPhysicalAddressSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> PhysicalAddressSetType {
 type : PhysicalAddressSetType

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   element := n.element.second

   idx := 0
   for at in element.attribs {
     if at.key == "PhysicalAddressType" {
       member := LoadPhysicalAddressType( n )
       append(&type.t_PhysicalAddress, member)
     }
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadParameterInstanceRefType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ParameterInstanceRefType {
 type : ParameterInstanceRefType

 utils.TODO(#procedure)

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //


LoadTimeAssociationUnitType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> TimeAssociationUnitType {
 type : TimeAssociationUnitType

 utils.TODO(#procedure)

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadTimeAssociationType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> TimeAssociationType {
 type : TimeAssociationType = {
  base = LoadParameterInstanceRefType( node ),
  t_interpolateTime = xs_boolean_get_default(),
  t_offset          = xs_double_get_default(),
  t_unit            = LoadTimeAssociationUnitType( node )
 }

 attrOffset, _    := internal_DepthFirstSearch_Node(node, "offset")
 attrInterpolateTime, _ := internal_DepthFirstSearch_Node(node, "interpolateTime")

 if len(attrOffset.val) > 0 {
  type.t_offset.val = strconv.atof(attrOffset.val)
 }

 if len(attrInterpolateTime.val) > 0 {
  type.t_interpolateTime.val = attrInterpolateTime.val == "True" ? true : false
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadTelemetryDataSourceType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> TelemetryDataSourceType {
 type : TelemetryDataSourceType = {
  t_restriction = xs_string_get_default(),
  t_enumeration_values = make([]string, len(t_TelemetryDataSourceType_Enumeration))
 }

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   element := n.element.second

   idx := 0
   for at in element.attribs {
     if slice.contains(t_TelemetryDataSourceType_Enumeration[:], at.val) {
       type.t_enumeration_values[idx] = at.val
       idx += 1
     }
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadParameterPropertiesType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ParameterPropertiesType {
 type : ParameterPropertiesType = {
  t_SystemName = xs_string_get_default(),
  t_ValidityCondition = LoadMatchCriteriaType(node),
  t_PhysicalAddressSet = LoadPhysicalAddressSetType( node ),
  t_TimeAssociation    = LoadTimeAssociationType( node ),
  t_dataSource         = LoadTelemetryDataSourceType( node ),
  t_readOnly           = xs_boolean_get_default(),
  t_persistence        = xs_boolean_get_default()
 }

 attrReadOnly, _    := internal_DepthFirstSearch_Node(node, "readOnly")
 attrPersistence, _ := internal_DepthFirstSearch_Node(node, "persistence")

 if len(attrReadOnly.val) > 0 {
  type.t_readOnly.val = attrReadOnly.val == "True" ? true : false
 }
 if len(attrPersistence.val) > 0 {
  type.t_persistence.val = attrPersistence.val == "True" ? true : false
 }

 return type
}


// ----------------------------------------------------------------------------------------------------------------- //

LoadParameterType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ParameterType {
 type : ParameterType = {
  base = LoadNameDescriptionType( node ),
  t_ParameterProperties = LoadParameterPropertiesType( node ),
  t_parameterTypeRef = LoadNameReferenceType( node, "parameterTypeRef"),
  t_initialValue = xs_string_get_default()
 }

 attr, _ := internal_DepthFirstSearch_Node(node, "initialValue")

 if len(attr.val) > 0 {
  type.t_initialValue.val = attr.val
 }

 return type
}

LoadParameterTypes :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> [dynamic]ParameterType {
 types : [dynamic]ParameterType

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   if n.element.first == "ParameterType" {
    member := LoadParameterType(n)
    append(&types, member)
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return types
}

// ----------------------------------------------------------------------------------------------------------------- //
// TODO: Check for minOccurs
//
LoadParameterSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), data : ^ParameterSetType ) {
 data.t_choice_0.t_ParameterRefType0 = LoadParameterRefTypes( node )
 data.t_choice_0.t_ParameterType1    = LoadParameterTypes( node )
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadRateInStreamType       :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)), element : string ) -> RateInStreamType {
  type : RateInStreamType = {}

  utils.TODO(#procedure)

  return type
}
// ----------------------------------------------------------------------------------------------------------------- //

LoadRateInStreamSetType    :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)), element : string ) -> RateInStreamSetType {
  type : RateInStreamSetType = {}

  utils.TODO(#procedure)

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadDataEncodingType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> DataEncodingType {
  type : DataEncodingType = {

  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadDiscreteLookupListType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> DiscreteLookupListType {
  type : DiscreteLookupListType = {}

  utils.TODO(#procedure)

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadLinearAdjustmentType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> LinearAdjustmentType {
  type : LinearAdjustmentType = {
    t_slope = xs_double_get_default(),
    t_intercept = xs_double_get_default()
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    for attr in n.element.second.attribs {
      if attr.key == "slope" {
        type.t_slope.val = strconv.atof(attr.val)
      }
      else if attr.key == "intercept" {
        type.t_intercept.val = strconv.atof(attr.val)
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadDynamicValueType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> DynamicValueType {
  type : DynamicValueType = {
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    switch n.element.first {
    case LINEAR_ADJUSTMENT_TYPE: {
      type.t_LinearAdjustment = LoadLinearAdjustmentType(n)
    }
    case PARAMETER_INSTANCE_REF_TYPE: {
      type.t_ParameterInstanceRef = LoadParameterInstanceRefType(n)
    }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadIntegerValueType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)), element : string ) -> IntegerValueType {
  type : IntegerValueType = {}

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    switch n.element.first {
    case DISCRETE_LOOKUP_LIST_TYPE: {
      d : DiscreteLookupListType
      d = LoadDiscreteLookupListType(node)
      type.t_choice_0 = d
    }
    case DYNAMIC_VALUE_TYPE : {
      d : DynamicValueType
      d = LoadDynamicValueType(node)
      type.t_choice_0 = d
    }
    case "xs_long": {
      if len(n.element.second.attribs) > 0 {
        l : xs_long = xs_long_get_default()
        l.integer   = auto_cast strconv.atoi(n.element.second.attribs[0].val)
        type.t_choice_0 = l
      }
    }
    case: {}
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadBinaryDataEncodingType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element)), element : string ) -> BinaryDataEncodingType {
  type : BinaryDataEncodingType = {
    base = LoadDataEncodingType(node),
    t_SizeInBits = LoadIntegerValueType(node, "SizeInBits"),
    t_FromBinaryTransformAlgorithm = LoadInputAlgorithmType(node),
    t_ToBinaryTransformAlgorithm   = LoadInputAlgorithmType(node)
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadContainerType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ContainerType {
 type : ContainerType = {
  base = LoadNameDescriptionType(node),
  t_DefaultRateInStream = LoadRateInStreamType(node, "DefaultRateInStream"),
  t_RateInStreamSet     = LoadRateInStreamSetType(node, "RateInStreamSet"),
  t_BinaryEncoding      = LoadBinaryDataEncodingType(node, "BinaryDataEncodingType")
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadSequenceEntryType ::  proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> SequenceEntryType {
 type : SequenceEntryType = {
  t_shortDescription = LoadShortDescriptionType(node),
  t_AncillaryDataSet = LoadAncillaryDataSetType(node),
  t_TimeAssociation  = LoadTimeAssociationType(node),
  t_IncludeCondition = LoadMatchCriteriaType(node),
 }

 utils.TODO(#procedure, "Not full type implementation yet")

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadParameterRefEntryType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ParameterRefEntryType {
 type : ParameterRefEntryType = {
  base = LoadSequenceEntryType(node),
  t_parameterRef = LoadNameReferenceType(node, "parameterRef")
 }

 return type
}
// ----------------------------------------------------------------------------------------------------------------- //

LoadEntryListType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> EntryListType {
 type : EntryListType

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   switch n.element.first {
    case ARRAY_PARAMETER_REF_ENTRY_TYPE: {}
    case INDIRECT_PARAMETER_REF_ENTRY_TYPE : {}
    case STREAM_SEGMENT_ENTRY_TYPE: {}
    case CONTAINER_SEGMENT_REF_ENTRY_TYPE : {}
    case PARAMETER_SEGMENT_REF_ENTRY_TYPE: {}
    case PARAMETER_REF_ENTRY_TYPE: {
     append(&type.t_choice_0.t_ParameterRefEntryType6, LoadParameterRefEntryType(n))
    }
    case: {}
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadRestrictionCriteriaType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), element : string ) -> RestrictionCriteriaType {
  type : RestrictionCriteriaType = {
    base = LoadMatchCriteriaType(node),
    //t_choice_0 = LoadContainerRefType(node)
  }
  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
   utils.push_stack(&stack, node)

   for stack.push_count > 0 {
     n := utils.get_front_stack(&stack)
     utils.pop_stack(&stack)

     if n.element.first == CONTAINER_REF_TYPE {
      c_typeref : ContainerRefType
      c_typeref.t_containerRef = LoadNameReferenceType(n, "containerRef")
      type.t_choice_0 = c_typeref
      break
     }

     for it := n.next; it != nil; it = it.right {
       utils.push_stack(&stack, it)
     }
   }
  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadBaseContainerType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> BaseContainerType {
 type : BaseContainerType = {
  t_RestrictionCriteria = LoadRestrictionCriteriaType(node, "RestrictionCriteria"),
  t_containerRef        = LoadNameReferenceType(node, "containerRef")
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadFixedIntegerValueType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), name : string ) -> FixedIntegerValueType {
 type : FixedIntegerValueType

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadSequenceContainerType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> SequenceContainerType {
 type : SequenceContainerType = {
  base            = LoadContainerType( node ),
  t_EntryList     = LoadEntryListType( node ),
  t_BaseContainer = LoadBaseContainerType( node ),
  t_abstract      = xs_boolean_get_default(),
  t_idlePattern   = LoadFixedIntegerValueType( node, "idlePatter" )
 }

 attr, _ := internal_DepthFirstSearch_Node(node, "abstract")

 if len(attr.key) > 0 {
  type.t_abstract.val = attr.val == "true" ? true : false
 }

 return type
}


LoadSequenceContainerTypes :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> [dynamic]SequenceContainerType {
 types : [dynamic]SequenceContainerType

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   if n.element.first == SEQUENCE_CONTAINER_TYPE {
    member := LoadSequenceContainerType(n)
    append(&types, member)
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return types
}

// ----------------------------------------------------------------------------------------------------------------- //

GetSequenceContainer :: proc( space_system : ^SpaceSystemType ) -> [dynamic]SequenceContainerType {
  return space_system.t_TelemetryMetaData.t_ContainerSet.t_choice_0.t_SequenceContainerType0
}

// ----------------------------------------------------------------------------------------------------------------- //
// TODO: Check for minOccurs
//
LoadContainerSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), data : ^ContainerSetType ) {
 data.t_choice_0.t_SequenceContainerType0 = LoadSequenceContainerTypes( node )
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadParameterTypeSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ParameterTypeSetType {
 type : ParameterTypeSetType = {}

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentTypeSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentTypeSetType {
 type : ArgumentTypeSetType = {}

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentAssignmentType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentAssignmentType {
 type : ArgumentAssignmentType = {
  t_argumentName = LoadNameReferenceType(node, "argumentName"),
  t_argumentValue = xs_string_get_default()
 }

 attr, _ := internal_DepthFirstSearch_Node(node, "argumentValue")
 if len(attr.key) > 0 {
  type.t_argumentValue.val = attr.val
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentAssignmentListType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentAssignmentListType {
 type : ArgumentAssignmentListType = {}


 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   if n.element.first == ARGUMENT_ASSIGNMENT_TYPE {
    append(&type.t_ArgumentAssignment, LoadArgumentAssignmentType(n))
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadBaseMetaCommandType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> BaseMetaCommandType {
 type : BaseMetaCommandType = {
  t_ArgumentAssignmentList = LoadArgumentAssignmentListType(node),
  t_metaCommandRef         = LoadNameReferenceType(node, "metaCommandRef")
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentType {
 type : ArgumentType = {
  base = LoadNameDescriptionType( node ),
  t_argumentTypeRef = LoadNameReferenceType( node, "argumentTypeRef" ),
  t_initialValue = xs_string_get_default()
 }

  attr, _ := internal_DepthFirstSearch_Node(node, "initialValue")
  if len(attr.key) > 0 {
   type.t_initialValue.val = attr.val
  }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentListType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentListType {
 type : ArgumentListType = {}

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)


 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   if n.element.first == ARGUMENT_TYPE {
    append(&type.t_Argument, LoadArgumentType(n))
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentLocationInContainerInBitsType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentLocationInContainerInBitsType {
 type : ArgumentLocationInContainerInBitsType =  {}

 utils.TODO(#procedure)

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentRepeatType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentRepeatType {
 type : ArgumentRepeatType = {}

 utils.TODO(#procedure)

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentMatchCriteriaType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentMatchCriteriaType {
 type : ArgumentMatchCriteriaType = {}

 utils.TODO(#procedure)

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentSequenceEntryType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentSequenceEntryType {
 type : ArgumentSequenceEntryType = {
  t_LocationInContainerInBits = LoadArgumentLocationInContainerInBitsType(node),
  t_RepeatEntry               = LoadArgumentRepeatType(node),
  t_IncludeCondition          = LoadArgumentMatchCriteriaType(node),
  t_AncillaryDataSet         = LoadAncillaryDataSetType(node),
  t_shortDescription          = LoadShortDescriptionType(node)
 }

 return type
}
// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentFixedValueEntryType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentFixedValueEntryType {
 type : ArgumentFixedValueEntryType = {
  base = LoadArgumentSequenceEntryType(node),
  t_name = xs_string_get_default(),
  t_binaryValue = xs_hex_binary_get_default(),
  t_sizeInBits  = LoadPositiveLongType(node)
 }

 attr, _ := internal_DepthFirstSearch_Node(node, "name")
 type.t_name.val = attr.val

 attr, _ = internal_DepthFirstSearch_Node(node, "binaryValue")
 type.t_binaryValue.val = auto_cast strconv.atoi(attr.val)

 attr, _ = internal_DepthFirstSearch_Node(node, "sizeInBits")
 type.t_sizeInBits.t_restriction.integer = auto_cast strconv.atoi(attr.val)

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentArgumentRefEntryType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentArgumentRefEntryType {
 type : ArgumentArgumentRefEntryType = {
  base = LoadArgumentSequenceEntryType(node),
  t_argumentRef = LoadNameReferenceType(node, "argumentRef")
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentContainerRefEntryType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentContainerRefEntryType {
 type : ArgumentContainerRefEntryType = {
  base = LoadArgumentSequenceEntryType(node),
  t_containerRef = LoadNameReferenceType(node, "containerRef")
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadArgumentParameterRefEntryType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ArgumentParameterRefEntryType {
 type : ArgumentParameterRefEntryType = {
  base = LoadArgumentSequenceEntryType(node),
  t_parameterRef = LoadNameReferenceType(node, "parameterRef")
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadCommandContainerEntryListType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> CommandContainerEntryListType {
 type : CommandContainerEntryListType = {
 }

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)


 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   switch n.element.first {
    case "ArgumentFixedValueEntryType" : {
     append(&type.t_choice_0.t_ArgumentFixedValueEntryType0, LoadArgumentFixedValueEntryType(node))
    }
   	case "ArgumentArrayArgumentRefEntryType" : {
     utils.TODO("ArgumentArrayArgumentRefEntryType")
   	}
   	case "ArgumentArgumentRefEntryType" : {
     append(&type.t_choice_0.t_ArgumentArgumentRefEntryType2, LoadArgumentArgumentRefEntryType(node))
   	}
   	case "ArgumentArrayParameterRefEntryType" : {
     utils.TODO("ArgumentArrayParameterRefEntryType")
   	}
   	case "ArgumentIndirectParameterRefEntryType" : {
     utils.TODO("ArgumentIndirectParameterRefEntryType")
   	}
   	case "ArgumentStreamSegmentEntryType" : {
     utils.TODO("ArgumentStreamSegmentEntryType")
   	}
   	case "ArgumentContainerSegmentRefEntryType" : {
   	 utils.TODO("ArgumentContainerSegmentRefEntryType")
   	}
   	case "ArgumentContainerRefEntryType" : {
     append(&type.t_choice_0.t_ArgumentContainerRefEntryType7, LoadArgumentContainerRefEntryType(node))
   	}
   	case "ArgumentParameterSegmentRefEntryType" : {
   	 utils.TODO("ArgumentParameterSegmentRefEntryType")
   	}
   	case "ArgumentParameterRefEntryType" : {
     append(&type.t_choice_0.t_ArgumentParameterRefEntryType9, LoadArgumentParameterRefEntryType(node))
   	}
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadCommandContainerType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> CommandContainerType {
 type : CommandContainerType = {
  base = LoadContainerType(node),
  t_EntryList = LoadCommandContainerEntryListType( node ),
  t_BaseContainer = LoadBaseContainerType(node)
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadMetaCommandType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> MetaCommandType {
 type : MetaCommandType = {
  base                             = LoadNameDescriptionType(node),
 	t_BaseMetaCommand                = LoadBaseMetaCommandType(node),
 	t_SystemName                     = xs_string_get_default(),
 	t_ArgumentList                   = LoadArgumentListType(node),
 	t_CommandContainer               = LoadCommandContainerType(node),
 	//t_TransmissionConstraintList     = LoadTransmissionConstraintListType(node),
 	//t_DefaultSignificance            = LoadSignificanceType(node),
 	//t_ContextSignificanceList        = LoadContextSignificanceListType(node),
 	//t_Interlock                      = LoadInterlockType(node),
 	//t_VerifierSet                    = LoadVerifierSetType(node),
 	//t_ParameterToSetList             = LoadParameterToSetListType(node),
 	//t_ParametersToSuspendAlarmsOnSet = LoadParametersToSuspendAlarmsOnSetType(node),
 	t_abstract                       = xs_boolean_get_default(),
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadMetaCommandSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> MetaCommandSetType {
 type : MetaCommandSetType = {
 }

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
   n := utils.get_front_stack(&stack)
   utils.pop_stack(&stack)

   switch n.element.first {
    case BLOCK_META_COMMAND_TYPE : {
     utils.TODO(BLOCK_META_COMMAND_TYPE)
    }
    case NAME_REFERENCE_TYPE     : {
     append(&type.t_choice_0.t_NameReferenceType1, LoadNameReferenceType(n, "MetaCommandRef"))
    }
    case META_COMMAND_TYPE       : {
     append(&type.t_choice_0.t_MetaCommandType2, LoadMetaCommandType(n))
    }
   }

   for it := n.next; it != nil; it = it.right {
     utils.push_stack(&stack, it)
   }
 }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadCommandContainerSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> CommandContainerSetType {
 type : CommandContainerSetType = {}

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadStreamSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> StreamSetType {
 type : StreamSetType = {}

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadAlgorithmSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> AlgorithmSetType {
 type : AlgorithmSetType = {}

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadIntegerDataType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), data : ^IntegerDataType ) {
  data.base = LoadBaseDataType(node)
  data.t_ToString = LoadToStringType(node)
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadMemberType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> MemberType {
 type : MemberType = {
  base = LoadNameDescriptionType(node),
  t_typeRef = LoadNameReferenceType(node, "typeRef"),
  t_initialValue = xs_string_get_default()
 }

 attr, n := internal_DepthFirstSearch_Node(node, "initialValue")
 type.t_initialValue.val = attr.val

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadMemberListType :: proc(node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> MemberListType {
 type : MemberListType = {}

 stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
 utils.push_stack(&stack, node)

 for stack.push_count > 0 {
  n := utils.get_front_stack(&stack)
  utils.pop_stack(&stack)

  element := n.element.second

  idx := 0
  for at in element.attribs {
    if at.key == "MemberList" {
      member := LoadMemberType(n)
      append(&type.t_Member, member)
    }
  }

  for it := n.next; it != nil; it = it.right {
    utils.push_stack(&stack, it)
  }
  }

 return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadAggregateDataType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), data : ^AggregateDataType ) {
  data.base = LoadNameDescriptionType(node)
  data.t_MemberList = LoadMemberListType(node)
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadValueEnumerationType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ValueEnumerationType {
  type : ValueEnumerationType = {
    t_value    = xs_long_get_default(),
    t_maxValue = xs_long_get_default(),
    t_label    = xs_string_get_default(),
    t_shortDescription = LoadShortDescriptionType(node)
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    idx := 0
    for at in element.attribs {
      if at.key == "value" {
        type.t_value.integer = auto_cast strconv.atoi(at.val)
      }
      else if at.key == "maxValue" {
        type.t_maxValue.integer = auto_cast strconv.atoi(at.val)
      }
      else if at.key == "label" {
        type.t_label.val = at.val
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadEnumerationListType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> EnumerationListType {
  type : EnumerationListType = {
  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    idx := 0
    for at in element.attribs {
      if at.key == "Enumeration" {
        val := LoadValueEnumerationType( n )
        append(&type.t_Enumeration, val)
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadEnumeratedDataType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), data : ^EnumeratedDataType  ) {
  data.base = LoadBaseDataType(node)
  data.t_EnumerationList = LoadEnumerationListType(node)
  data.t_initialValue    = xs_string_get_default()

  attr, n := internal_DepthFirstSearch_Node(node, "initialValue")

  data.t_initialValue.val = attr.val
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadConcernLevelsType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ConcernLevelsType {
  type : ConcernLevelsType = {

  }

  utils.TODO(#procedure)

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadEnumerationAlarmListType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> EnumerationAlarmListType {
  type : EnumerationAlarmListType

  utils.TODO(#procedure)

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadEnumerationAlarmType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element) ), data : ^EnumerationAlarmType  ) {
  data.base = LoadAlarmType( node )
  data.t_EnumerationAlarmList = LoadEnumerationAlarmListType( node )
  data.t_defaultAlarmLevel    = LoadConcernLevelsType( node )
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadComparisonType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ComparisonType {
  type : ComparisonType = {}

  utils.TODO(#procedure)

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadComparisonListType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> ComparisonListType {
  type : ComparisonListType = {}

  utils.TODO(#procedure)

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadBooleanExpressionType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> BooleanExpressionType {
  type : BooleanExpressionType = {}

  utils.TODO(#procedure)

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadSimpleAlgorithmType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> SimpleAlgorithmType {
  type : SimpleAlgorithmType = {

  }
  utils.TODO(#procedure)

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadInputSetType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> InputSetType {
  type : InputSetType = {

  }

  utils.TODO(#procedure)

  return type
}

LoadInputAlgorithmType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)) ) -> InputAlgorithmType {
  type : InputAlgorithmType = {
    base = LoadSimpleAlgorithmType(node),
    t_InputSet = LoadInputSetType( node )
  }

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadMatchCriteriaType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> MatchCriteriaType {
  type : MatchCriteriaType = {

  }

  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  type_found := false
  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    idx := 0
    if type_found {
        break
      }
    for at in element.attribs  {
      switch at.key {
        case "Comparison"       : {
          type.t_choice_0 = LoadComparisonType(n)
          type_found = true
        }
        case "ComparisonList"   : {
          type.t_choice_0 = LoadComparisonListType(n)
          type_found = true
        }
        case "BooleanExpresion" : {
          type.t_choice_0 = LoadBooleanExpressionType(n)
          type_found = true
        }
        case "CustomAlgorithm"  : {
          type.t_choice_0 = LoadInputAlgorithmType(n)
          type_found = true
        }
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }

  return type
}

LoadContextMatchType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> ContextMatchType {
  type : ContextMatchType = {
    base = LoadMatchCriteriaType( node )
  }
  return type
}

LoadEnumerationContextAlarmType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element))) -> EnumerationContextAlarmType {
  type : EnumerationContextAlarmType = {
    t_ContextMatch = LoadContextMatchType( node )
  }
  LoadEnumerationAlarmType( node, &type.base )

  return type
}

// ----------------------------------------------------------------------------------------------------------------- //

LoadEnumerationContextAlarmListType :: proc( node : ^utils.node_tree(utils.tuple(string, xml.Element)), data : ^EnumerationContextAlarmListType  ) {
  stack : utils.Stack( ^utils.node_tree(utils.tuple(string, xml.Element)), 4096 )
  utils.push_stack(&stack, node)

  for stack.push_count > 0 {
    n := utils.get_front_stack(&stack)
    utils.pop_stack(&stack)

    element := n.element.second

    idx := 0
    for at in element.attribs {
      if at.key == "ContextAlarm" {
        val := LoadEnumerationContextAlarmType( n )
        append(&data.t_ContextAlarm, val)
      }
    }

    for it := n.next; it != nil; it = it.right {
      utils.push_stack(&stack, it)
    }
  }
}

// ----------------------------------------------------------------------------------------------------------------- //

GetSpaceSystemParameterSetTypes :: proc( system : ^SpaceSystemType ) -> [dynamic]ParameterType {
 return system.t_TelemetryMetaData.t_ParameterSet.t_choice_0.t_ParameterType1
}

// ----------------------------------------------------------------------------------------------------------------- //

GetSpaceSystemParameterSetRefTypes :: proc( system : ^SpaceSystemType ) -> [dynamic]ParameterRefType {
 return system.t_TelemetryMetaData.t_ParameterSet.t_choice_0.t_ParameterRefType0
}

// ----------------------------------------------------------------------------------------------------------------- //

GetSpaceSystemName :: proc( system : ^SpaceSystemType ) -> string {
  name := system.base.t_name.t_restriction.val
 return len(name) > 0 ? name : "Non Defined"
}

// ----------------------------------------------------------------------------------------------------------------- //

GetSpaceSystemShortDescription :: proc( system : ^SpaceSystemType ) -> string {
  name := system.base.base.t_shortDescription.t_restriction.val
 return len(name) > 0 ? name : "Non Defined"
}

// ----------------------------------------------------------------------------------------------------------------- //

GetSpaceSystemLongDescription :: proc( system : ^SpaceSystemType ) -> string {
  name := system.base.base.t_LongDescription.t_restriction.val
 return len(name) > 0 ? name : "Non Defined"
}

// ----------------------------------------------------------------------------------------------------------------- //

GetSpaceSystemDate :: proc( system : ^SpaceSystemType ) -> string {
  name := system.t_Header.t_date.val
 return len(name) > 0 ? name : "Non Defined"
}

// ----------------------------------------------------------------------------------------------------------------- //

GetSpaceSystemVersion :: proc( system : ^SpaceSystemType ) -> string {
 return system.t_Header.t_version.val
}

// ----------------------------------------------------------------------------------------------------------------- //

SearchTypeInSystem :: proc( system : string, type : string, xml_handler : ^handler ) -> ^utils.node_tree(utils.tuple(string, xml.Element)) {

  // In a width-search we try to locate the node in which a space system starts
  //
  SpaceSystemNode : ^utils.node_tree(utils.tuple(string, xml.Element))
  TypeNode        : ^utils.node_tree(utils.tuple(string, xml.Element))
  node_values : utils.queue(^utils.node_tree(utils.tuple(string, xml.Element)), 4096)

  utils.PushQueue(&node_values, &xml_handler.tree_eval)

  system_not_found := true
  for ;node_values.IdxFront != node_values.IdxTail && system_not_found; {
    node_it := utils.GetFrontQueue(&node_values)
    utils.PopQueue(&node_values)

    el := node_it.element.second
    for it in el.attribs {
      if it.val == system {
        SpaceSystemNode = node_it
        system_not_found = false
      }
    }

    for b := node_it.next; b != node_it.tail && b != nil; b = b.right {
      utils.PushQueue(&node_values, b)
    }
  }

  if SpaceSystemNode == nil {
    return nil
  }

  utils.ClearQueue( &node_values )
  utils.PushQueue(&node_values, SpaceSystemNode)

  TypeNotFound := true
  for ;node_values.IdxFront != node_values.IdxTail && TypeNotFound; {
    node_it := utils.GetFrontQueue(&node_values)
    utils.PopQueue(&node_values)

    attr := node_it.element.first
    if attr == type {
      TypeNotFound = false
      TypeNode = node_it
    }

    for b := node_it.next; b != node_it.tail && b != nil; b = b.right {
      utils.PushQueue(&node_values, b)
    }
  }
  return TypeNode
}

// -----------------------------------------------------------------------------
