package render

import "base:runtime"
import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:math/bits"
import "core:math/linalg/glsl"
import "core:mem"
import vmem "core:mem/virtual"
import "vendor:glfw"
import "vendor:stb/image"
import vk "vendor:vulkan"

import "core:time"

//import tracy "../third_party/odin-tracy"

VulkanDebugTiming :: struct {
	scope:    [dynamic]string,
	duration: [dynamic]f64,
}

Global_VulkanDebug: VulkanDebugTiming

debug_time_end :: proc(scope_name: string, tick: time.Tick) {
	end := time.tick_now()
	diff := time.tick_diff(tick, end)
	last_time := time.duration_milliseconds(diff)
	append(&Global_VulkanDebug.scope, scope_name)
	append(&Global_VulkanDebug.duration, last_time)
}

@(deferred_out = debug_time_end)
debug_time_add_scope :: proc(
	name: string,
	allocator := context.allocator,
) -> (
	scope_name: string,
	tick: time.Tick,
) {
	return _debug_time_add_scope(name, allocator)
}

_debug_time_add_scope :: proc(
	name: string,
	allocator := context.allocator,
) -> (
	scope_name: string,
	tick: time.Tick,
) {
	return name, time.tick_now()
}

// -----------------------------------------------------------------------------

MAX_BUFFER_2D_SIZE_BYTES :: 32 << 20 // 32 MB

MAX_FRAMES_IN_FLIGHT :: 2
DEVICE_EXTENSIONS := [?]cstring {
	"VK_KHR_swapchain",
	"VK_KHR_dynamic_rendering",
	"VK_EXT_descriptor_indexing",
}

VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

Window :: struct {
	w_width:         i32,
	w_height:        i32,
	w_window:        glfw.WindowHandle,
	w_surface:       vk.SurfaceKHR,
	scaling_factor:  glsl.vec2,
	focused_windows: bool,
}

QueueFamilyIndices :: struct {
	qfi_GraphicsAndCompute: u32,
	qfi_Presentation:       u32,
}

SwapchainSupportDetails :: struct {
	scsd_Capabilities:     vk.SurfaceCapabilitiesKHR,
	scsd_Formats:          []vk.SurfaceFormatKHR,
	scsd_PresentModes:     []vk.PresentModeKHR,
	scsd_FormatCount:      u32,
	scsd_PresentModeCount: u32,
}

Device :: struct {
	d_PhysicalDevice:    vk.PhysicalDevice,
	d_LogicalDevice:     vk.Device,
	d_GraphicsQueue:     vk.Queue,
	d_ComputeQueue:      vk.Queue,
	d_PresentationQueue: vk.Queue,
	d_FamilyIndices:     QueueFamilyIndices,
}

SwapChain :: struct {
	sc_SwapChainHandle: vk.SwapchainKHR,
	sc_Images:          [dynamic]vk.Image,
	sc_ImageViews:      [dynamic]vk.ImageView,
	sc_Format:          vk.Format,
	sc_Extent:          vk.Extent2D,
	sc_Framebuffers:    [dynamic]vk.Framebuffer,
	sc_Capabilities:    vk.SurfaceCapabilitiesKHR,
	sc_SurfaceFormats:  [dynamic]vk.SurfaceFormatKHR,
	sc_PresentModes:    [dynamic]vk.PresentModeKHR,
}

PipelineType :: enum {
	GRAPHICS2D,
	GRAPHICS3D,
	COMPUTE,
	RAY_TRACING,
	PipelineType_COUNT,
}

Pipeline :: struct {
	p_PipelineLayout: vk.PipelineLayout,
	p_Pipeline:       vk.Pipeline,
}

DescriptorSet :: struct {
	d_DescriptorSet:       [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	d_DescriptorSetLayout: vk.DescriptorSetLayout,
}

Semaphore :: struct {
	s_ImageAvailable:  [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	s_RenderFinished:  [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	s_ComputeFinished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	s_InFlight:        [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	s_ComputeInFlight: [MAX_FRAMES_IN_FLIGHT]vk.Fence,
}

Vertex3D :: struct {
	v_pos:       glsl.vec3,
	v_color:     glsl.vec3,
	v_tex_coord: glsl.vec2,
}

Vertex3D_SOA :: #soa[dynamic]Vertex3D

Vertex2D :: struct {
	v_p0:             glsl.vec2, // top left corner
	v_p1:             glsl.vec2, // bottom right corner
	v_color00:        glsl.vec4,
	v_color01:        glsl.vec4,
	v_color10:        glsl.vec4,
	v_color11:        glsl.vec4,
	v_tex_coord_p0:   glsl.vec2,
	v_tex_coord_p1:   glsl.vec2,
	corner_radius:    f32,
	edge_softness:    f32,
	border_thickness: f32,
}

Vertex2D_SOA :: #soa[dynamic]Vertex2D

VulkanImage :: struct {
	vi_width:        u32,
	vi_height:       u32,
	vi_Format:       vk.Format,
	vi_Tiling:       vk.ImageTiling,
	vi_UsageFlags:   vk.ImageUsageFlags,
	vi_Properties:   vk.MemoryPropertyFlags,
	vi_Image:        vk.Image,
	vi_DeviceMemory: vk.DeviceMemory,
	vi_ImageView:    vk.ImageView,
	vi_Layout:       vk.ImageLayout,
	vi_Sampler:      vk.Sampler,
}

VulkanBuffer :: struct {
	vb_Buffer:        vk.Buffer,
	vb_DeviceMemory:  vk.DeviceMemory,
	vb_MappedMemory:  rawptr,
	vb_Size:          vk.DeviceSize,
	vb_MaxSize:       vk.DeviceSize,
	vb_Properties:    vk.MemoryPropertyFlags,
	vb_UsageFlags:    vk.BufferUsageFlags,
	vb_InstanceCount: u32,
	vb_toDestroy:     bool,
}

VulkanBuffer_SOA :: #soa[dynamic]VulkanBuffer

UniformBufferUI :: struct {
	time:        f32,
	delta_time:  f32,
	width:       f32,
	height:      f32,
	AtlasWidth:  f32,
	AtlasHeight: f32,
}

UniformBuffer3D :: struct {
	width:  f32,
	height: f32,
	fov:    f32,
	zNear:  f32,
	zFar:   f32,
	mvp:    glsl.mat4,
}

Batch2D :: struct {
	vertices:    [dynamic]Vertex2D,
	indices:     [dynamic]u32,
	n_instances: [dynamic]u32,
}

Batch2D_SOA :: #soa[dynamic]Batch2D

Batch3D :: struct {
	vertices: [dynamic]Vertex3D,
	indices:  [dynamic]u32,
}

Batch3D_SOA :: #soa[dynamic]Batch3D

// The idea behing is:
// There are multiple batches, each batch (set of vertices and indices + n instances) is
// "one object", thus having Batch2D_SOA means multiple objects, each of diferent sizes and
// number of instances. Every of them are grouped by their attributes (e.g. every object inside
// ui elements to render).
// Each Batch can be rendered by a single VulkanBuffer, having VulkanBuffer_SOA and Batch2D_SOA means we can
// store multiple VulkanBuffer.
//
BufferBatchGroup :: struct {
	bb_VertexBuffer:   [dynamic]VulkanBuffer,
	bb_IndexBuffer:    [dynamic]VulkanBuffer,
	bb_2DBatches:      [dynamic]Batch2D,
	n_batches:         u32,
	current_batch_idx: i32,
}

VulkanIface :: struct {
	ArenaAllocator:           mem.Allocator,
	va_Window:                Window,
	va_Device:                Device,
	va_Instance:              vk.Instance,
	va_SwapChain:             SwapChain,
	va_RenderPass:            [dynamic]vk.RenderPass,
	va_Pipelines:             [dynamic]Pipeline,
	va_DescriptorPool:        vk.DescriptorPool,
	va_Descriptors:           [dynamic]DescriptorSet,
	va_CommandPool:           vk.CommandPool,
	// For compute pipelines
	//
	va_ShaderStorage:         [dynamic]vk.Buffer,
	va_ShaderMemory:          [dynamic]vk.DeviceMemory,
	// Uniform buffers
	//
	va_UniformBufferUI:       [MAX_FRAMES_IN_FLIGHT]VulkanBuffer,
	va_CurrentUB_UI:          UniformBufferUI,
	va_UniformBuffer3D:       [MAX_FRAMES_IN_FLIGHT]VulkanBuffer,
	va_CurrentUB_3D:          UniformBuffer3D,
	// Vulkan command buffers
	//
	va_CommandBuffers:        [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	va_ComputeCommandBuffers: [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	va_3DBufferBatch:         BufferBatchGroup,
	va_2DBufferBatch:         BufferBatchGroup,
	va_2DBufferBatchDestroy:  [MAX_FRAMES_IN_FLIGHT]BufferBatchGroup,
	bitmap:                   texture_bitmap,
	va_FontCache:             [dynamic]FontCache,
	va_DepthImage:            VulkanImage,
	va_TextureImage:          VulkanImage,
	va_Semaphores:            Semaphore,

	// For frames
	//
	va_CurrentFrame:          u32,
	va_LastTimeFrame:         f64,
	va_FramebufferResized:    bool,
	va_LastTime:              f64,

	// Debug
	//
	va_DebugMessenger:        vk.DebugUtilsMessengerEXT,

	// Input handling
	//
	va_OsInput:               [dynamic]os_input,
	glfw_timer:               time.Tick "input timer",
}

// -----------------------------------------------------------------------------

os_input_type :: enum i32 {
	ESCAPE             = 0,
	ENTER              = 1,
	SPACE              = 2,
	LEFT_CLICK         = 3,
	RIGHT_CLICK        = 4,
	BACKSPACE          = 5,
	CHARACHTER         = 6,
	LEFT_CLICK_RELEASE = 7,
	ARROW_DOWN         = 8,
	ARROW_UP           = 9,
	F1                 = 10,
	CTRL_F             = 11,
}

os_input_types :: distinct bit_set[os_input_type;i32]

os_input :: struct {
	type:        os_input_types,
	mouse_click: glsl.vec2,
	codepoint:   rune,
	scroll_off:  glsl.vec2,
}

// -----------------------------------------------------------------------------

CHECK_MEM_ERROR :: proc(error: vmem.Allocator_Error) {
	switch (error) {
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

rgba_to_norm :: #force_inline proc(rgba: glsl.vec4) -> glsl.vec4 {
	return {rgba.x / 255, rgba.y / 255, rgba.z / 255, rgba[3] / 255}
}

// -----------------------------------------------------------------------------

error_callback :: proc "c" (code: i32, desc: cstring) {
	context = runtime.default_context()
	fmt.println(desc, code)
}

// -----------------------------------------------------------------------------

key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	app: ^VulkanIface = cast(^VulkanIface)(glfw.GetWindowUserPointer(window))
	context = runtime.default_context()
	context.allocator = app.ArenaAllocator
	if key == glfw.KEY_ESCAPE && action == glfw.PRESS {
		glfw.SetWindowShouldClose(window, glfw.TRUE)
	} else if key == glfw.KEY_BACKSPACE && (action == glfw.PRESS || action == glfw.REPEAT) {
		append(&app.va_OsInput, os_input{os_input_types{.BACKSPACE}, {0, 0}, 0, {0, 0}})
	} else if key == glfw.KEY_UP && (action == glfw.PRESS || action == glfw.REPEAT) {
		end := time.tick_now()
		diff := time.tick_diff(app.glfw_timer, end)
		duration := time.duration_milliseconds(diff)
		if action == glfw.PRESS || duration >= 100 {
			append(&app.va_OsInput, os_input{os_input_types{.ARROW_UP}, {0, 0}, 0, {0, 0}})
		}
	} else if key == glfw.KEY_DOWN && (action == glfw.PRESS || action == glfw.REPEAT) {
		end := time.tick_now()
		diff := time.tick_diff(app.glfw_timer, end)
		duration := time.duration_milliseconds(diff)
		if action == glfw.PRESS || duration >= 100 {
			append(&app.va_OsInput, os_input{os_input_types{.ARROW_DOWN}, {0, 0}, 0, {0, 0}})
		}
	} else if key == glfw.KEY_F1 && action == glfw.PRESS {
		append(&app.va_OsInput, os_input{os_input_types{.F1}, {0, 0}, 0, {0, 0}})
	} else if key == glfw.KEY_F && action == glfw.PRESS && mods == glfw.MOD_CONTROL {
		append(&app.va_OsInput, os_input{os_input_types{.CTRL_F}, {0, 0}, 0, {0, 0}})
	}
}

// -----------------------------------------------------------------------------

character_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	app: ^VulkanIface = cast(^VulkanIface)(glfw.GetWindowUserPointer(window))
	context = runtime.default_context()
	context.allocator = app.ArenaAllocator
	end := time.tick_now()
	diff := time.tick_diff(app.glfw_timer, end)
	duration := time.duration_milliseconds(diff)
	if duration >= 100 {
		append(&app.va_OsInput, os_input{os_input_types{.CHARACHTER}, {0, 0}, codepoint, {0, 0}})
	}
}

// -----------------------------------------------------------------------------

windows_focus_callback :: proc "c" (window: glfw.WindowHandle, focused: i32) {
	app: ^VulkanIface = cast(^VulkanIface)(glfw.GetWindowUserPointer(window))
	context = runtime.default_context()
	context.allocator = app.ArenaAllocator
	if (focused > 0) {
		app.va_Window.focused_windows = true
	} else {
		app.va_Window.focused_windows = false
	}
}


// -----------------------------------------------------------------------------

mouse_scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset, yoffset: f64) {
	app: ^VulkanIface = cast(^VulkanIface)(glfw.GetWindowUserPointer(window))
	context = runtime.default_context()
	context.allocator = app.ArenaAllocator
	end := time.tick_now()
	diff := time.tick_diff(app.glfw_timer, end)
	duration := time.duration_milliseconds(diff)
	if len(app.va_OsInput) > 0 {
		idx_os := len(app.va_OsInput) - 1
		os_input_val := app.va_OsInput[idx_os]
		if os_input_val.scroll_off.y < cast(f32)yoffset {
			scroll := glsl.vec2{os_input_val.scroll_off.x, cast(f32)yoffset}
			append(&app.va_OsInput, os_input{os_input_types{.ARROW_UP}, {0, 0}, 0, scroll})
		} else {
			scroll := glsl.vec2{os_input_val.scroll_off.x, cast(f32)yoffset}
			append(&app.va_OsInput, os_input{os_input_types{.ARROW_DOWN}, {0, 0}, 0, scroll})
		}
	} else {
		scroll := glsl.vec2{cast(f32)xoffset, cast(f32)yoffset}
		if yoffset > 0 {
			append(&app.va_OsInput, os_input{os_input_types{.ARROW_UP}, {0, 0}, 0, scroll})
		} else {
			append(&app.va_OsInput, os_input{os_input_types{.ARROW_DOWN}, {0, 0}, 0, scroll})
		}
	}
}

// -----------------------------------------------------------------------------

mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button, action, mods: i32) {
	app: ^VulkanIface = cast(^VulkanIface)(glfw.GetWindowUserPointer(window))
	context = runtime.default_context()
	context.allocator = app.ArenaAllocator
	if (button == glfw.MOUSE_BUTTON_LEFT && action == glfw.PRESS) {
		xpos, ypos := glfw.GetCursorPos(app.va_Window.w_window)
		append(
			&app.va_OsInput,
			os_input{os_input_types{.LEFT_CLICK}, {cast(f32)xpos, cast(f32)ypos}, 0, {0, 0}},
		)
	} else if (button == glfw.MOUSE_BUTTON_LEFT && action == glfw.RELEASE) {
		xpos, ypos := glfw.GetCursorPos(app.va_Window.w_window)
		append(
			&app.va_OsInput,
			os_input {
				os_input_types{.LEFT_CLICK_RELEASE},
				{cast(f32)xpos, cast(f32)ypos},
				0,
				{0, 0},
			},
		)
	}
}

// -----------------------------------------------------------------------------

framebuffer_resize_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	app: ^VulkanIface = cast(^VulkanIface)(glfw.GetWindowUserPointer(window))
	app.va_FramebufferResized = true
}
// -----------------------------------------------------------------------------

when ODIN_OS == .Windows {
	debugCallback :: proc "stdcall" (
		messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
		messageType: vk.DebugUtilsMessageTypeFlagsEXT,
		pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
		pUserData: rawptr,
	) -> b32 {
		context = runtime.default_context()
		fmt.println("validation layer: ", pCallbackData.pMessage)

		return false
	}
}

when ODIN_OS == .Linux {
	debugCallback :: proc "cdecl" (
		messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
		messageType: vk.DebugUtilsMessageTypeFlagsEXT,
		pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
		pUserData: rawptr,
	) -> b32 {
		context = runtime.default_context()
		fmt.println("validation layer: ", pCallbackData.pMessage)

		return false
	}
}
// -----------------------------------------------------------------------------

populate_debug_messenger_create_info :: proc(createInfo: ^vk.DebugUtilsMessengerCreateInfoEXT) {
	createInfo.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	createInfo.messageSeverity = {.VERBOSE, .WARNING, .ERROR}
	createInfo.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
	createInfo.pfnUserCallback = debugCallback
	createInfo.pUserData = nil
}

// -----------------------------------------------------------------------------

check_validation_layer_support :: proc(vapp: ^VulkanIface) -> bool {
	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)

	available_layers := make([]vk.LayerProperties, layer_count, context.temp_allocator)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

	outer: for name in VALIDATION_LAYERS {
		for i in 0 ..< layer_count {
			fmt.eprintf("Validation support: %s\n", available_layers[i].layerName)
			if cstring(&available_layers[i].layerName[0]) == cstring(name) do continue outer
		}
		fmt.eprintf("ERROR: validation layer %q not available\n", name)
		return false
	}

	return true
}

// -----------------------------------------------------------------------------

find_queue_families :: proc(
	v_interface: ^VulkanIface,
	device: vk.PhysicalDevice,
) -> QueueFamilyIndices {
	indices: QueueFamilyIndices
	indices.qfi_GraphicsAndCompute = bits.U32_MAX
	indices.qfi_Presentation = bits.U32_MAX

	queue_family_count: u32 = 0
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete_slice(queue_families)

	vk.GetPhysicalDeviceQueueFamilyProperties(
		device,
		&queue_family_count,
		raw_data(queue_families),
	)

	i: u32 = 0
	for &family in queue_families {
		if (.GRAPHICS in family.queueFlags) && (.COMPUTE in family.queueFlags) {
			indices.qfi_GraphicsAndCompute = i
		}

		present_support: b32
		if vk.GetPhysicalDeviceSurfaceSupportKHR(
			   device,
			   i,
			   v_interface.va_Window.w_surface,
			   &present_support,
		   ) !=
		   .SUCCESS {
			panic("[ERROR] GetPhysicalDeviceSurfaceSupportKHR was not succesful")
		}
		if present_support {
			indices.qfi_Presentation = i
		}
		if indices.qfi_GraphicsAndCompute != bits.U32_MAX &&
		   indices.qfi_Presentation != bits.U32_MAX {
			fmt.println("[INFO] Found adequate queue families")
			return indices
		}

		i = i + 1
	}

	return indices
}

// -----------------------------------------------------------------------------

check_device_extension_support :: proc(
	v_interface: ^VulkanIface,
	device: vk.PhysicalDevice,
) -> bool {
	extension_count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)

	available_extension := make(
		[]vk.ExtensionProperties,
		extension_count,
		v_interface.ArenaAllocator,
	)

	vk.EnumerateDeviceExtensionProperties(
		device,
		nil,
		&extension_count,
		raw_data(available_extension),
	)

	ext_found := false
	for extension in DEVICE_EXTENSIONS {
		ext_found = false
		for i in 0 ..< extension_count {
			if cstring(&available_extension[i].extensionName[0]) == cstring(extension) {
				fmt.println("[INFO] Found device extensions", extension)
				ext_found = true
			}
		}
		if !ext_found {
			delete_slice(available_extension, v_interface.ArenaAllocator)
			return false
		}
	}

	delete_slice(available_extension, v_interface.ArenaAllocator)
	return ext_found
}

