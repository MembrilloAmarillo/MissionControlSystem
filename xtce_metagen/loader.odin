package xml_metagen

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

import my_hash "../code/simple_hash"

import utils "../code/utils"

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

          for el in content.attr {
            if type_found {
              type_definition = search_and_get_first_from_bucket(
                schema,
                el.val[len("xtce:"):],
              )
              break
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
          allocator,
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
