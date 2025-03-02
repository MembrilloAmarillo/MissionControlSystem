package xml_metagen

import "base:runtime"

import "core:encoding/xml"
import "core:fmt"
import "core:math/bits"
import "core:os"
import "core:slice"
import "core:strings"
import "core:strconv"
import "core:unicode"

import hh "../code/simple_hash"
import utils "../code/utils"

enumeration_to_string :: proc( type : restriction_type, enumeration_name : string, allocator := context.temp_allocator ) -> string {
  text_store  : [6000]u8
  text_buffer : strings.Builder = strings.builder_from_bytes(text_store[:])

  text_return : string

  if len( type.enumeration ) > 0 {
    strings.write_string(&text_buffer, enumeration_name)
    strings.write_string(&text_buffer, " := [?]string { ")
    for en in type.enumeration {
      if en == "union" {
       break
      }
      strings.write_rune(&text_buffer, '\"')
      strings.write_string(&text_buffer, en)
      strings.write_rune(&text_buffer, '\"')
      strings.write_string(&text_buffer, ", ")
    }
    strings.write_string(&text_buffer, " }\n\n")
  }

  text_return = strings.to_string(text_buffer)

  return text_return
}

choice_tree_to_string :: proc( root_choice : ^choice, choice_type_name : string, allocator := context.temp_allocator ) -> string {

  text_store  : [6000]u8
  text_buffer : strings.Builder = strings.builder_from_bytes(text_store[:])

  n_choices := 0
  for iter := root_choice.next; iter != nil; iter = iter.right {
    n_choices += 1
  }

  first_width_order : utils.queue(^choice, 128)

  utils.PushQueue(&first_width_order, root_choice)

  unique_identifier : utils.queue(int, 128)

  it : int = 0
  utils.PushQueue(&unique_identifier, it)

  for first_width_order.IdxFront != first_width_order.IdxTail {
    ch := utils.GetFrontQueue(&first_width_order)
    utils.PopQueue(&first_width_order)

    //fmt.print(ch.element)
    max_bound_gt_one := false

    if ch.next != nil && ch != root_choice {
      buff : [64]u8
      identifier := utils.GetFrontQueue(&unique_identifier)
      utils.PopQueue(&unique_identifier)
      strings.write_string(&text_buffer, choice_type_name)
      strings.write_string(&text_buffer, strconv.itoa(buff[:], identifier))

      for el, idx in ch.element {
        if el.key == "minOccurs" || el.key == "maxOccurs" {
          if el.val != "1" && el.val != "0" {
            max_bound_gt_one = true
          }
        }
      }
      // NOTE: DISABLED THIS BECAUSE NOW WE DO IT AS ARRAY OF UNIONS
      // THAT IS MORE REALISTIC FOR XML REPRESENTATION
      if max_bound_gt_one && false {
        strings.write_string(&text_buffer, ":: struct {\n")
        for attr in ch.element {
          strings.write_rune(&text_buffer, '\t')
          strings.write_string(&text_buffer, attr.key)
          strings.write_string(&text_buffer, " : ")
          strings.write_string(&text_buffer, "string")
          strings.write_string(&text_buffer, ", // we do string type because maxOccurs and minOccurs can have non digit values stored \n")
        }
      } else {
        strings.write_string(&text_buffer, ":: union {\n")
      }
    }

    node_idx_it := 0
    repeated_type : [dynamic]string
    for b := ch.next; b != nil; b = b.right {
      defer node_idx_it += 1

      if b.next == nil {
        if len(b.element) > 1 {
          // TODO(s.p): check for minOccurss
          //strings.write_string(&text_buffer, b.element[0].val )
          //strings.write_string(&text_buffer, " : ")
          xs_element := strings.concatenate({"xs_", b.element[1].val}, allocator)
          el_name := has_namespace( "xtce", b.element[1].val) ? b.element[1].val[len("xtce:"):] : xs_element

          if slice.contains(repeated_type[:], el_name) {
            continue
          }
          else {
            append(&repeated_type, el_name)
          }

          strings.write_rune(&text_buffer, '\t')
          //if max_bound_gt_one {
          //  buff : [64]u8
          //  strings.write_string(&text_buffer, "t_")
          //  strings.write_string(&text_buffer, el_name)
          //  strings.write_string(&text_buffer, strconv.itoa(buff[:], node_idx_it))
          //  strings.write_string(&text_buffer, " : [dynamic]")
          //}

          if b.element[1].val == "embedded" {
            // next to embedded is base definition
            xs_element = strings.concatenate({"xs_", b.element[2].val}, allocator)
            el_name    = has_namespace( "xtce", b.element[2].val) ? b.element[1].val[len("xtce:"):] : xs_element
            strings.write_string(&text_buffer, "struct {\n\t")
            strings.write_string(&text_buffer, "t_base : ")
            strings.write_string(&text_buffer, el_name)
            strings.write_string(&text_buffer, ",\n\t")
            for i := 2; i < len(b.element); i += 1 {
              if b.element[i].val == "embedded" {
                strings.write_string(&text_buffer, b.element[i].key)
                strings.write_string(&text_buffer, " : string")
                //strings.write_string(&text_buffer, el_name)
                strings.write_string(&text_buffer, ",\n\t")
              }
            }
            strings.write_string(&text_buffer, "}")
          } else {
            strings.write_string(&text_buffer, el_name)
          }
          strings.write_string(&text_buffer, ",\n")
        }
        else {
          if len(b.element) == 1 {
            strings.write_string(&text_buffer, b.element[0].val)
          }
        }
      }
      else {
        //fmt.println("nested choice")
        it += 1
        if ch != root_choice {
          buff : [64]u8
          strings.write_rune(&text_buffer, '\t')
          strings.write_string(&text_buffer, choice_type_name)
          strings.write_string(&text_buffer, strconv.itoa(buff[:], utils.GetFrontQueue(&unique_identifier)))
          strings.write_string(&text_buffer, ",\n")
        }
        utils.PushQueue(&unique_identifier, it)
        utils.PushQueue(&first_width_order, cast(^choice)b)

      }
    }

    if ch.next != nil && ch != root_choice  {
      strings.write_string(&text_buffer, "}\n\n")
    }
  }

  ret_string := strings.to_string(text_buffer)
  //fmt.println(ret_string)

  return ret_string
}