// -----------------------------------------------------------------------------

query_swapchain_support :: proc(
	v_interface: ^VulkanIface,
	device: vk.PhysicalDevice,
	allocator := context.allocator,
) -> SwapchainSupportDetails {
	details: SwapchainSupportDetails
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		device,
		v_interface.va_Window.w_surface,
		&details.scsd_Capabilities,
	)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(
		device,
		v_interface.va_Window.w_surface,
		&details.scsd_FormatCount,
		nil,
	)

	// arena_alloc :: proc(arena: ^Arena, size, alignment: uint, loc := #caller_location) -> (data: []u8, err: Allocator_Error) {…}


	details.scsd_Formats = nil
	if details.scsd_FormatCount != 0 {
		details.scsd_Formats = make([]vk.SurfaceFormatKHR, details.scsd_FormatCount, allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			device,
			v_interface.va_Window.w_surface,
			&details.scsd_FormatCount,
			raw_data(details.scsd_Formats),
		)
	}

	vk.GetPhysicalDeviceSurfacePresentModesKHR(
		device,
		v_interface.va_Window.w_surface,
		&details.scsd_PresentModeCount,
		nil,
	)

	details.scsd_PresentModes = nil
	if details.scsd_PresentModeCount != 0 {
		details.scsd_PresentModes = make(
			[]vk.PresentModeKHR,
			details.scsd_PresentModeCount,
			allocator,
		)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device,
			v_interface.va_Window.w_surface,
			&details.scsd_PresentModeCount,
			raw_data(details.scsd_PresentModes),
		)
	}

	return details
}

// -----------------------------------------------------------------------------

is_suitable_device :: proc(v_interface: ^VulkanIface, device: vk.PhysicalDevice) -> bool {
	indices := find_queue_families(v_interface, device)
	extensions_supported := check_device_extension_support(v_interface, device)
	swapchain_adequate := false

	if extensions_supported {
		swapchain_support := query_swapchain_support(v_interface, device, context.temp_allocator)
		swapchain_adequate =
			swapchain_support.scsd_Formats != nil && swapchain_support.scsd_PresentModes != nil

		//defer delete( swapchain_support.scsd_Formats,      v_interface.ArenaAllocator );
		//defer delete( swapchain_support.scsd_PresentModes, v_interface.ArenaAllocator );
	}

	return(
		indices.qfi_GraphicsAndCompute != bits.U32_MAX &&
		indices.qfi_Presentation != bits.U32_MAX &&
		extensions_supported &&
		swapchain_adequate \
	)
}

// -----------------------------------------------------------------------------

create_image :: proc(vi: ^VulkanIface, img: ^VulkanImage) {
	imageInfo := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {width = img.vi_width, height = img.vi_height, depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		format = img.vi_Format,
		tiling = img.vi_Tiling,
		initialLayout = .UNDEFINED,
		usage = img.vi_UsageFlags,
		samples = vk.SampleCountFlags{._1},
		sharingMode = .EXCLUSIVE,
	}

	if vk.CreateImage(vi.va_Device.d_LogicalDevice, &imageInfo, nil, &img.vi_Image) != .SUCCESS {
		panic("[ERROR] Failed to create image!")
	}

	memRequirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(vi.va_Device.d_LogicalDevice, img.vi_Image, &memRequirements)

	allocInfo := vk.MemoryAllocateInfo {
		sType          = .MEMORY_ALLOCATE_INFO,
		allocationSize = memRequirements.size,
	}

	allocInfo.memoryTypeIndex = find_memory_type(
		vi.va_Device.d_PhysicalDevice,
		memRequirements.memoryTypeBits,
		img.vi_Properties,
	)

	if vk.AllocateMemory(vi.va_Device.d_LogicalDevice, &allocInfo, nil, &img.vi_DeviceMemory) !=
	   .SUCCESS {
		panic("[ERROR] Failed to allocate image memory\n")
	}

	vk.BindImageMemory(vi.va_Device.d_LogicalDevice, img.vi_Image, img.vi_DeviceMemory, 0)
}

// -----------------------------------------------------------------------------
find_depth_format :: proc(vi: ^VulkanIface, depthFormats: []vk.Format) -> Maybe(vk.Format) {
	depthFormat: Maybe(vk.Format)
	tiling: vk.ImageTiling = vk.ImageTiling.OPTIMAL

	for format in depthFormats {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(vi.va_Device.d_PhysicalDevice, format, &props)

		if tiling == vk.ImageTiling.LINEAR &&
		   .DEPTH_STENCIL_ATTACHMENT in props.linearTilingFeatures {
			depthFormat = format
			break
		} else if tiling == vk.ImageTiling.OPTIMAL &&
		   .DEPTH_STENCIL_ATTACHMENT in props.optimalTilingFeatures {
			depthFormat = format
			break
		}
	}

	return depthFormat
}

// -----------------------------------------------------------------------------

