package OrbitMCS

import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"
import "core:thread"

thread_pool :: struct {
	Pool:          thread.Pool,
	PoolArena:     vmem.Arena,
	PoolAllocator: mem.Allocator,
	N_Threads:     int,
	UserIdx:       int,
}

CreatePoolWithAllocator :: proc(n_threads: int = 1) -> ^thread_pool {
	pool: ^thread_pool = new(thread_pool)
	pool.N_Threads = n_threads
	pool.UserIdx = 0

	CHECK_MEM_ERROR(vmem.arena_init_growing(&pool.PoolArena))

	pool.PoolAllocator = vmem.arena_allocator(&pool.PoolArena)
	thread.pool_init(&pool.Pool, pool.PoolAllocator, n_threads)

	return pool
}

AddProcToPool :: proc(pool: ^thread_pool, task: thread.Task_Proc, data: rawptr = nil) {
	thread.pool_add_task(&pool.Pool, pool.PoolAllocator, task, data, pool.UserIdx)

	pool.UserIdx += 1
}
