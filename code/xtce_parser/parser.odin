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
import "core:text/regex"

import utils "../utils"
import my_hash "../simple_hash"

/*
  XSD : Notes
  ---
  An XML Schema Definition (XSD) describes the structure of an XML document
  Example give:
  '''
  <?xml version="1.0"?>
  <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
    <xs:element name="note">
      <xs:complexType>
        <xs:sequence>
          <xs:element name="to" type="xs:string"/>
          <xs:element name="from" type="xs:string"/>
          <xs:element name="heading" type="xs:string"/>
          <xs:element name="body" type="xs:string"/>
        </xs:sequence>
      </xs:complexType>
    </xs:element>
  </xs:schema>
'''
  Numeric data types:
  Name 	                Description
  byte 	                A signed 8-bit integer
  decimal 	            A decimal value
  int 	                A signed 32-bit integer
  integer             	An integer value
  long 	                A signed 64-bit integer
  negativeInteger 	    An integer containing only negative values (..,-2,-1)
  nonNegativeInteger 	  An integer containing only non-negative values (0,1,2,..)
  nonPositiveInteger 	  An integer containing only non-positive values (..,-2,-1,0)
  positiveInteger      	An integer containing only positive values (1,2,..)
  short 	              A signed 16-bit integer
  unsignedLong 	        An unsigned 64-bit integer
  unsignedInt 	        An unsigned 32-bit integer
  unsignedShort 	      An unsigned 16-bit integer
  unsignedByte 	        An unsigned 8-bit integer
 */

CHECK_MEM_ERROR :: proc(error: vmem.Allocator_Error) {
	switch (error)
	{
	case .None:
		break
	case .Out_Of_Memory:
		fallthrough
	case .Invalid_Pointer:
		fallthrough
	case .Invalid_Argument:
		fallthrough
	case .Mode_Not_Implemented:
		fallthrough
	case:
		fmt.println("[ERROR] Allocation error ", error)
		panic("[ERROR] Mem error")
	}
}

// -----------------------------------------------------------------------------

xsd_schema :: struct {
	file_path:  string,
	document:   ^xml.Document,
	error:      xml.Error,
	tokens:     xml.Tokenizer,
	attributes: xml.Attributes,
	arena:      vmem.Arena,
	allocator:  runtime.Allocator,
	xsd_hash:   my_hash.Table(string, schema_type_def),
}

// -----------------------------------------------------------------------------

handler :: struct {
	table:     my_hash.Table(string, ^utils.node_tree(utils.tuple(string, xml.Element))),
	system:    space_system,
	tree_eval: utils.node_tree(utils.tuple(string, xml.Element)),
}

// -----------------------------------------------------------------------------

space_system :: distinct utils.node_tree(^SpaceSystemType)

// -----------------------------------------------------------------------------

parse_xsd :: proc(path_to_file: string, allocator := context.allocator) -> ^xsd_schema {

	data := new(xsd_schema, allocator)
	
	CHECK_MEM_ERROR(vmem.arena_init_growing(&data.arena))

	temp          := vmem.arena_temp_begin(&data.arena)
	data.allocator = vmem.arena_allocator(&data.arena)
	temp_alloc    := vmem.arena_allocator(&data.arena)

	xml_content, success := os.read_entire_file(path_to_file, temp_alloc)

	xml.init(&data.tokens, transmute(string)xml_content, path_to_file)

	data.file_path = path_to_file
	data.document, data.error = xml.parse_bytes(
		xml_content,
		xml.Options{flags = {.Error_on_Unsupported}, expected_doctype = "schema"},
		"",
		nil,
		data.allocator,
	)

	data.document.tokenizer = &data.tokens

	if data.error != .None {
		fmt.eprintln("[ERROR] ", data.error)
	}

	fmt.println("[INFO] xsd schema parsed")

	//data.attributes = make(xml.Attributes, allocator)
	attr_error := xml.parse_attributes(data.document, &data.attributes)

	if attr_error != .None {
		fmt.println("[ERROR] Could not parse attributes of ", path_to_file, "error: ", attr_error)
	}

	fmt.println("[INFO] xsd schema attributes parsed")

	my_hash.init(&data.xsd_hash, 256 << 10, data.allocator)

	return data
}