create_depth_resources :: proc(vi: ^VulkanIface) {

	depthFormats := [?]vk.Format{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}
	flags := vk.FormatFeatureFlags{.DEPTH_STENCIL_ATTACHMENT}

	d_f, ok := find_depth_format(vi, depthFormats[:]).?

	fmt.println(d_f)

	vi.va_DepthImage.vi_width = vi.va_SwapChain.sc_Extent.width
	vi.va_DepthImage.vi_height = vi.va_SwapChain.sc_Extent.height
	vi.va_DepthImage.vi_Format = d_f
	vi.va_DepthImage.vi_Tiling = .OPTIMAL
	vi.va_DepthImage.vi_UsageFlags = vk.ImageUsageFlags{.DEPTH_STENCIL_ATTACHMENT}
	vi.va_DepthImage.vi_Properties = vk.MemoryPropertyFlags{.DEVICE_LOCAL}

	create_image(vi, &vi.va_DepthImage)

	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = vi.va_DepthImage.vi_Image,
		viewType = .D2,
		format = vi.va_DepthImage.vi_Format,
		components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
		subresourceRange = {
			aspectMask = vk.ImageAspectFlags{.DEPTH},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	if vk.CreateImageView(
		   vi.va_Device.d_LogicalDevice,
		   &create_info,
		   nil,
		   &vi.va_DepthImage.vi_ImageView,
	   ) !=
	   .SUCCESS {
		panic("[ERROR] Could not create image view")
	}

}
// -----------------------------------------------------------------------------

create_image_views :: proc(vi: ^VulkanIface) {
	n_images := len(vi.va_SwapChain.sc_Images)
	if vi.va_SwapChain.sc_ImageViews == nil {
		vi.va_SwapChain.sc_ImageViews = make([dynamic]vk.ImageView, n_images, vi.ArenaAllocator)
	} else {
		resize(&vi.va_SwapChain.sc_ImageViews, n_images)
	}

	i := 0
	for &image in vi.va_SwapChain.sc_Images {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image,
			viewType = .D2,
			format = vi.va_SwapChain.sc_Format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {
				aspectMask = vk.ImageAspectFlags{.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}

		if vk.CreateImageView(
			   vi.va_Device.d_LogicalDevice,
			   &create_info,
			   nil,
			   &vi.va_SwapChain.sc_ImageViews[i],
		   ) !=
		   .SUCCESS {
			panic("[ERROR] Could not create image view")
		}
		i = i + 1
	}
}

// -----------------------------------------------------------------------------

create_swap_chain :: proc(vi: ^VulkanIface) {
	surface_format: vk.SurfaceFormatKHR
	present_mode: vk.PresentModeKHR
	extent: vk.Extent2D

	support := query_swapchain_support(vi, vi.va_Device.d_PhysicalDevice, context.temp_allocator)
	//defer delete( support.scsd_Formats,      vi.ArenaAllocator );
	//defer delete( support.scsd_PresentModes, vi.ArenaAllocator );

	image_count: u32 = support.scsd_Capabilities.minImageCount + 1

	if support.scsd_Capabilities.maxImageCount > 0 &&
	   image_count > support.scsd_Capabilities.maxImageCount {
		image_count = support.scsd_Capabilities.maxImageCount
	}

	for format in support.scsd_Formats {
		// .B8G8R8A8_SRGB gives me not good results
		//
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			surface_format = format
		}
	}

	found_mailbox := false

	for mode in support.scsd_PresentModes {
		if mode == .MAILBOX {
			fmt.println("[INFO] MAILBOX mode enabled")
			found_mailbox = true
			present_mode = .MAILBOX
			break
		}
	}
	if !found_mailbox {
		fmt.println("[INFO] MAILBOX mode not found swaping to FIFO mode")
		present_mode = .FIFO
	}

	// [s.p.] I put this here sometimes just to try
	// present_mode = .IMMEDIATE

	if support.scsd_Capabilities.currentExtent.width != bits.U32_MAX {
		extent = support.scsd_Capabilities.currentExtent
	} else {
		width, height: i32

		width, height = glfw.GetFramebufferSize(vi.va_Window.w_window)

		extent = {cast(u32)width, cast(u32)height}
		extent.width = clamp(
			extent.width,
			support.scsd_Capabilities.minImageExtent.width,
			support.scsd_Capabilities.maxImageExtent.width,
		)
		extent.height = clamp(
			extent.height,
			support.scsd_Capabilities.minImageExtent.height,
			support.scsd_Capabilities.maxImageExtent.height,
		)
	}

	vi.va_SwapChain.sc_Extent = extent

	sc_create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = vi.va_Window.w_surface,
		minImageCount    = image_count,
		imageFormat      = surface_format.format,
		imageColorSpace  = surface_format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = vk.ImageUsageFlags{.COLOR_ATTACHMENT},
		preTransform     = support.scsd_Capabilities.currentTransform,
		compositeAlpha   = vk.CompositeAlphaFlagsKHR{.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
		//oldSwapchain     = nil
	}

	indices := find_queue_families(vi, vi.va_Device.d_PhysicalDevice)

	qFamilyIndices := [?]u32{indices.qfi_GraphicsAndCompute, indices.qfi_Presentation}
	if indices.qfi_GraphicsAndCompute != indices.qfi_Presentation {
		sc_create_info.imageSharingMode = .CONCURRENT
		sc_create_info.queueFamilyIndexCount = 2
		sc_create_info.pQueueFamilyIndices = &qFamilyIndices[0]
	} else {
		sc_create_info.imageSharingMode = .EXCLUSIVE
	}

	if vk.CreateSwapchainKHR(
		   vi.va_Device.d_LogicalDevice,
		   &sc_create_info,
		   nil,
		   &vi.va_SwapChain.sc_SwapChainHandle,
	   ) !=
	   .SUCCESS {
		panic("[ERROR] Could not create swapchain")
	}

	n_images: u32
	vk.GetSwapchainImagesKHR(
		vi.va_Device.d_LogicalDevice,
		vi.va_SwapChain.sc_SwapChainHandle,
		&n_images,
		nil,
	)

	if vi.va_SwapChain.sc_Images == nil {
		vi.va_SwapChain.sc_Images = make([dynamic]vk.Image, n_images, vi.ArenaAllocator)
	} else {
		resize(&vi.va_SwapChain.sc_Images, n_images)
	}
	vk.GetSwapchainImagesKHR(
		vi.va_Device.d_LogicalDevice,
		vi.va_SwapChain.sc_SwapChainHandle,
		&n_images,
		raw_data(vi.va_SwapChain.sc_Images),
	)

	vi.va_SwapChain.sc_Format = surface_format.format
	vi.va_SwapChain.sc_Extent = extent
	vi.va_SwapChain.sc_Capabilities = support.scsd_Capabilities
}

// -----------------------------------------------------------------------------

create_render_pass :: proc(vi: ^VulkanIface) {
	color_attachment := vk.AttachmentDescription {
		format         = vi.va_SwapChain.sc_Format,
		samples        = vk.SampleCountFlags{._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	depthFormats := [?]vk.Format{.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}
	depth_format, ok := find_depth_format(vi, depthFormats[:]).?
	if !ok {
		panic("[ERROR] Could not find depth format")
	}

	depth_attachment := vk.AttachmentDescription {
		format         = depth_format,
		samples        = vk.SampleCountFlags{._1},
		loadOp         = .CLEAR,
		storeOp        = .DONT_CARE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	color_attachment_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	depth_attachment_ref := vk.AttachmentReference {
		attachment = 1,
		layout     = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint       = .GRAPHICS,
		colorAttachmentCount    = 1,
		pColorAttachments       = &color_attachment_ref,
		pDepthStencilAttachment = &depth_attachment_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT, .LATE_FRAGMENT_TESTS},
		srcAccessMask = vk.AccessFlags{.DEPTH_STENCIL_ATTACHMENT_WRITE},
		dstStageMask  = vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT, .EARLY_FRAGMENT_TESTS},
		dstAccessMask = vk.AccessFlags{.COLOR_ATTACHMENT_WRITE, .DEPTH_STENCIL_ATTACHMENT_WRITE},
	}

	attachments := [?]vk.AttachmentDescription{color_attachment, depth_attachment}

	render_pass_info := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 2,
		pAttachments    = raw_data(attachments[:]),
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	render_pass_idx := 0
	if (vi.va_RenderPass == nil) {
		vi.va_RenderPass = make([dynamic]vk.RenderPass, 1, vi.ArenaAllocator)
	} else {
		render_pass_idx = len(vi.va_RenderPass)
		append(&vi.va_RenderPass, vk.RenderPass{})
		//CHECK_MEM_ERROR( error );
	}

	if vk.CreateRenderPass(
		   vi.va_Device.d_LogicalDevice,
		   &render_pass_info,
		   nil,
		   &vi.va_RenderPass[render_pass_idx],
	   ) !=
	   .SUCCESS {
		panic("[ERROR] Could not create render pass")
	}
}

// -----------------------------------------------------------------------------

add_descriptor_set_layout :: proc(vi: ^VulkanIface, layouts: []vk.DescriptorType) {
	n_layouts := len(layouts)

	layout_bindings := make([]vk.DescriptorSetLayoutBinding, n_layouts, context.temp_allocator)
	//defer delete_slice( layout_bindings, context.allocator );

	for i in 0 ..< n_layouts {
		if layouts[i] == .UNIFORM_BUFFER {
			layout_bindings[i].binding = cast(u32)i
			layout_bindings[i].descriptorCount = 1
			layout_bindings[i].descriptorType = .UNIFORM_BUFFER
			layout_bindings[i].pImmutableSamplers = nil
			layout_bindings[i].stageFlags = vk.ShaderStageFlags{.VERTEX}
		} else if layouts[i] == .COMBINED_IMAGE_SAMPLER {
			layout_bindings[i].binding = cast(u32)i
			layout_bindings[i].descriptorCount = 1
			layout_bindings[i].descriptorType = .COMBINED_IMAGE_SAMPLER
			layout_bindings[i].pImmutableSamplers = nil
			layout_bindings[i].stageFlags = vk.ShaderStageFlags{.FRAGMENT}
		}
	}

	layoutInfo := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = cast(u32)n_layouts,
		pBindings    = raw_data(layout_bindings),
	}

	descriptor_idx := len(vi.va_Descriptors)
	if descriptor_idx == 0 {
		vi.va_Descriptors = make([dynamic]DescriptorSet, 1, vi.ArenaAllocator)
	} else {
		error := reserve(&vi.va_Descriptors, descriptor_idx + 1)
		CHECK_MEM_ERROR(error)
	}
	if (vk.CreateDescriptorSetLayout(
			   vi.va_Device.d_LogicalDevice,
			   &layoutInfo,
			   nil,
			   &vi.va_Descriptors[descriptor_idx].d_DescriptorSetLayout,
		   ) !=
		   .SUCCESS) {
		panic("[ERROR] Failed to create compute descriptor set layout")
	}
}

// -----------------------------------------------------------------------------

create_shader_module :: proc(device: vk.Device, code: []u8) -> vk.ShaderModule {
	createInfo := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = auto_cast raw_data(code),
	}

	shaderModule: vk.ShaderModule
	if (vk.CreateShaderModule(device, &createInfo, nil, &shaderModule) != .SUCCESS) {
		panic("[ERROR] Failed to create shader module\n")
	}

	return shaderModule
}

// -----------------------------------------------------------------------------
V_GetVertex3DBindingDescription :: proc() -> vk.VertexInputBindingDescription {
	bindingDescription := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = size_of(Vertex3D),
		inputRate = .VERTEX,
	}

	return bindingDescription
}

// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
V_GetVertex2DBindingDescription :: proc() -> vk.VertexInputBindingDescription {
	bindingDescription := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = size_of(Vertex2D),
		inputRate = .INSTANCE,
	}

	return bindingDescription
}

// -----------------------------------------------------------------------------