slash_in_between_upper_letters :: proc( type : string ) -> string {
 b_type := strings.builder_make_len_cap(0, 256)
 first_upper := true
 len_s := 0
 for c in type {
   len_s += 1
  if unicode.is_upper(c) {
   if first_upper {
    first_upper = false
   }
   else {
    strings.write_rune(&b_type, cast(rune)'_')
    len_s += 1
   }
  }
  strings.write_rune(&b_type, c)
 }
 new_s := strings.to_string(b_type)
 return new_s
}

// ------------------------------------------------------------------------ //

gen_complex_content :: proc( file: os.Handle, type: schema_type_def, content : ^complex_content ) -> (string, string, string) {

  buffer             : string
  choice_buffer      : string
  enumeration_buffer : string

  text_store  : [6000]u8
  text_buffer : strings.Builder = strings.builder_from_bytes(text_store[:])

// store every element definition
  //
  minOccursPerType := make([]string, len(content.attr))
  maxOccursPerType := make([]string, len(content.attr))

  // Check for minOccurs and maxOccurs to know if there should be
  // an array instead of only a type definition
  //
  for attr, idx in content.attr {
    if attr.key == "minOccurs" {
      if attr.val != "0" && attr.val != "1" {
        minOccursPerType[idx] = attr.val
      }
    }
    if attr.key == "maxOccurs" {
      if attr.val == "unbounded" {
        maxOccursPerType[idx] = "dynamic"
      }
      else if attr.val != "0" && attr.val != "1" {
        maxOccursPerType[idx] = attr.val
      }
    }
  }

  for attrib, idx in content.attr {
    if attrib.key == "name" {
      is_type_name := false
      if idx + 1 < len(content.attr) {
        if content.attr[idx + 1].key == "type" {
          is_type_name = true
        }
      }

      if is_type_name {
        strings.write_string(&text_buffer, (cast(string)"\tt_"))
        strings.write_string(&text_buffer, attrib.val)
        strings.write_string(&text_buffer, (cast(string)" : "))

        if idx + 2 < len(content.attr) && len(maxOccursPerType[idx + 2]) > 0 {
          strings.write_string(&text_buffer, (cast(string)"["))
          strings.write_string(&text_buffer, maxOccursPerType[idx+2])
          strings.write_string(&text_buffer, (cast(string)"]"))
        }
        else if idx + 3 < len(content.attr) && len(maxOccursPerType[idx + 3]) > 0 {
          strings.write_string(&text_buffer, (cast(string)"["))
          strings.write_string(&text_buffer, maxOccursPerType[idx+3])
          strings.write_string(&text_buffer, (cast(string)"]"))
        }
        else if idx + 2 < len(content.attr) && len(minOccursPerType[idx+2]) > 0 {
          strings.write_string(&text_buffer,(cast(string)"["))
          strings.write_string(&text_buffer,minOccursPerType[idx+2])
          strings.write_string(&text_buffer,(cast(string)"]"))
        }
      }
    } else if attrib.key == "type" {
      if has_namespace("xtce:", attrib.val) {
        // In odin, avoid redeclaration cycles, by making it
        // a pointer to a type
        //
        if attrib.val[len("xtce:"):] == type.type_name {
          strings.write_string(&text_buffer,(cast(string)"^"))
        }
        strings.write_string(&text_buffer,attrib.val[len("xtce:"):])
      } else {
        strings.write_string(&text_buffer,(cast(string)"xs_"))
        strings.write_string(&text_buffer,attrib.val)
      }
      strings.write_string(&text_buffer,(cast(string)",\n"))
    }
  }

  if len(content.simple_type.base) > 0 {

    if len(content.simple_type.enumeration) > 0 {
      buff : [32]byte
      content_type_base := [?]string {
        "\tt_enumerations_",
        content.simple_type.base,
        ":[",
        strconv.itoa(buff[:], len(content.simple_type.enumeration)),
        "] string,\n"
      }
      enum_concat := strings.concatenate(content_type_base[:], allocator = context.temp_allocator)
      strings.write_string(&text_buffer, enum_concat)
    }
    base := content.simple_type.base
    xs_base := strings.concatenate({"xs_", content.simple_type.base})
    strings.write_string(&text_buffer, (cast(string)"\tt_restriction : "))
    strings.write_string(&text_buffer, has_namespace("xtce", content.simple_type.base) ? base[len("xtce:"):] : xs_base)
    strings.write_string(&text_buffer, (cast(string)",\n"))

    enumeration_buffer = enumeration_to_string( content.simple_type, strings.concatenate({"t_", type.type_name, "_Enumeration"}))
    //if len(enumeration_buffer) > 0 {
    //  os.write(file, transmute([]u8)(cast(string)"\tt_enumeration_values : []string,\n"))
    //}
  }
  // store every choice definition
  //
  choices := content.choices
  if choices != nil
  {
      type_struct := [?]string {
      "t_",
      type.type_name,
      }
      type_struct_concat := strings.concatenate(type_struct[:], allocator = context.allocator)


      it_choice_idx := 0
      for it_c := choices.next; it_c != nil; it_c = it_c.right {
        buf : [64]u8
        strings.write_string(&text_buffer, (cast(string)"\tt_choice_"))
        strings.write_string(&text_buffer, strconv.itoa(buf[:], it_choice_idx))
        strings.write_string(&text_buffer, (cast(string)" : "))
        for el, idx in it_c.element {
          if el.key == "minOccurs" || el.key == "maxOccurs" {
            if el.val != "1" && el.val != "0" {
              strings.write_string(&text_buffer, (cast(string)"["))
              if el.val == "unbounded" {
                strings.write_string(&text_buffer, (cast(string)"dynamic"))
              } else {
                strings.write_string(&text_buffer, el.val)
              }
              strings.write_string(&text_buffer, (cast(string)"]"))
            }
          }
        }
        strings.write_string(&text_buffer, type_struct_concat)
        strings.write_string(&text_buffer, strconv.itoa(buf[:], it_choice_idx))
        strings.write_string(&text_buffer, (cast(string)",\n"))
        it_choice_idx += 1
      }

      choice_buffer = choice_tree_to_string(choices, type_struct_concat)
  }
  buffer = strings.to_string( text_buffer )

  return buffer, choice_buffer, enumeration_buffer
}

