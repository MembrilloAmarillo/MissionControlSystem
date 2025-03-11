package xtce_parser

import "core:unicode"

import "core:math/bits"

import utils "../utils"

// NOTE: In principle, I will not be using regex, as it does create a massive
// overhead, and taking into account the incredible amount of regex that an xml file
// will need, I will try to make the parsing handmade
//

// --------------------------------------------------------------- //

xml_occurs :: struct {
	minOccurs: u32,
	maxOccurs: u32,
}

// --------------------------------------------------------------- //

xml_name_type_usage :: struct {
	used: bool,
	name: string,
	type: string,
}

// --------------------------------------------------------------- //

xml_choice :: struct {
	_: union {
		xml_occurs, // minOccurs maxOccurs
		xml_name_type_usage, // name and type, plus if that type is being used at the momment
	},
}

// --------------------------------------------------------------- //

facet_order :: enum {
	FALSE,
	PARTIAL,
	TOTAL,
}

// --------------------------------------------------------------- //

facet_cardinality :: enum {
	FINITE,
	COUNTABLY_INFINITE,
}

// --------------------------------------------------------------- //

facet_bounded :: distinct bool

// --------------------------------------------------------------- //

facet_numeric :: distinct bool

// --------------------------------------------------------------- //

fundamental_facets :: struct {
	ordered:     facet_order,
	cardinality: facet_cardinality,
	bounded:     facet_bounded,
	numeric:     facet_numeric,
}

// --------------------------------------------------------------- //

xs_restriction :: struct {
	length:     u32,
	min_length: u32,
	max_length: u32,
	pattern:    string,
	//enumeration : simple_type
}

// --------------------------------------------------------------- //

xs_string :: struct {
	val:          string,
	using facets: fundamental_facets,
}

xs_string_get_default :: proc() -> xs_string {
	str := xs_string {
		val         = "",
		ordered     = .FALSE,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
		bounded     = false,
	}

	return str
}

// --------------------------------------------------------------- //

xs_boolean :: struct {
	val:          bool,
	using facets: fundamental_facets,
}

xs_boolean_get_default :: proc() -> xs_boolean {
	bl := xs_boolean {
		val         = false,
		ordered     = .FALSE,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
		bounded     = false,
	}

	return bl
}

// --------------------------------------------------------------- //

xs_integer :: distinct i64

// --------------------------------------------------------------- //

xs_decimal :: struct {
	val:          f32,
	using facets: fundamental_facets,
}

xs_decimal_get_default :: proc() -> xs_decimal {
	dec := xs_decimal {
		val         = 0,
		ordered     = .TOTAL,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
		bounded     = false,
	}

	return dec
}

// --------------------------------------------------------------- //

float_special_values :: enum {
	POSITIVE_ZERO,
	NEGATIVE_ZERO,
	POSITIVE_INFINITY,
	NEGATIVE_INFINITY,
	NOT_A_NUMBER,
}

// --------------------------------------------------------------- //

double_special_values :: distinct float_special_values

// --------------------------------------------------------------- //

xs_float :: struct {
	val:          f32,
	special:      float_special_values,
	using facets: fundamental_facets,
}

xs_float_get_default :: proc() -> xs_float {
	flt := xs_float {
		val         = 0,
		special     = .POSITIVE_ZERO,
		ordered     = .PARTIAL,
		cardinality = .FINITE,
		numeric     = true,
		bounded     = true,
	}
	return flt
}

// --------------------------------------------------------------- //

xs_double :: struct {
	val:          f64,
	special:      double_special_values,
	using facets: fundamental_facets,
}

xs_double_get_default :: proc() -> xs_double {
	flt := xs_double {
		val         = 0,
		special     = .POSITIVE_ZERO,
		ordered     = .PARTIAL,
		cardinality = .FINITE,
		numeric     = true,
		bounded     = true,
	}
	return flt
}

// --------------------------------------------------------------- //