add_pipeline :: proc(
	vi: ^VulkanIface,
	pipeline: ^Pipeline,
	vert_data: []u8,
	frag_data: []u8,
	type: PipelineType,
) {
	if type == PipelineType.COMPUTE {
		fmt.println("[TODO] Not implemented COMPUTE pipelines yet")
		return
	}
	vert_sm := create_shader_module(vi.va_Device.d_LogicalDevice, vert_data)
	frag_sm := create_shader_module(vi.va_Device.d_LogicalDevice, frag_data)

	defer vk.DestroyShaderModule(vi.va_Device.d_LogicalDevice, vert_sm, nil)
	defer vk.DestroyShaderModule(vi.va_Device.d_LogicalDevice, frag_sm, nil)

	vertShaderStageInfo := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = vk.ShaderStageFlags{.VERTEX},
		module = vert_sm,
		pName  = "main",
	}

	fragShaderStageInfo := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = vk.ShaderStageFlags{.FRAGMENT},
		module = frag_sm,
		pName  = "main",
	}

	shader_stages := [?]vk.PipelineShaderStageCreateInfo{vertShaderStageInfo, fragShaderStageInfo}
	vertex_input_info: vk.PipelineVertexInputStateCreateInfo
	vertex_input_info.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO

	binding_desc: vk.VertexInputBindingDescription

	attributeDescriptions := make([]vk.VertexInputAttributeDescription, 11, vi.ArenaAllocator)
	defer delete_slice(attributeDescriptions, vi.ArenaAllocator)

	#partial switch (type) {
	case .GRAPHICS2D:
		{
			binding_desc = V_GetVertex2DBindingDescription()
			attributeDescriptions[0].binding = 0
			attributeDescriptions[0].location = 0
			attributeDescriptions[0].format = .R32G32_SFLOAT
			attributeDescriptions[0].offset = 0

			attributeDescriptions[1].binding = 0
			attributeDescriptions[1].location = 1
			attributeDescriptions[1].format = .R32G32_SFLOAT
			attributeDescriptions[1].offset = size_of(glsl.vec2)

			attributeDescriptions[2].binding = 0
			attributeDescriptions[2].location = 2
			attributeDescriptions[2].format = .R32G32B32A32_SFLOAT
			attributeDescriptions[2].offset = 2 * size_of(glsl.vec2)

			attributeDescriptions[3].binding = 0
			attributeDescriptions[3].location = 3
			attributeDescriptions[3].format = .R32G32B32A32_SFLOAT
			attributeDescriptions[3].offset = 2 * size_of(glsl.vec2) + size_of(glsl.vec4)

			attributeDescriptions[4].binding = 0
			attributeDescriptions[4].location = 4
			attributeDescriptions[4].format = .R32G32B32A32_SFLOAT
			attributeDescriptions[4].offset = 2 * size_of(glsl.vec2) + 2 * size_of(glsl.vec4)

			attributeDescriptions[5].binding = 0
			attributeDescriptions[5].location = 5
			attributeDescriptions[5].format = .R32G32B32A32_SFLOAT
			attributeDescriptions[5].offset = 2 * size_of(glsl.vec2) + 3 * size_of(glsl.vec4)

			attributeDescriptions[6].binding = 0
			attributeDescriptions[6].location = 6
			attributeDescriptions[6].format = .R32G32_SFLOAT
			attributeDescriptions[6].offset = 4 * size_of(glsl.vec4) + 2 * size_of(glsl.vec2)

			attributeDescriptions[7].binding = 0
			attributeDescriptions[7].location = 7
			attributeDescriptions[7].format = .R32G32_SFLOAT
			attributeDescriptions[7].offset = 4 * size_of(glsl.vec4) + 3 * size_of(glsl.vec2)

			attributeDescriptions[8].binding = 0
			attributeDescriptions[8].location = 8
			attributeDescriptions[8].format = .R32_SFLOAT
			attributeDescriptions[8].offset = 4 * size_of(glsl.vec4) + 4 * size_of(glsl.vec2)

			attributeDescriptions[9].binding = 0
			attributeDescriptions[9].location = 9
			attributeDescriptions[9].format = .R32_SFLOAT
			attributeDescriptions[9].offset =
				4 * size_of(glsl.vec4) + 4 * size_of(glsl.vec2) + size_of(f32)

			attributeDescriptions[10].binding = 0
			attributeDescriptions[10].location = 10
			attributeDescriptions[10].format = .R32_SFLOAT
			attributeDescriptions[10].offset =
				4 * size_of(glsl.vec4) + 4 * size_of(glsl.vec2) + 2 * size_of(f32)

			vertex_input_info.vertexBindingDescriptionCount = 1
			vertex_input_info.vertexAttributeDescriptionCount = 11
			vertex_input_info.pVertexAttributeDescriptions = raw_data(attributeDescriptions)
			vertex_input_info.pVertexBindingDescriptions = &binding_desc
		};break
	case .GRAPHICS3D:
		{
			binding_desc = V_GetVertex3DBindingDescription()
			attributeDescriptions[0].binding = 0
			attributeDescriptions[0].location = 0
			attributeDescriptions[0].format = .R32G32B32_SFLOAT
			attributeDescriptions[0].offset = 0

			attributeDescriptions[1].binding = 0
			attributeDescriptions[1].location = 1
			attributeDescriptions[1].format = .R32G32B32_SFLOAT
			attributeDescriptions[1].offset = size_of(glsl.vec3)

			attributeDescriptions[2].binding = 0
			attributeDescriptions[2].location = 2
			attributeDescriptions[2].format = .R32G32_SFLOAT
			attributeDescriptions[2].offset = 2 * size_of(glsl.vec3)

			vertex_input_info.vertexBindingDescriptionCount = 1
			vertex_input_info.vertexAttributeDescriptionCount = 3
			vertex_input_info.pVertexAttributeDescriptions = raw_data(attributeDescriptions)
			vertex_input_info.pVertexBindingDescriptions = &binding_desc
		};break
	}

	inputAssembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	viewportState := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		lineWidth               = 1,
		cullMode                = vk.CullModeFlags{.BACK},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable  = false,
		rasterizationSamples = vk.SampleCountFlags{._1},
	}

	colorBlendAttachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask      = vk.ColorComponentFlags{.R, .G, .B, .A},
		blendEnable         = true,
		colorBlendOp        = .ADD,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		alphaBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
		dstAlphaBlendFactor = .ZERO,
	}

	colorBlending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &colorBlendAttachment,
		blendConstants  = {0, 0, 0, 0},
	}

	dynamicStates := [?]vk.DynamicState{.VIEWPORT, .SCISSOR}

	depthStencil: vk.PipelineDepthStencilStateCreateInfo
	if (type == PipelineType.GRAPHICS3D) {
		depthStencil.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
		depthStencil.depthTestEnable = true
		depthStencil.depthWriteEnable = true
		depthStencil.depthCompareOp = .LESS
		depthStencil.depthBoundsTestEnable = false
		depthStencil.stencilTestEnable = false
	} else if (type == PipelineType.GRAPHICS2D) {
		depthStencil.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
		depthStencil.depthTestEnable = false
		depthStencil.depthWriteEnable = false
		depthStencil.depthCompareOp = .LESS
		depthStencil.depthBoundsTestEnable = false
		depthStencil.stencilTestEnable = false
	}

	dynamicState := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamicStates[:]),
	}

	pipelineLayoutInfo := vk.PipelineLayoutCreateInfo {
		sType          = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts    = &vi.va_Descriptors[len(vi.va_Descriptors) - 1].d_DescriptorSetLayout,
	}
	if (vk.CreatePipelineLayout(
			   vi.va_Device.d_LogicalDevice,
			   &pipelineLayoutInfo,
			   nil,
			   &(pipeline.p_PipelineLayout),
		   ) !=
		   .SUCCESS) {
		panic("[ERROR] Failed to create pipeline layout\n")
	}

	pipelineInfo: vk.GraphicsPipelineCreateInfo
	pipelineInfo.sType = .GRAPHICS_PIPELINE_CREATE_INFO
	pipelineInfo.stageCount = 2
	pipelineInfo.pStages = raw_data(shader_stages[:])
	pipelineInfo.pVertexInputState = &vertex_input_info
	pipelineInfo.pInputAssemblyState = &inputAssembly
	pipelineInfo.pViewportState = &viewportState
	pipelineInfo.pRasterizationState = &rasterizer
	pipelineInfo.pMultisampleState = &multisampling
	pipelineInfo.pColorBlendState = &colorBlending
	pipelineInfo.pDynamicState = &dynamicState
	pipelineInfo.layout = pipeline.p_PipelineLayout
	pipelineInfo.renderPass = vi.va_RenderPass[0]
	pipelineInfo.subpass = 0
	//pipelineInfo.basePipelineHandle  = VK_NULL_HANDLE;
	//pipelineInfo.pDepthStencilState  = &depthStencil;
	pipelineInfo.pDepthStencilState = &depthStencil

	if (vk.CreateGraphicsPipelines(
			   vi.va_Device.d_LogicalDevice,
			   0,
			   1,
			   &pipelineInfo,
			   nil,
			   &(pipeline.p_Pipeline),
		   ) !=
		   .SUCCESS) {
		panic("[ERROR] Failed to create graphics pipeline\n")
	}
}

// -----------------------------------------------------------------------------

create_frame_buffer :: proc(vi: ^VulkanIface) {
	if vi.va_SwapChain.sc_Framebuffers == nil {
		vi.va_SwapChain.sc_Framebuffers = make(
			[dynamic]vk.Framebuffer,
			len(vi.va_SwapChain.sc_ImageViews),
			vi.ArenaAllocator,
		)
	} else {
		resize(&vi.va_SwapChain.sc_Framebuffers, len(vi.va_SwapChain.sc_ImageViews))
	}

	for i in 0 ..< len(vi.va_SwapChain.sc_Framebuffers) {
		attachments := [?]vk.ImageView {
			vi.va_SwapChain.sc_ImageViews[i],
			vi.va_DepthImage.vi_ImageView,
		}

		framebufferInfo: vk.FramebufferCreateInfo
		framebufferInfo.sType = .FRAMEBUFFER_CREATE_INFO
		framebufferInfo.renderPass = vi.va_RenderPass[0]
		framebufferInfo.attachmentCount = 2
		framebufferInfo.pAttachments = raw_data(attachments[:])
		framebufferInfo.width = vi.va_SwapChain.sc_Extent.width
		framebufferInfo.height = vi.va_SwapChain.sc_Extent.height
		framebufferInfo.layers = 1

		if (vk.CreateFramebuffer(
				   vi.va_Device.d_LogicalDevice,
				   &framebufferInfo,
				   nil,
				   &(vi.va_SwapChain.sc_Framebuffers[i]),
			   ) !=
			   .SUCCESS) {
			panic("[ERROR] Failed to create framebuffer\n")
		}
	}
}

// -----------------------------------------------------------------------------

find_memory_type :: proc(
	physical_device: vk.PhysicalDevice,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_properties)
	// fmt.println(mem_properties);
	// fmt.println(type_filter);
	// fmt.println(properties);

	for i: u32 = 0; i < mem_properties.memoryTypeCount; i += 1 {
		prop_found: bool
		type_found: bool

		if (properties & mem_properties.memoryTypes[i].propertyFlags == properties) {
			prop_found = true
		}


		if (type_filter & (1 << i)) > 0 {
			type_found = true
		}

		if prop_found && type_found do return i
	}

	panic("failed to find suitable memory type")
}
// -----------------------------------------------------------------------------

create_buffer :: proc(vi: ^VulkanIface, buffer: ^VulkanBuffer, loc := #caller_location) {
	bufferInfo := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = buffer.vb_Size,
		usage       = buffer.vb_UsageFlags,
		sharingMode = .EXCLUSIVE,
	}

	if (vk.CreateBuffer(vi.va_Device.d_LogicalDevice, &bufferInfo, nil, &buffer.vb_Buffer) !=
		   .SUCCESS) {
		panic("[ERROR] Failed to create buffer\n")
	}

	memRequirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(
		vi.va_Device.d_LogicalDevice,
		buffer.vb_Buffer,
		&memRequirements,
	)

	allocInfo: vk.MemoryAllocateInfo
	allocInfo.sType = .MEMORY_ALLOCATE_INFO
	allocInfo.allocationSize = memRequirements.size
	allocInfo.memoryTypeIndex = find_memory_type(
		vi.va_Device.d_PhysicalDevice,
		memRequirements.memoryTypeBits,
		buffer.vb_Properties,
	)

	if (vk.AllocateMemory(
			   vi.va_Device.d_LogicalDevice,
			   &allocInfo,
			   nil,
			   &buffer.vb_DeviceMemory,
		   ) !=
		   .SUCCESS) {
		fmt.println(loc)
		fmt.println(#procedure, "called by", loc.procedure)
		panic("[ERROR] Failed to allocate buffer memory\n")
	}

	vk.BindBufferMemory(vi.va_Device.d_LogicalDevice, buffer.vb_Buffer, buffer.vb_DeviceMemory, 0)
}

// -----------------------------------------------------------------------------

begin_single_time_commands :: proc(vi: ^VulkanIface) -> vk.CommandBuffer {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = vi.va_CommandPool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
	vk.AllocateCommandBuffers(vi.va_Device.d_LogicalDevice, &alloc_info, &command_buffer)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = vk.CommandBufferUsageFlags{.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(command_buffer, &begin_info)

	return command_buffer
}

// -----------------------------------------------------------------------------

end_single_time_commands :: proc(vi: ^VulkanIface, buffer: ^vk.CommandBuffer) {
	vk.EndCommandBuffer(buffer^)
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = buffer,
	}

	vk.QueueSubmit(vi.va_Device.d_GraphicsQueue, 1, &submit_info, auto_cast 0)
	vk.QueueWaitIdle(vi.va_Device.d_GraphicsQueue)

	vk.FreeCommandBuffers(vi.va_Device.d_LogicalDevice, vi.va_CommandPool, 1, buffer)
}

// -----------------------------------------------------------------------------

copy_buffer :: proc(vi: ^VulkanIface, src: vk.Buffer, dest: vk.Buffer, d_size: vk.DeviceSize) {
	command_buffer := begin_single_time_commands(vi)
	copy_region := vk.BufferCopy {
		size = d_size,
	}
	vk.CmdCopyBuffer(command_buffer, src, dest, 1, &copy_region)

	end_single_time_commands(vi, &command_buffer)
}

// -----------------------------------------------------------------------------
// if batch instanced, we only store the indices the first time. Next time its called,
// the indices will be not used
add_batch2D_instanced_to_group :: proc(vi: ^VulkanIface, batch: ^Batch2D) {
	//tracy.ZoneS(depth = 10)
	//context.allocator = vi.ArenaAllocator

	n_batches: int = cast(int)vi.va_2DBufferBatch.n_batches
	if n_batches <= 0 {
		vi.va_2DBufferBatch.n_batches = 0
		if vi.va_2DBufferBatch.bb_2DBatches == nil {
			vi.va_2DBufferBatch.bb_2DBatches = make([dynamic]Batch2D, 1, vi.ArenaAllocator)
		}
	}
	//else if vi.va_2DBufferBatch.current_batch_idx == auto_cast n_batches
	//{
	//	err := resize(&vi.va_2DBufferBatch.bb_2DBatches, n_batches);
	//	CHECK_MEM_ERROR(err);
	//}
	idx_batch := vi.va_2DBufferBatch.current_batch_idx
	batch.vertices.allocator = vi.ArenaAllocator
	batch.indices.allocator = vi.ArenaAllocator
	batch.n_instances.allocator = vi.ArenaAllocator

	total_vertex_size := len(batch.vertices) * size_of(Vertex2D)
	for batch_it in vi.va_2DBufferBatch.bb_2DBatches {
		total_vertex_size += len(batch_it.vertices) * size_of(Vertex2D)
	}

	if total_vertex_size > MAX_BUFFER_2D_SIZE_BYTES {
		end_batch2D_instance_group(vi)
		idx_batch = vi.va_2DBufferBatch.current_batch_idx
	}

	if idx_batch == auto_cast len(vi.va_2DBufferBatch.bb_2DBatches) {
		append(&vi.va_2DBufferBatch.bb_2DBatches, Batch2D{})
	}

	for v in batch.vertices {
		append(&vi.va_2DBufferBatch.bb_2DBatches[idx_batch].vertices, v)
	}
	if (len(vi.va_2DBufferBatch.bb_2DBatches[idx_batch].indices) == 0) {
		for i in batch.indices {
			append(&vi.va_2DBufferBatch.bb_2DBatches[idx_batch].indices, i)
		}
	}
	for ins in batch.n_instances {
		append(&vi.va_2DBufferBatch.bb_2DBatches[idx_batch].n_instances, ins)
	}

	//fmt.println("[INFO] Current batches: ", idx_batch + 1 );
}

// -----------------------------------------------------------------------------

