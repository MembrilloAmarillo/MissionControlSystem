package simple_hash

import "base:runtime"
import "core:hash/xxhash"
import "core:math"
import "core:math/rand"
import "core:mem"

import "core:fmt"

// https://fgiesen.wordpress.com/2019/02/11/cache-tables/
// Open addressing hash table

MAX_BUCKET_SIZE :: 12

Entry :: struct($key_type, $value_type: typeid) {
	hash:  u64,
	key:   key_type,
	filled: [MAX_BUCKET_SIZE]bool,
	value: [MAX_BUCKET_SIZE]value_type,
}

Table :: struct($key_type, $value_type: typeid) {
	LOAD_FACTOR_PERCENT: f32,
	count:               int "Number of valid items in table",
	allocated:           int "Number of slots for which we have allocated memory",
	slots_filled:        int "Number of slots that can't be used for new items",
	allocator:           runtime.Allocator,
	entries:             []Entry(key_type, value_type),
	SIZE_MIN:            int,
}

next_power_of_two :: proc(n: u64) -> u64 {
	power: u64 = 1

	for power < n {
		power = power * 2
	}

	return power
}

init :: proc(
	using table: ^$T/Table($key_type, $value_type),
	slots_to_allocate: u64 = 0,
	c_allocator := context.allocator,
) {
	allocator = c_allocator

	to_allocate := slots_to_allocate
	if slots_to_allocate == 0 {
		to_allocate = cast(u64)SIZE_MIN
	}

	n := next_power_of_two(to_allocate)

	allocated = auto_cast n

	entries = make_slice([]Entry(key_type, value_type), n, allocator)

	for &entry in entries {
		entry.hash = 0
	}
}

resize_hash_table :: proc( using table: ^$T/Table($key_type, $value_type) )
{
 fmt.println("[INFO] Reallocating hash table, current size", allocated)
 n := next_power_of_two( cast(u64)(allocated + 1))
 allocated = auto_cast n

 new_entry := make([]Entry(key_type, value_type), n, allocator)
 copy(new_entry, entries)
 delete(entries, allocator)
 // NOTE I think this will not work. Maybe I need to recreate the entries slice
 // and do a copy again
 //
 entries = new_entry
 fmt.println("[INFO] New hash table size", allocated)
}

deinit :: proc(using table: ^$T/Table($key_type, $value_type)) {
	delete(entries, allocator)
}

table_reset :: proc(using table: ^$T/Table($key_type, $value_type)) {
	count = 0
	slots_filled = 0
	for &entry in entries {
		entry.hash = 0
	}
}

insert_table :: proc(
	using table: ^$T/Table($key_type, $value_type),
	key: key_type,
	value: value_type,
	parent_key: u64 = 0,
) -> u64 {
	/*
  switch ODIN_ENDIAN {
  case .Little: {}
  case .Big: {}
  case .Unknown: {}
  case : {}
  }
  */
	key_hash : u64
	key_hash = xxhash.XXH3_64_with_seed(transmute([]u8)key, parent_key)

	index := key_hash % cast(u64)allocated

	entry := &entries[index]

	if entry.hash == 0 {
		slots_filled += 1
		entry.hash = key_hash
	}

	//bucket_indx := rand.uint64() % MAX_BUCKET_SIZE
 //count += 1
	//entry.value[bucket_indx] = value
	//entry.key = key

	default_v : value_type
 idx_to_insert := 0

	for v, idx in entry.filled {
	 if v == false {
	  idx_to_insert = idx
	  break
	 }
	}

	entry.filled[idx_to_insert] = true
	entry.value[idx_to_insert]  = value
	entry.key = key

 LOAD_FACTOR_PERCENT = cast(f32)slots_filled / cast(f32)allocated

 if LOAD_FACTOR_PERCENT > 0.6 {
  resize_hash_table(table)
 }

	return key_hash
}

delete_key_value_table :: proc(
	using table: ^$T/Table($key_type, $value_type),
	key: key_type,
	value: value_type,
	parent_key: u64 = 0,
) {
	key_hash: u64
	key_hash = xxhash.XXH3_64_with_seed(transmute([]u8)key, parent_key) //hash.sdbm(transmute([]u8)key, parent_key)

		index := key_hash % cast(u64)allocated

	entry := &entries[index]

	if entry.hash == 0 {
		return
	}

	for it := 0; it < MAX_BUCKET_SIZE; it += 1 {
		if entry.value[it] == value {
			entry.value[it] = {}
			count -= 1
		}
	}
}

get_hash_from_key :: proc(key : $key_type, parent_key : u64 = 0 ) -> u64 {

	key_hash: u64
	key_hash = xxhash.XXH3_64_with_seed(transmute([]u8)key, parent_key) //hash.sdbm(transmute([]u8)key, parent_key)

	return key_hash
}

delete_key_table :: proc(
	using table: ^$T/Table($key_type, $value_type),
	key: key_type,
	parent_key: u64 = 0,
) {
	key_hash: u64
	key_hash = xxhash.XXH3_64_with_seed(transmute([]u8)key, parent_key) //hash.sdbm(transmute([]u8)key, parent_key)

		index := key_hash % cast(u64)allocated
	entry := &entries[index]

	if entry.hash == 0 {
		return
	}

	entry.hash = 0
	default_val: key_type
	entry.key = default_val
	slots_filled -= 1

	LOAD_FACTOR_PERCENT = cast(f32)slots_filled / cast(f32)allocated
}

get_load_factor :: proc(using table: ^$T/Table($key_type, $value_type)) -> int {
	return LOAD_FACTOR_PERCENT
}

lookup_table_bucket :: proc(
	using table: ^$T/Table($key_type, $value_type),
	key: key_type,
	parent_key: u64 = 0,
) -> [MAX_BUCKET_SIZE]value_type {

	key_hash: u64
	key_hash = xxhash.XXH3_64_with_seed(transmute([]u8)key, parent_key) //hash.sdbm(transmute([]u8)key, parent_key)

	index := key_hash % cast(u64)allocated
	entry := &entries[index]

	return entry.value
}

lookup_table :: proc(
	using table: ^$T/Table($key_type, $value_type),
	key: key_type,
	parent_key: u64 = 0,
) -> value_type {
	key_hash: u64

	key_hash = xxhash.XXH3_64_with_seed(transmute([]u8)key, parent_key) //hash.sdbm(transmute([]u8)key, parent_key)

		index := key_hash % cast(u64)allocated
	entry := &entries[index]

	for it in entry.value {
		if it != nil {
			return it
		}
	}

	return nil
}