xs_duration :: struct {
	years:          xs_integer,
	months:         xs_integer,
	days:           xs_integer,
	hours:          xs_integer,
	minutes:        xs_integer,
	seconds:        xs_decimal,
	is_negative:    xs_boolean,
	using facets:   fundamental_facets,
	lex_expression: string,
}

xs_duration_get_default :: proc() -> xs_duration {
	flt := xs_duration {
		years       = 0,
		months      = 0,
		days        = 0,
		hours       = 0,
		minutes     = 0,
		seconds     = xs_decimal_get_default(),
		ordered     = .PARTIAL,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
		bounded     = false,
	}
	return flt
}

// --------------------------------------------------------------- //

time_struct :: struct {
	hour:    xs_integer,
	minute:  xs_integer,
	seconds: xs_decimal,
}

xs_time :: struct {
	time:         union {
		time_struct,
		string, // endOfDay, NOTE: Go here for more info: https://www.w3.org/TR/2012/REC-xmlschema11-2-20120405/datatypes.html#time
	},
	timezone:     string, // optional
	using facets: fundamental_facets,
}

xs_time_get_default_time :: proc() -> xs_time {
	tm := xs_time {
		time = time_struct{hour = 0, minute = 0, seconds = xs_decimal_get_default()},
		timezone = "",
		ordered = .PARTIAL,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = false,
	}

	return tm
}

xs_time_get_default_end_of_day :: proc() -> xs_time {
	tm := xs_time {
		time        = "00:00:00",
		timezone    = "",
		ordered     = .PARTIAL,
		bounded     = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
	}

	return tm
}

// --------------------------------------------------------------- //

xs_dateTime :: struct {
	year:  xs_integer,
	month: xs_integer,
	day:   xs_integer,
	time:  xs_time,
}

xs_date_time_get_default :: proc() -> xs_dateTime {

	dt := xs_dateTime {
		year  = 0,
		month = 0,
		day   = 0,
		time  = xs_time_get_default_time(),
	}

	return dt
}

// --------------------------------------------------------------- //

xs_date :: struct {
	year:         xs_integer,
	month:        xs_integer,
	day:          xs_integer,
	timezone:     string, // optional
	using facets: fundamental_facets,
}

xs_date_get_default :: proc() -> xs_date {
	dat := xs_date {
		year        = 0,
		month       = 0,
		day         = 0,
		ordered     = .PARTIAL,
		bounded     = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
	}

	return dat
}

// --------------------------------------------------------------- //

xs_yearMonth :: struct {
	year:         xs_integer,
	month:        xs_integer,
	timezone:     string, // optional
	using facets: fundamental_facets,
}

xs_year_month_get_default :: proc() -> xs_yearMonth {
	ym := xs_yearMonth {
		year        = 0,
		month       = 0,
		ordered     = .PARTIAL,
		bounded     = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
	}

	return ym
}

// --------------------------------------------------------------- //

xs_year :: struct {
	year:         xs_integer,
	timezone:     string, // optional,
	using facets: fundamental_facets,
}

xs_year_get_default :: proc() -> xs_year {
	y := xs_year {
		year        = 0,
		ordered     = .PARTIAL,
		bounded     = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
	}

	return y
}

// --------------------------------------------------------------- //

xs_monthDay :: struct {
	month:        xs_integer,
	day:          xs_integer,
	timezone:     string, // optional
	using facets: fundamental_facets,
}

xs_month_day_get_default :: proc() -> xs_monthDay {
	md := xs_monthDay {
		month       = 0,
		day         = 0,
		ordered     = .PARTIAL,
		bounded     = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
	}

	return md
}

// --------------------------------------------------------------- //

xs_day :: struct {
	day:          xs_integer,
	timezone:     string, // optional
	using facets: fundamental_facets,
}

xs_day_get_default :: proc() -> xs_day {
	md := xs_day {
		day         = 0,
		ordered     = .PARTIAL,
		bounded     = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
	}

	return md
}

// --------------------------------------------------------------- //

xs_month :: struct {
	month:        xs_integer,
	timezone:     string, // optional
	using facets: fundamental_facets,
}