end_batch2D_instance_group :: proc(vi: ^VulkanIface) {
	//tracy.ZoneS(depth = 10)
	n_batches: int = auto_cast vi.va_2DBufferBatch.n_batches
	//if n_batches <= 0 {
	//fmt.println("[ERROR] no previous batch where added before calling this function");
	//return;
	//}
	idx_batch := vi.va_2DBufferBatch.current_batch_idx
	vertices := vi.va_2DBufferBatch.bb_2DBatches[idx_batch].vertices
	indices := vi.va_2DBufferBatch.bb_2DBatches[idx_batch].indices
	//instances := vi.va_2DBufferBatch.bb_2DBatches[idx_batch].n_instances;

	if auto_cast idx_batch >= len(vi.va_2DBufferBatch.bb_VertexBuffer) {
		vi.va_2DBufferBatch.n_batches += 1
		v_buffer: VulkanBuffer
		i_buffer: VulkanBuffer
		create_vertex_2D_buffer(vi, &v_buffer, &i_buffer, vertices, indices)
		v_buffer.vb_toDestroy = false
		i_buffer.vb_toDestroy = false

		vi.va_2DBufferBatch.bb_VertexBuffer.allocator = vi.ArenaAllocator
		vi.va_2DBufferBatch.bb_IndexBuffer.allocator = vi.ArenaAllocator
		append(&vi.va_2DBufferBatch.bb_VertexBuffer, v_buffer)
		append(&vi.va_2DBufferBatch.bb_IndexBuffer, i_buffer)
		fmt.println("[INFO] Vertex Batches   :", vi.va_2DBufferBatch.n_batches)
		fmt.println("[INFO] Vertex batch idx :", idx_batch)
		fmt.println("[INFO] Batch size       :", size_of(Vertex2D) * len(vertices))
	} else {
		buffer_size: vk.DeviceSize = auto_cast (size_of(Vertex2D) * len(vertices))
		idx_buffer_size: vk.DeviceSize = auto_cast (size_of(u32) * len(indices))
		v_buffer := &vi.va_2DBufferBatch.bb_VertexBuffer[idx_batch]
		i_buffer := &vi.va_2DBufferBatch.bb_IndexBuffer[idx_batch]
		if v_buffer.vb_toDestroy {
			v_buffer.vb_toDestroy = false
			i_buffer.vb_toDestroy = false
			vt_buffer: VulkanBuffer
			id_buffer: VulkanBuffer
			fmt.println("[INFO] Recreating buffer after destruction")
			create_vertex_2D_buffer(
				vi,
				&vt_buffer,
				&id_buffer,
				vertices,
				indices,
				auto_cast v_buffer.vb_Size,
			)

			vi.va_2DBufferBatch.bb_VertexBuffer.allocator = vi.ArenaAllocator
			vi.va_2DBufferBatch.bb_IndexBuffer.allocator = vi.ArenaAllocator

			mem.copy(v_buffer, &vt_buffer, cast(int)buffer_size)
			mem.copy(i_buffer, &id_buffer, cast(int)buffer_size)
		} else if (buffer_size > v_buffer.vb_MaxSize) {

			fmt.println("[INFO] Resizing for buffer idx:", idx_batch)
			fmt.println(
				"[INFO] Resizing buffer to size:",
				cast(int)buffer_size + MAX_BUFFER_2D_SIZE_BYTES,
			)
			fmt.println("[INFO] Previous size was      :", cast(int)v_buffer.vb_Size)
			fmt.println("[INFO] Current batch size is  :", cast(int)buffer_size)
			vk.DestroyBuffer(vi.va_Device.d_LogicalDevice, v_buffer.vb_Buffer, nil)
			vk.FreeMemory(vi.va_Device.d_LogicalDevice, v_buffer.vb_DeviceMemory, nil)
			vk.DestroyBuffer(vi.va_Device.d_LogicalDevice, i_buffer.vb_Buffer, nil)
			vk.FreeMemory(vi.va_Device.d_LogicalDevice, i_buffer.vb_DeviceMemory, nil)

			vt_buffer: VulkanBuffer
			id_buffer: VulkanBuffer
			create_vertex_2D_buffer(
				vi,
				v_buffer,
				i_buffer,
				vertices,
				indices,
				cast(int)buffer_size + MAX_BUFFER_2D_SIZE_BYTES,
			)

			fmt.println("[INFO] New size is: ", v_buffer.vb_Size)

			vi.va_2DBufferBatch.bb_VertexBuffer.allocator = vi.ArenaAllocator
			vi.va_2DBufferBatch.bb_IndexBuffer.allocator = vi.ArenaAllocator
		} else {
			// TODO: This staging buffer can perfectly be inside the vulkan state struct, not making it be created
			// every time, so it should be less stressful to the gpu, in particular, with low-end gpu
			//
			staging_buffer: VulkanBuffer
			staging_buffer.vb_Size = buffer_size
			staging_buffer.vb_UsageFlags = vk.BufferUsageFlags{.TRANSFER_SRC}
			staging_buffer.vb_Properties = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_COHERENT}

			create_buffer(vi, &staging_buffer)

			memory_map_flag: vk.MemoryMapFlags

			data: rawptr
			vk.MapMemory(
				vi.va_Device.d_LogicalDevice,
				staging_buffer.vb_DeviceMemory,
				0,
				buffer_size,
				memory_map_flag,
				&data,
			)
			mem.copy(data, raw_data(vertices), auto_cast buffer_size)
			vk.UnmapMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory)

			copy_buffer(vi, staging_buffer.vb_Buffer, v_buffer.vb_Buffer, buffer_size)
			v_buffer.vb_Size = buffer_size

			vk.MapMemory(
				vi.va_Device.d_LogicalDevice,
				staging_buffer.vb_DeviceMemory,
				0,
				idx_buffer_size,
				memory_map_flag,
				&data,
			)
			mem.copy(data, raw_data(indices), auto_cast idx_buffer_size)
			vk.UnmapMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory)

			copy_buffer(vi, staging_buffer.vb_Buffer, i_buffer.vb_Buffer, idx_buffer_size)
			i_buffer.vb_Size = idx_buffer_size

			vk.DestroyBuffer(vi.va_Device.d_LogicalDevice, staging_buffer.vb_Buffer, nil)
			vk.FreeMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory, nil)
		}
	}
	vi.va_2DBufferBatch.current_batch_idx += 1
}

// -----------------------------------------------------------------------------

create_vertex_2D_buffer :: proc(
	vi: ^VulkanIface,
	v_buffer: ^VulkanBuffer,
	i_buffer: ^VulkanBuffer,
	vertices: [dynamic]Vertex2D,
	indices: [dynamic]u32,
	size := MAX_BUFFER_2D_SIZE_BYTES,
	loc := #caller_location,
) {
	debug_time_add_scope("vk buffer creation", vi.ArenaAllocator)
	{
		buffer_size: vk.DeviceSize = auto_cast size
		vertex_size := size_of(Vertex2D) * len(vertices)
		staging_buffer: VulkanBuffer
		staging_buffer.vb_Size = auto_cast vertex_size
		staging_buffer.vb_UsageFlags = vk.BufferUsageFlags{.TRANSFER_SRC}
		staging_buffer.vb_Properties = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_COHERENT}

		create_buffer(vi, &staging_buffer)

		memory_map_flag: vk.MemoryMapFlags

		data: rawptr
		vk.MapMemory(
			vi.va_Device.d_LogicalDevice,
			staging_buffer.vb_DeviceMemory,
			0,
			auto_cast vertex_size,
			memory_map_flag,
			&data,
		)
		mem.copy(data, raw_data(vertices), auto_cast vertex_size)
		vk.UnmapMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory)

		v_buffer.vb_Size = buffer_size
		v_buffer.vb_MaxSize = buffer_size
		v_buffer.vb_Properties = vk.MemoryPropertyFlags{.DEVICE_LOCAL}
		v_buffer.vb_UsageFlags = vk.BufferUsageFlags{.TRANSFER_DST, .VERTEX_BUFFER}

		create_buffer(vi, v_buffer, loc)
		copy_buffer(vi, staging_buffer.vb_Buffer, v_buffer.vb_Buffer, auto_cast vertex_size)

		vk.DestroyBuffer(vi.va_Device.d_LogicalDevice, staging_buffer.vb_Buffer, nil)
		vk.FreeMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory, nil)
	}
	// Index buffer creation
	//
	{
		buffer_size: vk.DeviceSize = auto_cast size
		idx_size := size_of(u32) * len(indices)
		staging_buffer: VulkanBuffer
		staging_buffer.vb_Size = auto_cast idx_size
		staging_buffer.vb_UsageFlags = vk.BufferUsageFlags{.TRANSFER_SRC}
		staging_buffer.vb_Properties = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_COHERENT}

		create_buffer(vi, &staging_buffer)

		memory_map_flag: vk.MemoryMapFlags
		data: rawptr
		vk.MapMemory(
			vi.va_Device.d_LogicalDevice,
			staging_buffer.vb_DeviceMemory,
			0,
			auto_cast idx_size,
			memory_map_flag,
			&data,
		)
		mem.copy(data, raw_data(indices), auto_cast idx_size)
		vk.UnmapMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory)

		i_buffer.vb_Size = buffer_size
		i_buffer.vb_MaxSize = buffer_size
		i_buffer.vb_Properties = vk.MemoryPropertyFlags{.DEVICE_LOCAL}
		i_buffer.vb_UsageFlags = vk.BufferUsageFlags{.TRANSFER_DST, .INDEX_BUFFER}

		create_buffer(vi, i_buffer)
		copy_buffer(vi, staging_buffer.vb_Buffer, i_buffer.vb_Buffer, auto_cast idx_size)

		vk.DestroyBuffer(vi.va_Device.d_LogicalDevice, staging_buffer.vb_Buffer, nil)
		vk.FreeMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory, nil)
	}
}

// -----------------------------------------------------------------------------

