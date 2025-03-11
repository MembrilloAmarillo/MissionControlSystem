package utils

import "core:fmt"
import "core:math"

// -----------------------------------------------------------------------------

TODO :: proc(args: ..string) {
	fmt.println("[TODO] ", args)
}

// -----------------------------------------------------------------------------

tuple :: struct($T: typeid, $R: typeid) {
	first:  T,
	second: R,
}

// -----------------------------------------------------------------------------

key_val :: struct($T: typeid, $R: typeid) {
	key: T,
	val: R,
}

// -----------------------------------------------------------------------------

node_tree :: struct($T: typeid) {
	parent, left, right, next, tail: ^node_tree(T),
	element:                         T,
	depth:                           int,
}

// -----------------------------------------------------------------------------

push_node :: proc(node, parent: ^$T/node_tree) {
	if parent.next == nil {
		parent.next = node
	} else {
		b: type_of(parent) = parent.next
		for ; b != parent.tail && b.right != nil; b = b.right {}
		b.right = node
		node.left = b
	}

	parent.tail = node
	node.parent = cast(^T)parent
	node.depth = parent.depth + 1
}

// -----------------------------------------------------------------------------

search_val_in_node :: proc(value: $T, root_node: ^node_tree) -> ^node_tree {

	stack: Stack(^T / node_tree, 2056)

	push_stack(&stack, root_node)

	for stack.push_count > 0 {
		v := get_front_stack(&stack)
		pop_stack(&stack)

		if v.element == value {
			return v
		}

		for b := v.next; b != nil; b = b.right {
			push_stack(&stack, b)
		}
	}

	return nil
}

// -----------------------------------------------------------------------------

Stack :: struct($T: typeid, $N: u32) where N > 1 {
	items:      [N]T,
	push_count: int,
}

// -----------------------------------------------------------------------------

push_stack :: #force_inline proc(stk: ^$T/Stack($V, $N), val: V) {
	assert(stk.push_count < len(stk.items))
	stk.items[stk.push_count] = val
	stk.push_count += 1
}

// -----------------------------------------------------------------------------

get_front_stack :: #force_inline proc(stk: ^$T/Stack($V, $N)) -> V {
	assert(stk.push_count > 0)
	return stk.items[stk.push_count - 1]
}

// -----------------------------------------------------------------------------

pop_stack :: #force_inline proc(stk: ^$T/Stack($V, $N)) {
	assert(stk.push_count > 0)
	stk.push_count -= 1
}

// -----------------------------------------------------------------------------

queue :: struct($T: typeid, $N: u32) where N > 1 {
	Items:      [N]T,
	IdxFront:   int,
	IdxTail:    int,
	N_Elements: int,
}

// -----------------------------------------------------------------------------

PushQueue :: #force_inline proc(q: ^$T/queue($V, $N), val: V) {
	q.Items[q.IdxTail] = val
	q.IdxTail = cast(int)math.mod(cast(f32)(q.IdxTail + 1), cast(f32)N)
	q.N_Elements += 1
}

// -----------------------------------------------------------------------------

PopQueue :: #force_inline proc(q: ^$T/queue($V, $N)) {
	if q.IdxFront == q.IdxTail && q.IdxFront != 0 {
		q.IdxFront, q.IdxTail = 0, 0
	} else {
		q.IdxFront = cast(int)math.mod(cast(f32)(q.IdxFront + 1), cast(f32)N)
	}
	q.N_Elements -= 1
}

// -----------------------------------------------------------------------------

GetFrontQueue :: #force_inline proc(q: ^$T/queue($V, $N)) -> V {
	return q.Items[q.IdxFront]
}

// -----------------------------------------------------------------------------

ClearQueue :: #force_inline proc(q: ^$T/queue($V, $N)) {
	q.IdxFront = 0
	q.IdxTail = 0
	q.N_Elements = 0
}

// -----------------------------------------------------------------------------