xs_month_get_default :: proc() -> xs_month {
	md := xs_month {
		month       = 0,
		ordered     = .PARTIAL,
		bounded     = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
	}

	return md
}

// --------------------------------------------------------------- //

xs_hexBinary :: struct {
	val:          xs_integer,
	using facets: fundamental_facets,
}

xs_hex_binary_get_default :: proc() -> xs_hexBinary {
	hb := xs_hexBinary {
		val         = 0,
		ordered     = .FALSE,
		bounded     = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric     = false,
	}

	return hb
}

// --------------------------------------------------------------- //

xs_base64binary :: struct {
	val:          []u8,
	using facets: fundamental_facets,
}

xs_base_64_binary_get_default :: proc() -> xs_base64binary {
	return xs_base64binary {
		ordered = .FALSE,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = false,
	}
}

// --------------------------------------------------------------- //

xs_anyURI :: struct {
	val:          []u8,
	using facets: fundamental_facets,
}

xs_any_URI_get_default :: proc() -> xs_anyURI {
	return xs_anyURI {
		ordered = .FALSE,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = false,
	}
}

// --------------------------------------------------------------- //

xs_normalizedString :: distinct xs_string

xs_normalized_string_get_default :: proc() -> xs_normalizedString {
	return xs_normalizedString {
		ordered = .FALSE,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = false,
	}
}


// --------------------------------------------------------------- //

xs_token :: distinct xs_string

xs_token_get_default :: proc() -> xs_token {
	return xs_token {
		ordered = .FALSE,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = false,
	}
}


// --------------------------------------------------------------- //

xs_language :: distinct xs_string

xs_language_get_default :: proc() -> xs_language {
	return xs_language {
		ordered = .FALSE,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = false,
	}
}

// --------------------------------------------------------------- //

xs_nmtoken :: distinct xs_string

xs_nmtoken_get_default :: proc() -> xs_nmtoken {
	return xs_nmtoken {
		ordered = .FALSE,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = false,
	}
}

// --------------------------------------------------------------- //

xs_nmtokens :: struct {
	tokens:       []xs_nmtoken,
	using facets: fundamental_facets,
}

xs_nmtokens_get_default :: proc() -> xs_nmtokens {
	return xs_nmtokens {
		ordered = .FALSE,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = false,
	}
}


// --------------------------------------------------------------- //

xs_nonPositiveInteger :: struct {
	integer:             xs_integer,
	max_inclusive_value: i32,
	using facets:        fundamental_facets,
}