copy_buffer_to_image :: proc(vi: ^VulkanIface, old_buffer: ^vk.Buffer, new_img: ^VulkanImage) {
	command_buffer := begin_single_time_commands(vi)
	defer end_single_time_commands(vi, &command_buffer)

	region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {
			aspectMask = vk.ImageAspectFlags{.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = {0, 0, 0},
		imageExtent = {width = new_img.vi_width, height = new_img.vi_height, depth = 1},
	}

	vk.CmdCopyBufferToImage(
		command_buffer,
		old_buffer^,
		new_img.vi_Image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&region,
	)
}

// -----------------------------------------------------------------------------

transition_image_layout :: proc(vi: ^VulkanIface, old_img, new_img: ^VulkanImage) {
	command_buffer := begin_single_time_commands(vi)
	defer end_single_time_commands(vi, &command_buffer)

	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = old_img.vi_Layout,
		newLayout = new_img.vi_Layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = new_img.vi_Image,
		subresourceRange = {
			aspectMask = vk.ImageAspectFlags{.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	source_stage: vk.PipelineStageFlags
	destination_stage: vk.PipelineStageFlags

	indirec_command_access_flag: vk.AccessFlags
	if (old_img.vi_Layout == .UNDEFINED && new_img.vi_Layout == .TRANSFER_DST_OPTIMAL) {
		barrier.srcAccessMask = nil
		barrier.dstAccessMask = vk.AccessFlags{.TRANSFER_WRITE}
		source_stage = vk.PipelineStageFlags{.TOP_OF_PIPE}
		destination_stage = vk.PipelineStageFlags{.TRANSFER}
	} else if (old_img.vi_Layout == .TRANSFER_DST_OPTIMAL &&
		   new_img.vi_Layout == .SHADER_READ_ONLY_OPTIMAL) {
		barrier.srcAccessMask = vk.AccessFlags{.TRANSFER_WRITE}
		barrier.dstAccessMask = vk.AccessFlags{.SHADER_READ}

		source_stage = vk.PipelineStageFlags{.TRANSFER}
		destination_stage = vk.PipelineStageFlags{.FRAGMENT_SHADER}
	} else {
		panic("[ERROR] Unsupported layout transition")
	}

	dependency_flag: vk.DependencyFlags //{ .BY_REGION };
	vk.CmdPipelineBarrier(
		command_buffer,
		source_stage,
		destination_stage,
		nil,
		0,
		nil,
		0,
		nil,
		1,
		&barrier,
	)
}

// -----------------------------------------------------------------------------

add_texture_font :: proc(vi: ^VulkanIface, font: ^[dynamic]FontCache) {
	if vi.bitmap.bitmap == nil {
		fmt.println("[ERROR] Bitmap array font was nil")
	}
	//tex_width   := font.BitmapWidth;
	//text_height := font.BitmapHeight;
	tex_width := vi.bitmap.width
	text_height := vi.bitmap.height
	image_size: vk.DeviceSize = auto_cast (tex_width * text_height) //rgb

	staging_buffer: VulkanBuffer
	staging_buffer.vb_Size = image_size
	staging_buffer.vb_UsageFlags = vk.BufferUsageFlags{.TRANSFER_SRC}
	staging_buffer.vb_Properties = vk.MemoryPropertyFlags{.HOST_VISIBLE, .HOST_COHERENT}

	create_buffer(vi, &staging_buffer)
	data: rawptr
	memory_map_flag: vk.MemoryMapFlags
	vk.MapMemory(
		vi.va_Device.d_LogicalDevice,
		staging_buffer.vb_DeviceMemory,
		0,
		image_size,
		memory_map_flag,
		&data,
	)
	mem.copy(data, raw_data(vi.bitmap.bitmap), auto_cast image_size)
	vk.UnmapMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory)

	vi.va_TextureImage.vi_width = tex_width
	vi.va_TextureImage.vi_height = text_height
	vi.va_TextureImage.vi_Format = .R8_UNORM
	vi.va_TextureImage.vi_Tiling = .OPTIMAL
	vi.va_TextureImage.vi_UsageFlags = vk.ImageUsageFlags{.TRANSFER_DST, .SAMPLED}
	vi.va_TextureImage.vi_Properties = vk.MemoryPropertyFlags{.DEVICE_LOCAL}
	vi.va_TextureImage.vi_Layout = .TRANSFER_DST_OPTIMAL

	create_image(vi, &vi.va_TextureImage)
	old_image: VulkanImage
	old_image.vi_Layout = .UNDEFINED
	transition_image_layout(vi, &old_image, &vi.va_TextureImage)

	copy_buffer_to_image(vi, &staging_buffer.vb_Buffer, &vi.va_TextureImage)

	old_image.vi_Layout = .TRANSFER_DST_OPTIMAL
	vi.va_TextureImage.vi_Layout = .SHADER_READ_ONLY_OPTIMAL

	transition_image_layout(vi, &old_image, &vi.va_TextureImage)

	vk.DestroyBuffer(vi.va_Device.d_LogicalDevice, staging_buffer.vb_Buffer, nil)
	vk.FreeMemory(vi.va_Device.d_LogicalDevice, staging_buffer.vb_DeviceMemory, nil)

	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = vi.va_TextureImage.vi_Image,
		viewType = .D2,
		format = vi.va_TextureImage.vi_Format,
		subresourceRange = {
			aspectMask = vk.ImageAspectFlags{.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	if vk.CreateImageView(
		   vi.va_Device.d_LogicalDevice,
		   &create_info,
		   nil,
		   &vi.va_TextureImage.vi_ImageView,
	   ) !=
	   .SUCCESS {
		panic("[ERROR] Could not create image view")
	}

	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(vi.va_Device.d_PhysicalDevice, &properties)

	samplerInfo := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		addressModeU            = .CLAMP_TO_EDGE,
		addressModeV            = .CLAMP_TO_EDGE,
		addressModeW            = .REPEAT,
		anisotropyEnable        = false,
		maxAnisotropy           = properties.limits.maxSamplerAnisotropy,
		borderColor             = .INT_TRANSPARENT_BLACK,
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = .LINEAR,
	}

	if (vk.CreateSampler(
			   vi.va_Device.d_LogicalDevice,
			   &samplerInfo,
			   nil,
			   &vi.va_TextureImage.vi_Sampler,
		   ) !=
		   .SUCCESS) {
		panic("[ERROR] Failed to create texture sampler")
	}
}

// -----------------------------------------------------------------------------

recreate_swapchain :: proc(vi: ^VulkanIface) {
	width, height := glfw.GetFramebufferSize(vi.va_Window.w_window)
	for width == 0 || height == 0 {
		fmt.println("Cannot be zero, width: ", width, "height: ", height)
		width, height := glfw.GetFramebufferSize(vi.va_Window.w_window)
		glfw.WaitEvents()
	}
	vk.DeviceWaitIdle(vi.va_Device.d_LogicalDevice)

	for frame in vi.va_SwapChain.sc_Framebuffers {
		vk.DestroyFramebuffer(vi.va_Device.d_LogicalDevice, frame, nil)
	}
	for imgview in vi.va_SwapChain.sc_ImageViews {
		vk.DestroyImageView(vi.va_Device.d_LogicalDevice, imgview, nil)
	}

	vk.DestroyImageView(vi.va_Device.d_LogicalDevice, vi.va_DepthImage.vi_ImageView, nil)
	vk.DestroyImage(vi.va_Device.d_LogicalDevice, vi.va_DepthImage.vi_Image, nil)
	vk.FreeMemory(vi.va_Device.d_LogicalDevice, vi.va_DepthImage.vi_DeviceMemory, nil)

	vk.DestroySwapchainKHR(vi.va_Device.d_LogicalDevice, vi.va_SwapChain.sc_SwapChainHandle, nil)

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(
			vi.va_Device.d_LogicalDevice,
			vi.va_Semaphores.s_RenderFinished[i],
			nil,
		)
		vk.DestroySemaphore(
			vi.va_Device.d_LogicalDevice,
			vi.va_Semaphores.s_ImageAvailable[i],
			nil,
		)
		vk.DestroyFence(vi.va_Device.d_LogicalDevice, vi.va_Semaphores.s_InFlight[i], nil)
	}

	create_swap_chain(vi)
	create_image_views(vi)
	create_depth_resources(vi)
	create_frame_buffer(vi)
	create_semaphores(vi)
}

// -----------------------------------------------------------------------------

init_glfw :: proc(vi: ^VulkanIface) {

	//bitmap := make([^]u8, 920 * 920);
	//font_cache := f_BuildFont(18, 920, 920, bitmap );
	//glfw.SetErrorCallback(error_callback)

	if !glfw.Init() {
		panic("EXIT_FAILURE")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	//glfw.WindowHint(glfw.DECORATED, false)
	glfw.WindowHint(glfw.AUTO_ICONIFY, false)

	vi.va_Window.w_width = 1920
	vi.va_Window.w_height = 1080
	vi.va_Window.w_window = glfw.CreateWindow(
		vi.va_Window.w_width,
		vi.va_Window.w_height,
		"OrbitMCS",
		nil,
		nil,
	)
	if vi.va_Window.w_window == nil {
		panic("EXIT_FAILURE")
	}

	glfw.SetWindowUserPointer(vi.va_Window.w_window, vi)
	//glfw.SetInputMode(vi.va_Window.w_window, glfw.STICKY_KEYS, 1 );
	glfw.SetKeyCallback(vi.va_Window.w_window, key_callback)
	glfw.SetFramebufferSizeCallback(vi.va_Window.w_window, framebuffer_resize_callback)
	glfw.SetMouseButtonCallback(vi.va_Window.w_window, mouse_button_callback)
	glfw.SetCharCallback(vi.va_Window.w_window, character_callback)
	glfw.SetScrollCallback(vi.va_Window.w_window, mouse_scroll_callback)
	glfw.SetWindowFocusCallback(vi.va_Window.w_window, windows_focus_callback)
	glfw.MakeContextCurrent(vi.va_Window.w_window)
	glfw.WindowHint(glfw.TRANSPARENT_FRAMEBUFFER, true)
	glfw.WindowHint(glfw.DECORATED, false)

	monitors_handle := glfw.GetMonitors()
	vi.va_Window.scaling_factor.x, vi.va_Window.scaling_factor.y = glfw.GetMonitorContentScale(
		monitors_handle[0],
	)
	//glfw.SetWindowOpacity(vi.va_Window.w_window, 0.8)

	vi.glfw_timer = time.tick_now()
}

// -----------------------------------------------------------------------------

render_pass :: proc(
	vi: ^VulkanIface,
	command_buffer: vk.CommandBuffer,
	pipeline: Pipeline,
	descriptor: ^DescriptorSet,
) {
	//tracy.ZoneS(depth = 10)
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, pipeline.p_Pipeline)
	view_port := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = cast(f32)vi.va_SwapChain.sc_Extent.width,
		height   = cast(f32)vi.va_SwapChain.sc_Extent.height,
		minDepth = 0,
		maxDepth = 1,
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &view_port)

	scissor := vk.Rect2D {
		offset = {0, 0},
		extent = vi.va_SwapChain.sc_Extent,
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	for i: u32 = 0; i < vi.va_2DBufferBatch.n_batches; i = i + 1 {
		vertex_buffers := [?]vk.Buffer{vi.va_2DBufferBatch.bb_VertexBuffer[i].vb_Buffer}
		offsets := [?]vk.DeviceSize{0}
		vk.CmdBindVertexBuffers(
			command_buffer,
			0,
			1,
			raw_data(vertex_buffers[:]),
			raw_data(offsets[:]),
		)

		vk.CmdBindIndexBuffer(
			command_buffer,
			vi.va_2DBufferBatch.bb_IndexBuffer[i].vb_Buffer,
			0,
			.UINT32,
		)

		vk.CmdBindDescriptorSets(
			command_buffer,
			.GRAPHICS,
			pipeline.p_PipelineLayout,
			0,
			1,
			&descriptor.d_DescriptorSet[vi.va_CurrentFrame],
			0,
			nil,
		)

		vk.CmdDrawIndexed(
			command_buffer,
			auto_cast len(vi.va_2DBufferBatch.bb_2DBatches[i].indices),
			math.sum(vi.va_2DBufferBatch.bb_2DBatches[i].n_instances[:]),
			0,
			0,
			0,
		)
	}
}

// -----------------------------------------------------------------------------

update_descriptor_sets :: proc(v_interface: ^VulkanIface) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		bufferInfo: vk.DescriptorBufferInfo
		bufferInfo.buffer = v_interface.va_UniformBufferUI[i].vb_Buffer
		bufferInfo.offset = 0
		bufferInfo.range = size_of(UniformBufferUI)

		bufferInfo3D: vk.DescriptorBufferInfo
		bufferInfo3D.buffer = v_interface.va_UniformBuffer3D[i].vb_Buffer
		bufferInfo3D.offset = 0
		bufferInfo3D.range = size_of(UniformBuffer3D)

		imageInfo: vk.DescriptorImageInfo
		imageInfo.imageLayout = .SHADER_READ_ONLY_OPTIMAL
		imageInfo.imageView = v_interface.va_TextureImage.vi_ImageView
		imageInfo.sampler = v_interface.va_TextureImage.vi_Sampler

		descriptorWrites := make([]vk.WriteDescriptorSet, 3)
		defer delete_slice(descriptorWrites)

		descriptor_set := v_interface.va_Descriptors[0].d_DescriptorSet[i]

		descriptorWrites[0].sType = .WRITE_DESCRIPTOR_SET
		descriptorWrites[0].dstSet = descriptor_set
		descriptorWrites[0].dstBinding = 0
		descriptorWrites[0].dstArrayElement = 0
		descriptorWrites[0].descriptorType = .UNIFORM_BUFFER
		descriptorWrites[0].descriptorCount = 1
		descriptorWrites[0].pBufferInfo = &bufferInfo
		descriptorWrites[0].pNext = nil
		descriptorWrites[0].pTexelBufferView = nil

		descriptorWrites[1].sType = .WRITE_DESCRIPTOR_SET
		descriptorWrites[1].dstSet = descriptor_set
		descriptorWrites[1].dstBinding = 1
		descriptorWrites[1].dstArrayElement = 0
		descriptorWrites[1].descriptorType = .UNIFORM_BUFFER
		descriptorWrites[1].descriptorCount = 1
		descriptorWrites[1].pBufferInfo = &bufferInfo3D
		descriptorWrites[1].pNext = nil
		descriptorWrites[1].pTexelBufferView = nil

		descriptorWrites[2].sType = .WRITE_DESCRIPTOR_SET
		descriptorWrites[2].dstSet = descriptor_set
		descriptorWrites[2].dstBinding = 2
		descriptorWrites[2].dstArrayElement = 0
		descriptorWrites[2].descriptorType = .COMBINED_IMAGE_SAMPLER
		descriptorWrites[2].descriptorCount = 1
		descriptorWrites[2].pImageInfo = &imageInfo
		descriptorWrites[2].pNext = nil
		descriptorWrites[2].pTexelBufferView = nil

		vk.UpdateDescriptorSets(
			v_interface.va_Device.d_LogicalDevice,
			3,
			raw_data(descriptorWrites),
			0,
			nil,
		)
	}
}

// -----------------------------------------------------------------------------

update_uniform_buffer :: proc(vi: ^VulkanIface) {
	//vi.va_CurrentUB_UI.time        = cast(f32)vi.glfw_timer
	vi.va_CurrentUB_UI.width = cast(f32)vi.va_SwapChain.sc_Extent.width
	vi.va_CurrentUB_UI.height = cast(f32)vi.va_SwapChain.sc_Extent.height
	vi.va_CurrentUB_UI.AtlasWidth = cast(f32)vi.bitmap.width
	vi.va_CurrentUB_UI.AtlasHeight = cast(f32)vi.bitmap.height

	mem.copy(
		vi.va_UniformBufferUI[vi.va_CurrentFrame].vb_MappedMemory,
		&vi.va_CurrentUB_UI,
		size_of(UniformBufferUI),
	)
}

// -----------------------------------------------------------------------------

destroy_render_batch :: proc(vi: ^VulkanIface, frame: u32) {
	debug_time_add_scope("Destroy_Render_Batch", vi.ArenaAllocator)
	//defer debug_time_end(n, t);
	batch := vi.va_2DBufferBatchDestroy[frame]

	for i := 0; i < len(batch.bb_VertexBuffer); i += 1 {
		vk.DestroyBuffer(vi.va_Device.d_LogicalDevice, batch.bb_VertexBuffer[i].vb_Buffer, nil)
		vk.FreeMemory(vi.va_Device.d_LogicalDevice, batch.bb_VertexBuffer[i].vb_DeviceMemory, nil)
	}
	for i := 0; i < len(batch.bb_IndexBuffer); i += 1 {
		vk.DestroyBuffer(vi.va_Device.d_LogicalDevice, batch.bb_IndexBuffer[i].vb_Buffer, nil)
		vk.FreeMemory(vi.va_Device.d_LogicalDevice, batch.bb_IndexBuffer[i].vb_DeviceMemory, nil)
	}

	clear(&vi.va_2DBufferBatchDestroy[frame].bb_VertexBuffer)
	clear(&vi.va_2DBufferBatchDestroy[frame].bb_IndexBuffer)
	/*
	for &batches in vi.va_2DBufferBatchDestroy[frame].bb_2DBatches {
		clear(&batches.vertices);
		clear(&batches.indices);
		clear(&batches.n_instances);
	}
	*/
}