// ------------------------------------------------------------------------ //

gen_type_into_file :: proc(file: os.Handle, type: schema_type_def ) {

  nested_content_buffer : [dynamic]string
  choice_buffer : string
  enumeration_buffer : string

  slashed_type := slash_in_between_upper_letters(type.type_name)
  os.write(file, transmute([]u8)strings.to_upper(slashed_type))
  os.write(file, transmute([]u8)(cast(string)" :: \""))
  os.write(file, transmute([]u8)type.type_name)
  os.write(file, transmute([]u8)(cast(string)"\" \n"))

  os.write(file, transmute([]u8)type.type_name)
  os.write(file, transmute([]u8)(cast(string)" :: struct {\n"))
  if len(type.base) > 0 {
    os.write(file, transmute([]u8)(cast(string)"\tbase : "))
    if has_namespace("xtce:", type.base) {
      os.write(file, transmute([]u8)type.base[len("xtce:"):])
    } else {
      os.write(file, transmute([]u8)type.base)
    }
    os.write(file, transmute([]u8)(cast(string)",\n"))
  }

  #partial switch content in type.content {
  case complex_content:
    {
      // store every element definition
      //
      minOccursPerType := make([]string, len(content.attr))
      maxOccursPerType := make([]string, len(content.attr))

      // Check for minOccurs and maxOccurs to know if there should be
      // an array instead of only a type definition
      //
      for attr, idx in content.attr {
        if attr.key == "minOccurs" {
          if attr.val != "0" && attr.val != "1" {
            minOccursPerType[idx] = attr.val
          }
        }
        if attr.key == "maxOccurs" {
          if attr.val == "unbounded" {
            maxOccursPerType[idx] = "dynamic"
          }
          else if attr.val != "0" && attr.val != "1" {
            maxOccursPerType[idx] = attr.val
          }
        }
      }

      for attrib, idx in content.attr {
        if attrib.key == "name" {
          is_type_name := false
          if idx + 1 < len(content.attr) {
            if content.attr[idx + 1].key == "type" {
              is_type_name = true
            }
          }

          if is_type_name {
            os.write(file, transmute([]u8)(cast(string)"\tt_"))
            os.write(file, transmute([]u8)attrib.val)
            os.write(file, transmute([]u8)(cast(string)" : "))

            if idx + 2 < len(content.attr) && len(maxOccursPerType[idx + 2]) > 0 {
              os.write(file, transmute([]u8)(cast(string)"["))
              os.write(file, transmute([]u8)maxOccursPerType[idx+2])
              os.write(file, transmute([]u8)(cast(string)"]"))
            }
            else if idx + 3 < len(content.attr) && len(maxOccursPerType[idx + 3]) > 0 {
              os.write(file, transmute([]u8)(cast(string)"["))
              os.write(file, transmute([]u8)maxOccursPerType[idx+3])
              os.write(file, transmute([]u8)(cast(string)"]"))
            }
            else if idx + 2 < len(content.attr) && len(minOccursPerType[idx+2]) > 0 {
              os.write(file, transmute([]u8)(cast(string)"["))
              os.write(file, transmute([]u8)minOccursPerType[idx+2])
              os.write(file, transmute([]u8)(cast(string)"]"))
            }
          }
        } else if attrib.key == "type" {
          if has_namespace("xtce:", attrib.val) {
            // In odin, avoid redeclaration cycles, by making it
            // a pointer to a type
            //
            if attrib.val[len("xtce:"):] == type.type_name {
              os.write(file, transmute([]u8)(cast(string)"^"))
            }
            os.write(file, transmute([]u8)attrib.val[len("xtce:"):])
          } else {
            os.write(file, transmute([]u8)(cast(string)"xs_"))
            os.write(file, transmute([]u8)attrib.val)
          }
          os.write(file, transmute([]u8)(cast(string)",\n"))
        }
      }
      if content.nested_content != nil {
        for c := content.nested_content; c != nil; c = c.nested_content {
          content_buffer, content_choice_buffer, content_enum_buffer := gen_complex_content( file, type, c )
          append(&nested_content_buffer, content_choice_buffer)
          append(&nested_content_buffer, content_enum_buffer)
          os.write(file, transmute([]u8)content_buffer)
        }
      }
      if len(content.simple_type.base) > 0 {
        /*
        simple_type_base := [?]string {
          "t_",
          content.simple_type.base,
          "type : ",
          content.simple_type.base,
          ",\n"
        }

        type_concat := strings.concatenate(simple_type_base[:], allocator = context.temp_allocator)
        os.write(file, transmute([]u8)type_concat)
        */
        if len(content.simple_type.enumeration) > 0 {
          buff : [32]byte
          content_type_base := [?]string {
            "\tt_enumerations_",
            content.simple_type.base,
            ":[",
            strconv.itoa(buff[:], len(content.simple_type.enumeration)),
            "] string,\n"
          }
          enum_concat := strings.concatenate(content_type_base[:], allocator = context.temp_allocator)
          os.write(file, transmute([]u8)enum_concat)
        }
        base := transmute([]u8)content.simple_type.base
        xs_base := transmute([]u8)strings.concatenate({"xs_", content.simple_type.base})
        os.write(file, transmute([]u8)(cast(string)"\tt_restriction : "))
        os.write(file, has_namespace("xtce", content.simple_type.base) ? base[len("xtce:"):] : xs_base)
        os.write(file, transmute([]u8)(cast(string)",\n"))

        enumeration_buffer = enumeration_to_string( content.simple_type, strings.concatenate({"t_", type.type_name, "_Enumeration"}))
        //if len(enumeration_buffer) > 0 {
        //  os.write(file, transmute([]u8)(cast(string)"\tt_enumeration_values : []string,\n"))
        //}
      }
      // store every choice definition
      //
      choices := content.choices
      if choices != nil
      {
          type_struct := [?]string {
          "t_",
          type.type_name,
          }
          type_struct_concat := strings.concatenate(type_struct[:], allocator = context.allocator)

          it_choice_idx := 0
          for it_c := choices.next; it_c != nil; it_c = it_c.right {
            buf : [64]u8
            os.write(file, transmute([]u8)(cast(string)"\tt_choice_"))
            os.write(file, transmute([]u8)strconv.itoa(buf[:], it_choice_idx))
            os.write(file, transmute([]u8)(cast(string)" : "))
            for el, idx in it_c.element {
              if el.key == "minOccurs" || el.key == "maxOccurs" {
                if el.val != "1" && el.val != "0" {
                  os.write(file, transmute([]u8)(cast(string)"["))
                  if el.val == "unbounded" {
                    os.write(file, transmute([]u8)(cast(string)"dynamic"))
                  } else {
                    os.write(file, transmute([]u8)el.val)
                  }
                  os.write(file, transmute([]u8)(cast(string)"]"))
                }
              }
            }
            os.write(file, transmute([]u8)type_struct_concat)
            os.write(file, transmute([]u8)strconv.itoa(buf[:], it_choice_idx))
            os.write(file, transmute([]u8)(cast(string)",\n"))
            it_choice_idx += 1
          }

          choice_buffer = choice_tree_to_string(choices, type_struct_concat)
      }
    }
  case restriction_type:
    {
      if len(content.base) > 0 {
        base := transmute([]u8)content.base
        xs_base := transmute([]u8)strings.concatenate({"xs_", content.base})
        os.write(file, transmute([]u8)(cast(string)"\tt_restriction : "))
        os.write(file, has_namespace("xtce", content.base) ? base[len("xtce:"):] : xs_base)
       os.write(file, transmute([]u8)(cast(string)",\n"))
      }
      enumeration_buffer = enumeration_to_string( content, strings.concatenate({"t_", type.type_name, "_Enumeration"}))
      if len(enumeration_buffer) > 0 {
        os.write(file, transmute([]u8)(cast(string)"\tt_enumeration_values : []string,\n"))
      }

      create_union := false
      for en in content.enumeration {
       if create_union {
        to_print := has_namespace("xtce", en) ? en[len("xtce:"):] : strings.concatenate({"xs_", en})
        os.write(file, transmute([]u8)(cast(string)"\t\t"))
        os.write(file, transmute([]u8)to_print)
        os.write(file, transmute([]u8)(cast(string)",\n"))
       }
       if en == "union" {
        create_union = true
        os.write(file, transmute([]u8)(cast(string)"\tt_union : union {\n"))
       }
      }

      if create_union {
       os.write(file, transmute([]u8)(cast(string)"\t}"))
      }

  }
}

  os.write(file, transmute([]u8)(cast(string)"\n}\n\n"))

  if len( enumeration_buffer ) > 0 {
    os.write(file, transmute([]u8)enumeration_buffer)
  }

  if len( choice_buffer ) > 0 {
    os.write(file, transmute([]u8)choice_buffer)
  }

  for it in nested_content_buffer {
    os.write(file, transmute([]u8)it)
  }

}

start :: proc(file_path: string, destination_file: string, allocator := context.allocator) {


  fmt.println("[INFO] Parsing file: ", file_path)
  fmt.println("[INFO] Autogen into: ", destination_file)
  schema := parse_xsd(file_path, allocator)

  file_handler: os.Handle
  file_error: os.Error
  file_handler, file_error = os.open(destination_file, os.O_CREATE | os.O_WRONLY)
  if file_error != 0 {
    fmt.println("Error openening file", destination_file, "error code", file_error)
  }

  os.write(file_handler, transmute([]u8)(cast(string)"package xtce_parser\n\n"))

  hash_schema(schema, allocator)

  for i := 0; i < schema.xsd_hash.allocated; i += 1 {
    el_entries := schema.xsd_hash.entries[i]
    el_found := false
    for j := 0; j < len(el_entries.value) && !el_found; j += 1 {
      el := el_entries.value[j]
      if len(el.type_name) > 0 {
        el_found = true
        gen_type_into_file(file_handler, el)
      }
    }
  }
}

main :: proc() {
  start("../data/SpaceSystem.xsd", "../code/xtce_parser/xtce_type.odin", context.allocator)
}