xs_non_positive_integer_get_default :: proc() -> xs_nonPositiveInteger {
	return xs_nonPositiveInteger {
		integer = 0,
		max_inclusive_value = 0,
		ordered = .TOTAL,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_negativeInteger :: struct {
	integer:             xs_integer,
	max_inclusive_value: i32,
	using facets:        fundamental_facets,
}

xs_negative_integer_get_default :: proc() -> xs_negativeInteger {
	return xs_negativeInteger {
		integer = 0,
		max_inclusive_value = -1,
		ordered = .TOTAL,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_long :: struct {
	integer:             xs_integer,
	max_inclusive_value: i64,
	min_inclusive_value: i64,
	using facets:        fundamental_facets,
}

xs_long_get_default :: proc() -> xs_long {
	return xs_long {
		integer = 0,
		max_inclusive_value = 9223372036854775807,
		min_inclusive_value = -9223372036854775808,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_int :: struct {
	integer:             xs_integer,
	max_inclusive_value: i32,
	min_inclusive_value: i32,
	using facets:        fundamental_facets,
}

xs_int_get_default :: proc() -> xs_int {
	return xs_int {
		integer = 0,
		max_inclusive_value = 2147483647,
		min_inclusive_value = -2147483648,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_short :: struct {
	integer:             xs_integer,
	max_inclusive_value: i16,
	min_inclusive_value: i16,
	using facets:        fundamental_facets,
}

xs_short_get_default :: proc() -> xs_short {
	return xs_short {
		integer = 0,
		max_inclusive_value = 32767,
		min_inclusive_value = -32768,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_byte :: struct {
	integer:             xs_integer,
	max_inclusive_value: i8,
	min_inclusive_value: i8,
	using facets:        fundamental_facets,
}

xs_byte_get_default :: proc() -> xs_byte {
	return xs_byte {
		integer = 0,
		max_inclusive_value = 127,
		min_inclusive_value = -128,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_nonNegativeInteger :: struct {
	integer:             xs_integer,
	min_inclusive_value: i32,
	using facets:        fundamental_facets,
}

xs_non_negative_integer_get_default :: proc() -> xs_nonNegativeInteger {
	return xs_nonNegativeInteger {
		integer = 0,
		min_inclusive_value = 0,
		ordered = .TOTAL,
		bounded = false,
		cardinality = .COUNTABLY_INFINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_unsignedLong :: struct {
	integer:             xs_integer,
	max_inclusive_value: u64,
	min_inclusive_value: u8,
	using facets:        fundamental_facets,
}

xs_unsigned_long_get_default :: proc() -> xs_unsignedLong {
	return xs_unsignedLong {
		integer = 0,
		max_inclusive_value = 18446744073709551615,
		min_inclusive_value = 0,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_unsignedInt :: struct {
	integer:             xs_integer,
	max_inclusive_value: u32,
	min_inclusive_value: u8,
	using facets:        fundamental_facets,
}

xs_unsigned_int_get_default :: proc() -> xs_unsignedInt {
	return xs_unsignedInt {
		integer = 0,
		max_inclusive_value = 4294967295,
		min_inclusive_value = 0,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_unsignedShort :: struct {
	integer:             xs_integer,
	max_inclusive_value: u16,
	min_inclusive_value: u8,
	using facets:        fundamental_facets,
}

xs_unsigned_short_get_default :: proc() -> xs_unsignedShort {
	return xs_unsignedShort {
		integer = 0,
		max_inclusive_value = 65535,
		min_inclusive_value = 0,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_unsigedBinary :: struct {
	integer:             xs_integer,
	max_inclusive_value: u8,
	min_inclusive_value: u8,
	using facets:        fundamental_facets,
}

xs_unsigned_byte_get_default :: proc() -> xs_unsigedBinary {
	return xs_unsigedBinary {
		integer = 0,
		max_inclusive_value = 255,
		min_inclusive_value = 0,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_positiveInteger :: struct {
	integer:             xs_integer,
	max_inclusive_value: u64,
	min_inclusive_value: u8,
	using facets:        fundamental_facets,
}

xs_positive_integer_get_default :: proc() -> xs_positiveInteger {
	return xs_positiveInteger {
		integer = 0,
		max_inclusive_value = bits.U64_MAX,
		min_inclusive_value = 1,
		ordered = .TOTAL,
		bounded = true,
		cardinality = .FINITE,
		numeric = true,
	}
}

// --------------------------------------------------------------- //

xs_yearMonthDuration :: distinct xs_yearMonth

xs_year_month_duration_get_default :: proc() -> xs_yearMonthDuration {
	return cast(xs_yearMonthDuration)xs_year_month_get_default()
}

// --------------------------------------------------------------- //

xs_dayTimeDuration :: struct {
	day_time_frag: union {
		struct {
			day:  xs_integer,
			time: xs_time,
		},
		xs_time,
	},
}

xs_day_time_duration_get_default :: proc() -> xs_dayTimeDuration {
	return xs_dayTimeDuration{}
}

// --------------------------------------------------------------- //

// NOTE: For more info go to:
// https://www.w3.org/TR/2012/REC-xmlschema11-2-20120405/datatypes.html#dateTimeStamp
//
xs_dateTimeStamp :: distinct xs_dateTime

xs_date_time_stamp_get_default :: proc() -> xs_dateTimeStamp {

	return cast(xs_dateTimeStamp)xs_date_time_get_default()

}

// --------------------------------------------------------------- //