// -----------------------------------------------------------------------------

add_batch_to_destroy :: proc(vi: ^VulkanIface, frame: u32) {
	debug_time_add_scope("Add_Batch_Destroy", vi.ArenaAllocator)
	//defer debug_time_end(n, t);
	//mem.copy(&vi.va_2DBufferBatchDestroy[frame], &vi.va_2DBufferBatch, size_of(BufferBatchGroup));
	//vi.va_2DBufferBatchDestroy[frame].bb_VertexBuffer = vi.va_2DBufferBatch.bb_VertexBuffer;
	//vi.va_2DBufferBatchDestroy[frame].bb_IndexBuffer = vi.va_2DBufferBatch.bb_IndexBuffer;
	n_batches_erase: u32 = 0
	for i: u32 = 0; i < vi.va_2DBufferBatch.n_batches; i += 1 {
		batch := vi.va_2DBufferBatch.bb_2DBatches[i]
		if vi.va_2DBufferBatch.bb_VertexBuffer[i].vb_toDestroy {
			n_batches_erase += 1
			append(
				&vi.va_2DBufferBatchDestroy[frame].bb_VertexBuffer,
				vi.va_2DBufferBatch.bb_VertexBuffer[i],
			)
		}
		//clear(&batch.vertices);
		//clear(&batch.indices);
		//clear(&batch.n_instances);
	}

	for i: u32 = 0; i < vi.va_2DBufferBatch.n_batches; i += 1 {
		if vi.va_2DBufferBatch.bb_IndexBuffer[i].vb_toDestroy {
			append(
				&vi.va_2DBufferBatchDestroy[frame].bb_IndexBuffer,
				vi.va_2DBufferBatch.bb_IndexBuffer[i],
			)
		}
	}

	vi.va_2DBufferBatch.n_batches -= n_batches_erase
	// reset batch idx for next frame iteration
	//
	vi.va_2DBufferBatch.current_batch_idx = 0

	//clear(&vi.va_2DBufferBatch.bb_VertexBuffer);
	//clear(&vi.va_2DBufferBatch.bb_IndexBuffer);
	for &batch in vi.va_2DBufferBatch.bb_2DBatches {
		clear(&batch.vertices)
		clear(&batch.indices)
		clear(&batch.n_instances)
	}
}

// -----------------------------------------------------------------------------
create_semaphores :: proc(vi: ^VulkanIface) {
	semaphoreInfo: vk.SemaphoreCreateInfo
	semaphoreInfo.sType = .SEMAPHORE_CREATE_INFO

	fenceInfo: vk.FenceCreateInfo
	fenceInfo.sType = .FENCE_CREATE_INFO
	fenceInfo.flags = vk.FenceCreateFlags{.SIGNALED}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		if (vk.CreateSemaphore(
				   vi.va_Device.d_LogicalDevice,
				   &semaphoreInfo,
				   nil,
				   &(vi.va_Semaphores.s_ImageAvailable[i]),
			   ) !=
				   .SUCCESS ||
			   vk.CreateSemaphore(
				   vi.va_Device.d_LogicalDevice,
				   &semaphoreInfo,
				   nil,
				   &(vi.va_Semaphores.s_RenderFinished[i]),
			   ) !=
				   .SUCCESS ||
			   vk.CreateFence(
				   vi.va_Device.d_LogicalDevice,
				   &fenceInfo,
				   nil,
				   &(vi.va_Semaphores.s_InFlight[i]),
			   ) !=
				   .SUCCESS) {
			panic("[ERROR] Failed to create synchronization objects for a frame\n")
		}
	}
}

// -----------------------------------------------------------------------------

draw_frame :: proc(vi: ^VulkanIface) {
	//tracy.ZoneS(depth = 10)
	debug_time_add_scope("DrawFrame")
	//defer debug_time_end(n, t);
	vk.WaitForFences(
		vi.va_Device.d_LogicalDevice,
		1,
		&vi.va_Semaphores.s_InFlight[vi.va_CurrentFrame],
		true,
		bits.U64_MAX,
	)
	destroy_render_batch(vi, vi.va_CurrentFrame)

	image_index: u32
	result := vk.AcquireNextImageKHR(
		vi.va_Device.d_LogicalDevice,
		vi.va_SwapChain.sc_SwapChainHandle,
		bits.U64_MAX,
		vi.va_Semaphores.s_ImageAvailable[vi.va_CurrentFrame],
		{},
		&image_index,
	)

	if result == .ERROR_OUT_OF_DATE_KHR {
		add_batch_to_destroy(vi, vi.va_CurrentFrame)
		recreate_swapchain(vi)
		return
	} else if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
		panic("[ERROR] Could not acquire next image")
	}

	update_uniform_buffer(vi)

	vk.ResetFences(
		vi.va_Device.d_LogicalDevice,
		1,
		&vi.va_Semaphores.s_InFlight[vi.va_CurrentFrame],
	)
	vk.ResetCommandBuffer(vi.va_CommandBuffers[vi.va_CurrentFrame], {})

	// ------------------------------------------------------------------------
	// Record command buffer

	command_buffer := vi.va_CommandBuffers[vi.va_CurrentFrame]
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	if vk.BeginCommandBuffer(command_buffer, &begin_info) != .SUCCESS {
		fmt.println("[INFO ERROR] Failed to begin record command buffer")
	}

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = vi.va_RenderPass[0],
		framebuffer = vi.va_SwapChain.sc_Framebuffers[image_index],
		renderArea = {offset = {0, 0}, extent = vi.va_SwapChain.sc_Extent},
	}
	c_val: [4]f32 = rgba_to_norm({2, 2, 2, 256})
	clear_values := [2]vk.ClearValue {
		//0 = {color={float32 = [4]f32{0.7, 0.7, 0.7, 1.0}}},
		//0 = {color={float32 = [4]f32{0.025, 0.025, 0.025, 1.0}}},
		0 = {color = {float32 = c_val}},
		1 = {depthStencil = {1.0, 0}},
	}

	render_pass_info.clearValueCount = len(clear_values)
	render_pass_info.pClearValues = &clear_values[0]

	vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)

	render_pass(vi, command_buffer, vi.va_Pipelines[0], &vi.va_Descriptors[0])

	vk.CmdEndRenderPass(command_buffer)

	if vk.EndCommandBuffer(command_buffer) != .SUCCESS {
		panic("[ERROR] Failed to record command buffer")
	}
	// ------------------------------------------------------------------------

	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
	}
	wait_semaphores := [?]vk.Semaphore{vi.va_Semaphores.s_ImageAvailable[vi.va_CurrentFrame]}
	wait_stages := [?]vk.PipelineStageFlags{vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}}

	submit_info.waitSemaphoreCount = len(wait_semaphores)
	submit_info.pWaitSemaphores = raw_data(wait_semaphores[:])
	submit_info.pWaitDstStageMask = raw_data(wait_stages[:])
	submit_info.commandBufferCount = 1
	submit_info.pCommandBuffers = &vi.va_CommandBuffers[vi.va_CurrentFrame]

	signal_semaphores := [?]vk.Semaphore{vi.va_Semaphores.s_RenderFinished[vi.va_CurrentFrame]}
	submit_info.signalSemaphoreCount = len(signal_semaphores)
	submit_info.pSignalSemaphores = raw_data(signal_semaphores[:])


	add_batch_to_destroy(vi, vi.va_CurrentFrame)
	if vk.QueueSubmit(
		   vi.va_Device.d_GraphicsQueue,
		   1,
		   &submit_info,
		   vi.va_Semaphores.s_InFlight[vi.va_CurrentFrame],
	   ) !=
	   .SUCCESS {
		panic("[ERROR] Failed to submit draw command buffer")
	}

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = len(signal_semaphores),
		pWaitSemaphores    = raw_data(signal_semaphores[:]),
	}

	swapchains := [?]vk.SwapchainKHR{vi.va_SwapChain.sc_SwapChainHandle}
	present_info.swapchainCount = len(swapchains)
	present_info.pSwapchains = raw_data(swapchains[:])
	present_info.pImageIndices = &image_index

	result = vk.QueuePresentKHR(vi.va_Device.d_PresentationQueue, &present_info)
	if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR || vi.va_FramebufferResized {
		vi.va_FramebufferResized = false
		recreate_swapchain(vi)
	} else if result != .SUCCESS {
		panic("[ERROR] Failed to present swapchain image")
	}
	vi.va_CurrentFrame = (vi.va_CurrentFrame + 1) % MAX_FRAMES_IN_FLIGHT
}

// -----------------------------------------------------------------------------

init_vulkan :: proc(v_interface: ^VulkanIface) {

	v_interface.va_CurrentFrame = 0
	//context.allocator = v_interface.ArenaAllocator;

	init_glfw(v_interface)

	context.user_ptr = &v_interface.va_Instance
	get_proc_address :: proc(p: rawptr, name: cstring) {
		(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name)
	}

	vk.load_proc_addresses(get_proc_address)

	v_interface.va_LastTime = glfw.GetTime()

	appInfo: vk.ApplicationInfo
	appInfo.sType = .APPLICATION_INFO
	appInfo.pApplicationName = "OrbitMCS"
	appInfo.applicationVersion = vk.MAKE_VERSION(1, 3, 0)
	appInfo.pEngineName = "No Engine"
	appInfo.engineVersion = vk.MAKE_VERSION(1, 3, 0)
	appInfo.apiVersion = vk.API_VERSION_1_3

	create_info: vk.InstanceCreateInfo
	create_info.sType = .INSTANCE_CREATE_INFO
	create_info.pApplicationInfo = &appInfo

	when ODIN_DEBUG {
		if (!check_validation_layer_support(v_interface)) {
			panic("[ERROR] Could not find validation layers")
		}
	}

	create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
	create_info.enabledLayerCount = len(VALIDATION_LAYERS)

	glfw_extensions := glfw.GetRequiredInstanceExtensions()
	glfw_extension_count: int = len(glfw_extensions)
	glfw_ext2: [dynamic]cstring
	append(&glfw_ext2, ..glfw_extensions[:])
	when ODIN_DEBUG {
		glfw_extension_count += 1
		append(&glfw_ext2, cstring(vk.EXT_DEBUG_UTILS_EXTENSION_NAME))
	}
	glfw_extension_count += 1
	append(&glfw_ext2, cstring(vk.KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME))

	for ext in glfw_ext2 {
		fmt.println(ext)
	}

	create_info.ppEnabledExtensionNames = raw_data(glfw_ext2)
	create_info.enabledExtensionCount = cast(u32)len(glfw_ext2)

	debugCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT
	create_info.enabledLayerCount = 0
	create_info.pNext = nil
	when ODIN_DEBUG {
		populate_debug_messenger_create_info(&debugCreateInfo)
		create_info.pNext = &debugCreateInfo
		create_info.enabledLayerCount = 0
	}

	if (vk.CreateInstance(&create_info, nil, &v_interface.va_Instance) != .SUCCESS) {
		panic("ERROR: Failed to create instance\n")
	}

	vk.load_proc_addresses(get_proc_address)

	if (glfw.CreateWindowSurface(
			   v_interface.va_Instance,
			   v_interface.va_Window.w_window,
			   nil,
			   &v_interface.va_Window.w_surface,
		   ) !=
		   .SUCCESS) {
		panic("[ERROR] Could not create window surface")
	}

	when ODIN_DEBUG {
		if (vk.CreateDebugUtilsMessengerEXT(
				   v_interface.va_Instance,
				   &debugCreateInfo,
				   nil,
				   &v_interface.va_DebugMessenger,
			   ) !=
			   .SUCCESS) {
			panic("[ERROR] Could not create debug utils")
		}
	}

	// --------------------------------------------------------------
	// Create device
	device_count: u32 = 0
	vk.EnumeratePhysicalDevices(v_interface.va_Instance, &device_count, nil)

	if (device_count == 0) {
		panic("[ERROR] Could not find any GPU with vulkan support")
	}

	devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
	//defer delete_slice( devices, context.allocator );

	vk.EnumeratePhysicalDevices(v_interface.va_Instance, &device_count, raw_data(devices))

	fmt.println("[INFO] Number of devices found: ", len(devices))

	for &device in devices {
		if is_suitable_device(v_interface, device) {
			v_interface.va_Device.d_PhysicalDevice = device
			properties: vk.PhysicalDeviceProperties
			vk.GetPhysicalDeviceProperties(device, &properties)
			fmt.println("GPU Name: ", cstring(&properties.deviceName[0]))
			break
			/*
			if properties.deviceType == .DISCRETE_GPU {
				break
			}
      */
		}
	}

	if v_interface.va_Device.d_PhysicalDevice == nil {
		panic("[ERROR] Could not find suitable gpu")
	}


	queue_families := find_queue_families(v_interface, v_interface.va_Device.d_PhysicalDevice)
	queue_priority: f32 = 1
	queue_create_info: vk.DeviceQueueCreateInfo
	queue_create_info.sType = .DEVICE_QUEUE_CREATE_INFO
	queue_create_info.queueFamilyIndex = queue_families.qfi_GraphicsAndCompute
	queue_create_info.queueCount = 1
	queue_create_info.pQueuePriorities = &queue_priority

	device_features: vk.PhysicalDeviceFeatures
	device_features.samplerAnisotropy = true

	device_create_info: vk.DeviceCreateInfo
	device_create_info.sType = .DEVICE_CREATE_INFO
	device_create_info.pQueueCreateInfos = &queue_create_info
	device_create_info.queueCreateInfoCount = 1
	device_create_info.pEnabledFeatures = &device_features
	device_create_info.enabledExtensionCount = len(DEVICE_EXTENSIONS)
	device_create_info.ppEnabledExtensionNames = &DEVICE_EXTENSIONS[0]
	device_create_info.enabledLayerCount = 0
	device_create_info.pNext = nil
	when ODIN_DEBUG {
		device_create_info.enabledLayerCount = 1
		device_create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
	}

	if vk.CreateDevice(
		   v_interface.va_Device.d_PhysicalDevice,
		   &device_create_info,
		   nil,
		   &v_interface.va_Device.d_LogicalDevice,
	   ) !=
	   .SUCCESS {
		panic("[ERROR] Could not create logical device")
	}

	vk.GetDeviceQueue(
		v_interface.va_Device.d_LogicalDevice,
		queue_families.qfi_GraphicsAndCompute,
		0,
		&v_interface.va_Device.d_GraphicsQueue,
	)
	vk.GetDeviceQueue(
		v_interface.va_Device.d_LogicalDevice,
		queue_families.qfi_GraphicsAndCompute,
		0,
		&v_interface.va_Device.d_ComputeQueue,
	)
	vk.GetDeviceQueue(
		v_interface.va_Device.d_LogicalDevice,
		queue_families.qfi_Presentation,
		0,
		&v_interface.va_Device.d_PresentationQueue,
	)

	// --------------------------------------------------------------
	// Create swapchain
	create_swap_chain(v_interface)

	// --------------------------------------------------------------
	// Create image views for swap chain images
	create_image_views(v_interface)

	// --------------------------------------------------------------
	// Create main renderpass. TODO: add posibility of multiple renderpasses
	create_render_pass(v_interface)

	// --------------------------------------------------------------
	// Add descriptor layouts
	add_descriptor_set_layout(
		v_interface,
		{.UNIFORM_BUFFER, .UNIFORM_BUFFER, .COMBINED_IMAGE_SAMPLER},
	)

	// --------------------------------------------------------------
	// add pipeline

	vertex2D_data := #load("../../shaders/vert2D.spv")
	fragment2D_data := #load("../../shaders/frag2D.spv")
	vertex3D_data := #load("../../shaders/vert3D.spv")
	fragment3D_data := #load("../../shaders/frag3D.spv")
	compute_data := #load("../../shaders/compute.spv")

	v_interface.va_Pipelines = make([dynamic]Pipeline, 3, v_interface.ArenaAllocator)

	add_pipeline(
		v_interface,
		&v_interface.va_Pipelines[0],
		vertex2D_data,
		fragment2D_data,
		PipelineType.GRAPHICS2D,
	)

	add_pipeline(
		v_interface,
		&v_interface.va_Pipelines[1],
		vertex3D_data,
		fragment3D_data,
		PipelineType.GRAPHICS3D,
	)

	add_pipeline(
		v_interface,
		&v_interface.va_Pipelines[2],
		compute_data,
		nil,
		PipelineType.COMPUTE,
	)

	queueFamilyIndices := find_queue_families(v_interface, v_interface.va_Device.d_PhysicalDevice)

	poolInfo := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = vk.CommandPoolCreateFlags{.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queueFamilyIndices.qfi_GraphicsAndCompute,
	}

	if (vk.CreateCommandPool(
			   v_interface.va_Device.d_LogicalDevice,
			   &poolInfo,
			   nil,
			   &(v_interface.va_CommandPool),
		   ) !=
		   .SUCCESS) {
		panic("[ERROR] Failed to create graphics command pool\n")
	}

	// --------------------------------------------------------------
	// Create depth resources. Probably can make it so that there are more
	create_depth_resources(v_interface)

	// --------------------------------------------------------------
	// Add frame buffers
	create_frame_buffer(v_interface)

	// --------------------------------------------------------------
	// Create font cache
	//
	v_interface.bitmap = bitmap_create(2160, 2160, v_interface.ArenaAllocator)
	bitmap := bitmap_push(2160, 126, &v_interface.bitmap)
	new_bit := bitmap_push(2160, 126, &v_interface.bitmap)
	v_interface.va_FontCache = make([dynamic]FontCache, 2, v_interface.ArenaAllocator)
	v_interface.va_FontCache[0] = f_BuildFont(
		22 * v_interface.va_Window.scaling_factor.x,
		2160,
		126,
		raw_data(bitmap),
		"./data/font/RobotoMonoBold.ttf",
	)
	v_interface.va_FontCache[0].BitmapOffset = {0, 0}

	v_interface.va_FontCache[1] = f_BuildFont(
		18 * v_interface.va_Window.scaling_factor.x,
		2160,
		126,
		raw_data(new_bit),
	)
	v_interface.va_FontCache[1].BitmapOffset = {0, 126}

	// --------------------------------------------------------------
	// Add Texture image
	//
	add_texture_font(v_interface, &v_interface.va_FontCache)

	// --------------------------------------------------------------
	// Create dummy vertex buffers
	//

	batch: Batch2D
	append(
		&batch.vertices,
		Vertex2D {
			{0.0, 0.0},
			{200.0, 200.0},
			{0.2, 0.2, 0.2, 1.0},
			{0.1, 0.1, 0.1, 1.0},
			{0.2, 0.2, 0.2, 1.0},
			{0.1, 0.1, 0.1, 1.0},
			{-2, -2},
			{-2, -2},
			1,
			0.75,
			0,
		},
	)
	append(&batch.indices, 0, 1, 3, 3, 2, 0)
	append(&batch.n_instances, 1)

	add_batch2D_instanced_to_group(v_interface, &batch)

	end_batch2D_instance_group(v_interface)

	// ------------------------------------------------------------------------------------------
	// Create uniform buffers
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		v_interface.va_UniformBufferUI[i].vb_Size = size_of(UniformBufferUI)
		v_interface.va_UniformBufferUI[i].vb_UsageFlags = vk.BufferUsageFlags{.UNIFORM_BUFFER}
		v_interface.va_UniformBufferUI[i].vb_Properties = vk.MemoryPropertyFlags {
			.HOST_VISIBLE,
			.HOST_COHERENT,
		}
		create_buffer(v_interface, &v_interface.va_UniformBufferUI[i])
		memory_map_flag: vk.MemoryMapFlags
		vk.MapMemory(
			v_interface.va_Device.d_LogicalDevice,
			v_interface.va_UniformBufferUI[i].vb_DeviceMemory,
			0,
			size_of(UniformBufferUI),
			memory_map_flag,
			&v_interface.va_UniformBufferUI[i].vb_MappedMemory,
		)

		v_interface.va_UniformBuffer3D[i].vb_Size = size_of(UniformBuffer3D)
		v_interface.va_UniformBuffer3D[i].vb_UsageFlags = vk.BufferUsageFlags{.UNIFORM_BUFFER}
		v_interface.va_UniformBuffer3D[i].vb_Properties = vk.MemoryPropertyFlags {
			.HOST_VISIBLE,
			.HOST_COHERENT,
		}
		create_buffer(v_interface, &v_interface.va_UniformBuffer3D[i])

		vk.MapMemory(
			v_interface.va_Device.d_LogicalDevice,
			v_interface.va_UniformBuffer3D[i].vb_DeviceMemory,
			0,
			size_of(UniformBuffer3D),
			memory_map_flag,
			&v_interface.va_UniformBuffer3D[i].vb_MappedMemory,
		)
	}

	// -------------- Creates descriptor pool -------------------- //
	{
		poolSizes: [3]vk.DescriptorPoolSize
		poolSizes[0].type = .UNIFORM_BUFFER
		poolSizes[0].descriptorCount = MAX_FRAMES_IN_FLIGHT
		poolSizes[1].type = .UNIFORM_BUFFER
		poolSizes[1].descriptorCount = MAX_FRAMES_IN_FLIGHT
		poolSizes[2].type = .COMBINED_IMAGE_SAMPLER
		poolSizes[2].descriptorCount = MAX_FRAMES_IN_FLIGHT

		poolInfo: vk.DescriptorPoolCreateInfo
		poolInfo.sType = .DESCRIPTOR_POOL_CREATE_INFO
		poolInfo.poolSizeCount = 3
		poolInfo.pPoolSizes = raw_data(poolSizes[:])
		poolInfo.maxSets = MAX_FRAMES_IN_FLIGHT

		if (vk.CreateDescriptorPool(
				   v_interface.va_Device.d_LogicalDevice,
				   &poolInfo,
				   nil,
				   &v_interface.va_DescriptorPool,
			   ) !=
			   .SUCCESS) {
			panic("[ERROR] Failed to create descriptor pool\n")
		}
	}

	// -------------- Creates descriptor sets -------------------- //
	layouts: [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		layouts[i] = v_interface.va_Descriptors[0].d_DescriptorSetLayout
	}

	allocInfo: vk.DescriptorSetAllocateInfo
	allocInfo.sType = .DESCRIPTOR_SET_ALLOCATE_INFO
	allocInfo.descriptorPool = v_interface.va_DescriptorPool
	allocInfo.descriptorSetCount = MAX_FRAMES_IN_FLIGHT
	allocInfo.pSetLayouts = &layouts[0]

	descriptor_sets := raw_data(v_interface.va_Descriptors[0].d_DescriptorSet[:])
	if (vk.AllocateDescriptorSets(
			   v_interface.va_Device.d_LogicalDevice,
			   &allocInfo,
			   descriptor_sets,
		   ) !=
		   .SUCCESS) {
		panic("[ERROR] Failed to allocate descriptor sets\n")
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		bufferInfo: vk.DescriptorBufferInfo
		bufferInfo.buffer = v_interface.va_UniformBufferUI[i].vb_Buffer
		bufferInfo.offset = 0
		bufferInfo.range = size_of(UniformBufferUI)

		bufferInfo3D: vk.DescriptorBufferInfo
		bufferInfo3D.buffer = v_interface.va_UniformBuffer3D[i].vb_Buffer
		bufferInfo3D.offset = 0
		bufferInfo3D.range = size_of(UniformBuffer3D)

		imageInfo: vk.DescriptorImageInfo
		imageInfo.imageLayout = .SHADER_READ_ONLY_OPTIMAL
		imageInfo.imageView = v_interface.va_TextureImage.vi_ImageView
		imageInfo.sampler = v_interface.va_TextureImage.vi_Sampler

		descriptorWrites := make([]vk.WriteDescriptorSet, 3)
		defer delete_slice(descriptorWrites)

		descriptor_set := v_interface.va_Descriptors[0].d_DescriptorSet[i]

		descriptorWrites[0].sType = .WRITE_DESCRIPTOR_SET
		descriptorWrites[0].dstSet = descriptor_set
		descriptorWrites[0].dstBinding = 0
		descriptorWrites[0].dstArrayElement = 0
		descriptorWrites[0].descriptorType = .UNIFORM_BUFFER
		descriptorWrites[0].descriptorCount = 1
		descriptorWrites[0].pBufferInfo = &bufferInfo
		descriptorWrites[0].pNext = nil
		descriptorWrites[0].pTexelBufferView = nil

		descriptorWrites[1].sType = .WRITE_DESCRIPTOR_SET
		descriptorWrites[1].dstSet = descriptor_set
		descriptorWrites[1].dstBinding = 1
		descriptorWrites[1].dstArrayElement = 0
		descriptorWrites[1].descriptorType = .UNIFORM_BUFFER
		descriptorWrites[1].descriptorCount = 1
		descriptorWrites[1].pBufferInfo = &bufferInfo3D
		descriptorWrites[1].pNext = nil
		descriptorWrites[1].pTexelBufferView = nil

		descriptorWrites[2].sType = .WRITE_DESCRIPTOR_SET
		descriptorWrites[2].dstSet = descriptor_set
		descriptorWrites[2].dstBinding = 2
		descriptorWrites[2].dstArrayElement = 0
		descriptorWrites[2].descriptorType = .COMBINED_IMAGE_SAMPLER
		descriptorWrites[2].descriptorCount = 1
		descriptorWrites[2].pImageInfo = &imageInfo
		descriptorWrites[2].pNext = nil
		descriptorWrites[2].pTexelBufferView = nil

		vk.UpdateDescriptorSets(
			v_interface.va_Device.d_LogicalDevice,
			3,
			raw_data(descriptorWrites),
			0,
			nil,
		)
	}

	// -------------- Creates command buffers -------------------- //
	{
		allocInfo: vk.CommandBufferAllocateInfo
		allocInfo.sType = .COMMAND_BUFFER_ALLOCATE_INFO
		allocInfo.commandPool = v_interface.va_CommandPool
		allocInfo.level = .PRIMARY
		allocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT

		if (vk.AllocateCommandBuffers(
				   v_interface.va_Device.d_LogicalDevice,
				   &allocInfo,
				   raw_data(v_interface.va_CommandBuffers[:]),
			   ) !=
			   .SUCCESS) {
			panic("[ERROR] Failed to allocate command buffers\n")
		}
	}

	// -------------- Creates semaphores -------------------- //
	create_semaphores(v_interface)
}
