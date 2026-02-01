// ============================================================
// clay_layout_test.zig
// Zero-Pointer Ring Buffer Layout Engine — Full Test
// Hardcoded Prolog facts as Zig functions
// Single module, all 9 phases
// ============================================================

const std = @import("std");

// ============================================================
// PHASE 1: TYPE DEFINITIONS
// ============================================================

const SLOT_COUNT: usize = 5000;
const TEXT_LEN_MAX: usize = 1500;
const HASH_BUCKET_COUNT: usize = 5000;
const TREE_ROOT_COUNT: usize = 5000;
const WRAPPED_LINE_COUNT: usize = 5000;
const TEXT_DATA_COUNT: usize = 5000;
const RENDER_CMD_COUNT: usize = 10000;
const POINTER_OVER_COUNT: usize = 64;

// --- Sizing type constants (i32 enums) ---
const SIZE_FIT: i32 = 0;
const SIZE_GROW: i32 = 1;
const SIZE_PERCENT: i32 = 2;
const SIZE_FIXED: i32 = 3;

// --- Layout direction constants ---
const LAYOUT_LEFT_TO_RIGHT: i32 = 0;
const LAYOUT_TOP_TO_BOTTOM: i32 = 1;

// --- Slot state constants ---
const STATE_EMPTY: i32 = 0;
const STATE_LIVE: i32 = 1;
const STATE_DEAD: i32 = 2;

// --- Render command type constants ---
const CMD_SCISSOR_START: i32 = 0;
const CMD_RECTANGLE: i32 = 1;
const CMD_IMAGE: i32 = 2;
const CMD_TEXT: i32 = 3;
const CMD_CUSTOM: i32 = 4;
const CMD_BORDER: i32 = 5;
const CMD_SCISSOR_END: i32 = 6;

// --- Pointer state constants ---
const PTR_RELEASED: i32 = 0;
const PTR_PRESSED_THIS_FRAME: i32 = 1;
const PTR_PRESSED: i32 = 2;
const PTR_RELEASED_THIS_FRAME: i32 = 3;

// index_target: slot.children_start       -> ring_buffer
// index_target: slot.children_end         -> ring_buffer (exclusive)
// index_target: slot.layout_config_idx    -> layout_configs
// index_target: slot.config_shared        -> shared_configs
// index_target: slot.config_border        -> border_configs
// index_target: slot.config_floating      -> floating_configs
// index_target: slot.config_clip          -> clip_configs
// index_target: slot.config_text          -> text_configs
// index_target: slot.config_aspect        -> aspect_configs
// index_target: slot.config_image         -> image_configs
// index_target: slot.config_custom        -> custom_configs
// index_target: slot.text_data_idx        -> text_data
// index_target: slot.hash_next            -> ring_buffer
// index_target: hash_buckets.entry        -> ring_buffer
// index_target: text_data.wrapped_lines_start -> wrapped_lines
// index_target: text_data.wrapped_lines_end   -> wrapped_lines
// index_target: text_data.element_index       -> ring_buffer
// index_target: tree_root.layout_element_index -> ring_buffer
// index_target: floating_config.parent_id     -> ring_buffer (via hash lookup)

pub const Slot = struct {
    id: i32 = 0,
    state: i32 = STATE_EMPTY,
    dimensions_w: f32 = 0.0,
    dimensions_h: f32 = 0.0,
    min_dimensions_w: f32 = 0.0,
    min_dimensions_h: f32 = 0.0,
    bbox_x: f32 = 0.0,
    bbox_y: f32 = 0.0,
    bbox_w: f32 = 0.0,
    bbox_h: f32 = 0.0,
    children_start: i32 = -1,
    children_end: i32 = -1,
    floating_children_count: i32 = 0,
    config_shared: i32 = -1,
    config_border: i32 = -1,
    config_floating: i32 = -1,
    config_clip: i32 = -1,
    config_text: i32 = -1,
    config_aspect: i32 = -1,
    config_image: i32 = -1,
    config_custom: i32 = -1,
    layout_config_idx: i32 = -1,
    text_data_idx: i32 = -1,
    generation: i32 = 0,
    hash_next: i32 = -1,
    collision: i32 = 0,
    collapsed: i32 = 0,
    clip_element_id: i32 = -1,
    parent_slot_idx: i32 = -1,
};

pub const LayoutConfig = struct {
    sizing_w_type: i32 = SIZE_FIT,
    sizing_w_min: f32 = 0.0,
    sizing_w_max: f32 = 99999.0,
    sizing_w_percent: f32 = 0.0,
    sizing_h_type: i32 = SIZE_FIT,
    sizing_h_min: f32 = 0.0,
    sizing_h_max: f32 = 99999.0,
    sizing_h_percent: f32 = 0.0,
    padding_left: f32 = 0.0,
    padding_right: f32 = 0.0,
    padding_top: f32 = 0.0,
    padding_bottom: f32 = 0.0,
    child_gap: f32 = 0.0,
    layout_direction: i32 = LAYOUT_LEFT_TO_RIGHT,
    child_align_x: i32 = 0,
    child_align_y: i32 = 0,
};

pub const SharedConfig = struct {
    bg_r: f32 = 0.0,
    bg_g: f32 = 0.0,
    bg_b: f32 = 0.0,
    bg_a: f32 = 0.0,
    corner_tl: f32 = 0.0,
    corner_tr: f32 = 0.0,
    corner_bl: f32 = 0.0,
    corner_br: f32 = 0.0,
};

pub const BorderConfig = struct {
    color_r: f32 = 0.0,
    color_g: f32 = 0.0,
    color_b: f32 = 0.0,
    color_a: f32 = 0.0,
    left: i32 = 0,
    right: i32 = 0,
    top: i32 = 0,
    bottom: i32 = 0,
    between: i32 = 0,
};

pub const FloatingConfig = struct {
    offset_x: f32 = 0.0,
    offset_y: f32 = 0.0,
    expand_w: f32 = 0.0,
    expand_h: f32 = 0.0,
    parent_id: i32 = -1,
    z_index: i32 = 0,
    attach_element: i32 = 4,
    attach_parent: i32 = 4,
    capture_mode: i32 = 0,
    attach_to: i32 = 1,
    clip_to: i32 = 1,
};

pub const ClipConfig = struct {
    horizontal: i32 = 1,
    vertical: i32 = 1,
    child_offset_x: f32 = 0.0,
    child_offset_y: f32 = 0.0,
};

pub const TextConfig = struct {
    color_r: f32 = 1.0,
    color_g: f32 = 1.0,
    color_b: f32 = 1.0,
    color_a: f32 = 1.0,
    font_id: i32 = 0,
    font_size: i32 = 16,
    letter_spacing: i32 = 0,
    line_height: i32 = 20,
    wrap_mode: i32 = 0,
    alignment: i32 = 0,
};

pub const TextElementData = struct {
    text: [TEXT_LEN_MAX]u8 = [_]u8{0} ** TEXT_LEN_MAX,
    text_len: usize = 0,
    preferred_w: f32 = 0.0,
    preferred_h: f32 = 0.0,
    element_index: i32 = -1,
    wrapped_lines_start: i32 = -1,
    wrapped_lines_end: i32 = -1,
};

pub const WrappedLine = struct {
    dim_w: f32 = 0.0,
    dim_h: f32 = 0.0,
    text_start: usize = 0,
    text_len: usize = 0,
    source_text_data_idx: i32 = -1,
};

pub const TreeRoot = struct {
    layout_element_index: i32 = -1,
    parent_id: i32 = -1,
    clip_element_id: i32 = -1,
    z_index: i32 = 0,
};

pub const RenderCommand = struct {
    cmd_type: i32 = 0,
    x: f32 = 0.0,
    y: f32 = 0.0,
    w: f32 = 0.0,
    h: f32 = 0.0,
    color_r: f32 = 0.0,
    color_g: f32 = 0.0,
    color_b: f32 = 0.0,
    color_a: f32 = 0.0,
    corner_tl: f32 = 0.0,
    corner_tr: f32 = 0.0,
    corner_bl: f32 = 0.0,
    corner_br: f32 = 0.0,
    border_left: i32 = 0,
    border_right: i32 = 0,
    border_top: i32 = 0,
    border_bottom: i32 = 0,
    text_data_idx: i32 = -1,
    wrapped_line_idx: i32 = -1,
    slot_id: i32 = 0,
};

// ============================================================
// GLOBAL STATE — static arrays, zero allocation
// ============================================================

var ring_buffer: [SLOT_COUNT]Slot = [_]Slot{Slot{}} ** SLOT_COUNT;
var layout_configs: [SLOT_COUNT]LayoutConfig = [_]LayoutConfig{LayoutConfig{}} ** SLOT_COUNT;
var shared_configs: [SLOT_COUNT]SharedConfig = [_]SharedConfig{SharedConfig{}} ** SLOT_COUNT;
var border_configs: [SLOT_COUNT]BorderConfig = [_]BorderConfig{BorderConfig{}} ** SLOT_COUNT;
var floating_configs: [SLOT_COUNT]FloatingConfig = [_]FloatingConfig{FloatingConfig{}} ** SLOT_COUNT;
var clip_configs: [SLOT_COUNT]ClipConfig = [_]ClipConfig{ClipConfig{}} ** SLOT_COUNT;
var text_configs: [SLOT_COUNT]TextConfig = [_]TextConfig{TextConfig{}} ** SLOT_COUNT;
var aspect_configs: [SLOT_COUNT]f32 = [_]f32{0.0} ** SLOT_COUNT;
var image_configs: [SLOT_COUNT]i32 = [_]i32{-1} ** SLOT_COUNT;
var custom_configs: [SLOT_COUNT]i32 = [_]i32{-1} ** SLOT_COUNT;
var text_data: [TEXT_DATA_COUNT]TextElementData = [_]TextElementData{TextElementData{}} ** TEXT_DATA_COUNT;
var wrapped_lines: [WRAPPED_LINE_COUNT]WrappedLine = [_]WrappedLine{WrappedLine{}} ** WRAPPED_LINE_COUNT;
var tree_roots: [TREE_ROOT_COUNT]TreeRoot = [_]TreeRoot{TreeRoot{}} ** TREE_ROOT_COUNT;
var hash_buckets: [HASH_BUCKET_COUNT]i32 = [_]i32{-1} ** HASH_BUCKET_COUNT;
var render_commands: [RENDER_CMD_COUNT]RenderCommand = [_]RenderCommand{RenderCommand{}} ** RENDER_CMD_COUNT;
var pointer_over_ids: [POINTER_OVER_COUNT]i32 = [_]i32{-1} ** POINTER_OVER_COUNT;

// Counters for next-free-slot in each array
var next_slot: i32 = 0;
var next_layout_config: i32 = 0;
var next_shared_config: i32 = 0;
var next_border_config: i32 = 0;
var next_floating_config: i32 = 0;
var next_clip_config: i32 = 0;
var next_text_config: i32 = 0;
var next_aspect_config: i32 = 0;
var next_text_data: i32 = 0;
var next_wrapped_line: i32 = 0;
var next_tree_root: i32 = 0;
var next_render_cmd: i32 = 0;

var current_generation: i32 = 1;
var layout_width: f32 = 800.0;
var layout_height: f32 = 600.0;

// Declaration stack
var decl_stack: [256]i32 = [_]i32{-1} ** 256;
var decl_stack_top: i32 = -1;

// Pointer state
var pointer_state: i32 = PTR_RELEASED;
var pointer_over_write_head: i32 = 0;

// ============================================================
// PHASE 7: DEPENDENCY VALIDATION
// depends_on/2 as bitmask runtime assertions
// ============================================================

// Bit assignments per pass
const BIT_DECLARATION: i32 = 1 << 1;
const BIT_SIZE_X: i32 = 1 << 2;
const BIT_TEXT_WRAP: i32 = 1 << 3;
const BIT_ASPECT_RATIO_V: i32 = 1 << 4;
const BIT_PROPAGATE_HEIGHTS: i32 = 1 << 5;
const BIT_SIZE_Y: i32 = 1 << 6;
const BIT_ASPECT_RATIO_H: i32 = 1 << 7;
const BIT_SORT_Z: i32 = 1 << 8;
const BIT_FINAL_LAYOUT: i32 = 1 << 9;
const BIT_POINTER_DETECTION: i32 = 1 << 0;

var passes_completed: i32 = 0;

fn assertDepsAndMark(pass_bit: i32, dep_bits: i32) void {
    std.debug.assert((passes_completed & dep_bits) == dep_bits);
    passes_completed |= pass_bit;
}

// ============================================================
// PHASE 3: HELPER FUNCTIONS — config_present, config_lookup
// Hardcoded Prolog facts: config_present/2, config_lookup/3
// ============================================================

fn configPresentShared(slot_idx: i32) bool {
    return ring_buffer[@intCast(slot_idx)].config_shared != -1;
}
fn configPresentBorder(slot_idx: i32) bool {
    return ring_buffer[@intCast(slot_idx)].config_border != -1;
}
fn configPresentFloating(slot_idx: i32) bool {
    return ring_buffer[@intCast(slot_idx)].config_floating != -1;
}
fn configPresentClip(slot_idx: i32) bool {
    return ring_buffer[@intCast(slot_idx)].config_clip != -1;
}
fn configPresentText(slot_idx: i32) bool {
    return ring_buffer[@intCast(slot_idx)].config_text != -1;
}
fn configPresentAspect(slot_idx: i32) bool {
    return ring_buffer[@intCast(slot_idx)].config_aspect != -1;
}
fn configPresentImage(slot_idx: i32) bool {
    return ring_buffer[@intCast(slot_idx)].config_image != -1;
}
fn configPresentCustom(slot_idx: i32) bool {
    return ring_buffer[@intCast(slot_idx)].config_custom != -1;
}

fn configLookupShared(slot_idx: i32) i32 {
    return ring_buffer[@intCast(slot_idx)].config_shared;
}
fn configLookupBorder(slot_idx: i32) i32 {
    return ring_buffer[@intCast(slot_idx)].config_border;
}
fn configLookupFloating(slot_idx: i32) i32 {
    return ring_buffer[@intCast(slot_idx)].config_floating;
}
fn configLookupClip(slot_idx: i32) i32 {
    return ring_buffer[@intCast(slot_idx)].config_clip;
}
fn configLookupText(slot_idx: i32) i32 {
    return ring_buffer[@intCast(slot_idx)].config_text;
}
fn configLookupAspect(slot_idx: i32) i32 {
    return ring_buffer[@intCast(slot_idx)].config_aspect;
}
fn configLookupImage(slot_idx: i32) i32 {
    return ring_buffer[@intCast(slot_idx)].config_image;
}
fn configLookupCustom(slot_idx: i32) i32 {
    return ring_buffer[@intCast(slot_idx)].config_custom;
}

// ============================================================
// PHASE 4: CHILDREN ITERATION
// children_iteration/2, children_sizing_filter/2
// ============================================================

// Iterates [children_start, children_end), skips state != LIVE
// Returns count of live children visited via callback
// We use a simple loop pattern — caller iterates directly

fn childrenStart(parent_idx: i32) i32 {
    return ring_buffer[@intCast(parent_idx)].children_start;
}
fn childrenEnd(parent_idx: i32) i32 {
    return ring_buffer[@intCast(parent_idx)].children_end;
}

fn isChildLive(child_idx: i32) bool {
    return ring_buffer[@intCast(child_idx)].state == STATE_LIVE;
}

fn isChildNonFloating(child_idx: i32) bool {
    return ring_buffer[@intCast(child_idx)].config_floating == -1;
}

// ============================================================
// PHASE 5: HASH MAP
// hash_map_fields/3, hash_bucket_index/2, chain walk
// ============================================================

fn hashBucket(id: i32) i32 {
    // Ensure positive modulo
    const raw: i32 = @mod(id, @as(i32, HASH_BUCKET_COUNT));
    return if (raw < 0) raw + @as(i32, HASH_BUCKET_COUNT) else raw;
}

// hash_chain_walk: returns slot index matching target_id, or -1
fn hashChainWalk(target_id: i32) i32 {
    const bucket = hashBucket(target_id);
    var idx: i32 = hash_buckets[@intCast(bucket)];
    while (idx != -1) {
        if (ring_buffer[@intCast(idx)].id == target_id) {
            return idx;
        }
        idx = ring_buffer[@intCast(idx)].hash_next;
    }
    return -1;
}

// hash_insert: generational collision policy
// Returns slot index (existing or new)
fn hashInsert(id: i32, slot_idx: i32) i32 {
    const bucket = hashBucket(id);
    var idx: i32 = hash_buckets[@intCast(bucket)];
    while (idx != -1) {
        if (ring_buffer[@intCast(idx)].id == id) {
            if (ring_buffer[@intCast(idx)].generation == current_generation) {
                // Duplicate ID this frame
                std.debug.print("HASH ERROR: duplicate id {} this frame\n", .{id});
                return idx;
            } else {
                // Same element, new frame — update generation
                ring_buffer[@intCast(idx)].generation = current_generation;
                return idx;
            }
        }
        idx = ring_buffer[@intCast(idx)].hash_next;
    }
    // Not found — link new slot into chain
    ring_buffer[@intCast(slot_idx)].hash_next = hash_buckets[@intCast(bucket)];
    hash_buckets[@intCast(bucket)] = slot_idx;
    ring_buffer[@intCast(slot_idx)].generation = current_generation;
    return slot_idx;
}

// ============================================================
// PHASE 6: PASS FUNCTIONS
// ============================================================

// --- Allocate helpers for configs ---

fn allocSlot() i32 {
    const idx = next_slot;
    next_slot += 1;
    ring_buffer[@intCast(idx)] = Slot{};
    return idx;
}

fn allocLayoutConfig(cfg: LayoutConfig) i32 {
    const idx = next_layout_config;
    next_layout_config += 1;
    layout_configs[@intCast(idx)] = cfg;
    return idx;
}

fn allocSharedConfig(cfg: SharedConfig) i32 {
    const idx = next_shared_config;
    next_shared_config += 1;
    shared_configs[@intCast(idx)] = cfg;
    return idx;
}

fn allocBorderConfig(cfg: BorderConfig) i32 {
    const idx = next_border_config;
    next_border_config += 1;
    border_configs[@intCast(idx)] = cfg;
    return idx;
}

fn allocFloatingConfig(cfg: FloatingConfig) i32 {
    const idx = next_floating_config;
    next_floating_config += 1;
    floating_configs[@intCast(idx)] = cfg;
    return idx;
}

fn allocClipConfig(cfg: ClipConfig) i32 {
    const idx = next_clip_config;
    next_clip_config += 1;
    clip_configs[@intCast(idx)] = cfg;
    return idx;
}

fn allocTextConfig(cfg: TextConfig) i32 {
    const idx = next_text_config;
    next_text_config += 1;
    text_configs[@intCast(idx)] = cfg;
    return idx;
}

fn allocTextData(text: []const u8, element_idx: i32) i32 {
    const idx = next_text_data;
    next_text_data += 1;
    text_data[@intCast(idx)] = TextElementData{};
    const copy_len = if (text.len < TEXT_LEN_MAX) text.len else TEXT_LEN_MAX;
    @memcpy(text_data[@intCast(idx)].text[0..copy_len], text[0..copy_len]);
    text_data[@intCast(idx)].text_len = copy_len;
    text_data[@intCast(idx)].element_index = element_idx;
    return idx;
}

fn allocWrappedLine(line: WrappedLine) i32 {
    const idx = next_wrapped_line;
    next_wrapped_line += 1;
    wrapped_lines[@intCast(idx)] = line;
    return idx;
}

fn allocTreeRoot(root: TreeRoot) i32 {
    const idx = next_tree_root;
    next_tree_root += 1;
    tree_roots[@intCast(idx)] = root;
    return idx;
}

fn emitRenderCommand(cmd: RenderCommand) void {
    render_commands[@intCast(next_render_cmd)] = cmd;
    next_render_cmd += 1;
}

// --- Declaration helpers: open / close element ---

fn elementOpen(id: i32, layout: LayoutConfig, shared: ?SharedConfig, border: ?BorderConfig, clip: ?ClipConfig) i32 {
    const slot_idx = allocSlot();
    ring_buffer[@intCast(slot_idx)].id = id;
    ring_buffer[@intCast(slot_idx)].state = STATE_LIVE;
    ring_buffer[@intCast(slot_idx)].layout_config_idx = allocLayoutConfig(layout);
    ring_buffer[@intCast(slot_idx)].children_start = next_slot; // children will follow

    if (shared) |s| {
        ring_buffer[@intCast(slot_idx)].config_shared = allocSharedConfig(s);
    }
    if (border) |b| {
        ring_buffer[@intCast(slot_idx)].config_border = allocBorderConfig(b);
    }
    if (clip) |c| {
        ring_buffer[@intCast(slot_idx)].config_clip = allocClipConfig(c);
    }

    // Inherit clip_element_id from parent
    if (decl_stack_top >= 0) {
        const parent_idx = decl_stack[@intCast(decl_stack_top)];
        ring_buffer[@intCast(slot_idx)].parent_slot_idx = parent_idx;
        // If this element IS a clip container, it becomes its own clip_element_id
        if (ring_buffer[@intCast(slot_idx)].config_clip != -1) {
            ring_buffer[@intCast(slot_idx)].clip_element_id = id;
        } else {
            ring_buffer[@intCast(slot_idx)].clip_element_id = ring_buffer[@intCast(parent_idx)].clip_element_id;
        }
    } else {
        // Root element
        if (ring_buffer[@intCast(slot_idx)].config_clip != -1) {
            ring_buffer[@intCast(slot_idx)].clip_element_id = id;
        }
    }

    // Push onto declaration stack
    decl_stack_top += 1;
    decl_stack[@intCast(decl_stack_top)] = slot_idx;

    // Hash insert
    _ = hashInsert(id, slot_idx);

    return slot_idx;
}

fn elementClose() void {
    const slot_idx = decl_stack[@intCast(decl_stack_top)];
    decl_stack_top -= 1;

    // children_end = current next_slot (exclusive)
    ring_buffer[@intCast(slot_idx)].children_end = next_slot;

    // Compute fit dimensions from children
    const lc_idx = ring_buffer[@intCast(slot_idx)].layout_config_idx;
    const lc = &layout_configs[@intCast(lc_idx)];

    var fit_w: f32 = lc.padding_left + lc.padding_right;
    var fit_h: f32 = lc.padding_top + lc.padding_bottom;
    var child_count: i32 = 0;
    var max_child_w: f32 = 0.0;
    var max_child_h: f32 = 0.0;
    var sum_child_w: f32 = 0.0;
    var sum_child_h: f32 = 0.0;

    var i: i32 = ring_buffer[@intCast(slot_idx)].children_start;
    while (i < ring_buffer[@intCast(slot_idx)].children_end) {
        if (isChildLive(i)) {
            if (configPresentFloating(i)) {
                ring_buffer[@intCast(slot_idx)].floating_children_count += 1;
                // Floating child — write TreeRoot
                const fc_idx = configLookupFloating(i);
                const fc = &floating_configs[@intCast(fc_idx)];
                _ = allocTreeRoot(TreeRoot{
                    .layout_element_index = i,
                    .parent_id = fc.parent_id,
                    .clip_element_id = ring_buffer[@intCast(i)].clip_element_id,
                    .z_index = fc.z_index,
                });
            } else {
                // Non-floating: contributes to fit
                child_count += 1;
                const cw = ring_buffer[@intCast(i)].dimensions_w;
                const ch = ring_buffer[@intCast(i)].dimensions_h;
                sum_child_w += cw;
                sum_child_h += ch;
                if (cw > max_child_w) max_child_w = cw;
                if (ch > max_child_h) max_child_h = ch;
            }
        }
        i += 1;
    }

    const gap_total: f32 = if (child_count > 1) lc.child_gap * @as(f32, @intCast(child_count - 1)) else 0.0;

    if (lc.layout_direction == LAYOUT_LEFT_TO_RIGHT) {
        fit_w += sum_child_w + gap_total;
        fit_h += max_child_h;
    } else {
        fit_h += sum_child_h + gap_total;
        fit_w += max_child_w;
    }

    // Only write fit if sizing type is FIT (type 0)
    if (lc.sizing_w_type == SIZE_FIT) {
        ring_buffer[@intCast(slot_idx)].dimensions_w = fit_w;
    }
    if (lc.sizing_h_type == SIZE_FIT) {
        ring_buffer[@intCast(slot_idx)].dimensions_h = fit_h;
    }
}

fn elementOpenFloating(id: i32, layout: LayoutConfig, float_cfg: FloatingConfig, shared: ?SharedConfig) i32 {
    const slot_idx = elementOpen(id, layout, shared, null, null);
    ring_buffer[@intCast(slot_idx)].config_floating = allocFloatingConfig(float_cfg);
    return slot_idx;
}

fn elementOpenText(id: i32, layout: LayoutConfig, text: []const u8, text_cfg: TextConfig, shared: ?SharedConfig) i32 {
    const slot_idx = elementOpen(id, layout, shared, null, null);
    ring_buffer[@intCast(slot_idx)].config_text = allocTextConfig(text_cfg);
    ring_buffer[@intCast(slot_idx)].text_data_idx = allocTextData(text, slot_idx);
    return slot_idx;
}

// --- PASS 1: declaration ---
// This is the test harness element tree. The declaration IS the pass.
// See Phase 8 for the actual tree structure.

fn passDeclaration() void {
    assertDepsAndMark(BIT_DECLARATION, 0); // no dependencies

    // Reset counters for this frame
    next_slot = 0;
    next_layout_config = 0;
    next_shared_config = 0;
    next_border_config = 0;
    next_floating_config = 0;
    next_clip_config = 0;
    next_text_config = 0;
    next_text_data = 0;
    next_wrapped_line = 0;
    next_tree_root = 0;
    next_render_cmd = 0;
    decl_stack_top = -1;
    hash_buckets = [_]i32{-1} ** HASH_BUCKET_COUNT;
    current_generation += 1;

    // ============================================================
    // PHASE 8: TEST HARNESS — hardcoded element tree
    //
    // Tree structure:
    //   [100] Root container (TOP_TO_BOTTOM, 800x600 FIXED, red bg)
    //     [200] Child A (LEFT_TO_RIGHT, FIT width, 100h FIXED, blue bg)
    //       [300] Grandchild A1 (FIT, 50x50 FIXED, green bg)
    //       [301] Grandchild A2 (GROW width, 50h FIXED, yellow bg)
    //     [400] Child B — clip container (TOP_TO_BOTTOM, GROW width, 200h FIXED, purple bg, scroll offset)
    //       [500] Text element ("Hello World Layout Test", white text)
    //       [600] Aspect ratio child (width 100 FIXED, aspect 2.0 -> height = 50)
    //     [700] Floating element (attached to element 300, center-center, offset 10,10)
    //
    // Root has border with between=2
    // ============================================================

    // --- Root: id=100 ---
    _ = elementOpen(100, LayoutConfig{
        .sizing_w_type = SIZE_FIXED,
        .sizing_w_min = 800.0,
        .sizing_w_max = 800.0,
        .sizing_h_type = SIZE_FIXED,
        .sizing_h_min = 600.0,
        .sizing_h_max = 600.0,
        .layout_direction = LAYOUT_TOP_TO_BOTTOM,
        .padding_left = 10.0,
        .padding_right = 10.0,
        .padding_top = 10.0,
        .padding_bottom = 10.0,
        .child_gap = 5.0,
    }, SharedConfig{ .bg_r = 0.8, .bg_g = 0.1, .bg_b = 0.1, .bg_a = 1.0 }, BorderConfig{ .color_r = 1.0, .color_g = 1.0, .color_b = 1.0, .color_a = 1.0, .left = 2, .right = 2, .top = 2, .bottom = 2, .between = 2 }, null);
    ring_buffer[@intCast(next_slot - 1)].dimensions_w = 800.0;
    ring_buffer[@intCast(next_slot - 1)].dimensions_h = 600.0;

    // --- Child A: id=200 ---
    _ = elementOpen(200, LayoutConfig{
        .sizing_w_type = SIZE_FIT,
        .sizing_h_type = SIZE_FIXED,
        .sizing_h_min = 100.0,
        .sizing_h_max = 100.0,
        .layout_direction = LAYOUT_LEFT_TO_RIGHT,
        .child_gap = 8.0,
    }, SharedConfig{ .bg_r = 0.1, .bg_g = 0.1, .bg_b = 0.8, .bg_a = 1.0 }, null, null);
    ring_buffer[@intCast(next_slot - 1)].dimensions_h = 100.0;

    // --- Grandchild A1: id=300 ---
    _ = elementOpen(300, LayoutConfig{
        .sizing_w_type = SIZE_FIXED,
        .sizing_w_min = 50.0,
        .sizing_w_max = 50.0,
        .sizing_h_type = SIZE_FIXED,
        .sizing_h_min = 50.0,
        .sizing_h_max = 50.0,
    }, SharedConfig{ .bg_r = 0.1, .bg_g = 0.8, .bg_b = 0.1, .bg_a = 1.0 }, null, null);
    ring_buffer[@intCast(next_slot - 1)].dimensions_w = 50.0;
    ring_buffer[@intCast(next_slot - 1)].dimensions_h = 50.0;
    elementClose(); // close 300

    // --- Grandchild A2: id=301 (GROW) ---
    _ = elementOpen(301, LayoutConfig{
        .sizing_w_type = SIZE_GROW,
        .sizing_w_min = 20.0,
        .sizing_w_max = 99999.0,
        .sizing_h_type = SIZE_FIXED,
        .sizing_h_min = 50.0,
        .sizing_h_max = 50.0,
    }, SharedConfig{ .bg_r = 0.8, .bg_g = 0.8, .bg_b = 0.1, .bg_a = 1.0 }, null, null);
    ring_buffer[@intCast(next_slot - 1)].dimensions_h = 50.0;
    elementClose(); // close 301

    elementClose(); // close 200 — fit_w computed from children

    // --- Child B: id=400, clip container ---
    _ = elementOpen(400, LayoutConfig{
        .sizing_w_type = SIZE_GROW,
        .sizing_w_min = 0.0,
        .sizing_w_max = 99999.0,
        .sizing_h_type = SIZE_FIXED,
        .sizing_h_min = 200.0,
        .sizing_h_max = 200.0,
        .layout_direction = LAYOUT_TOP_TO_BOTTOM,
        .child_gap = 4.0,
        .padding_left = 5.0,
        .padding_right = 5.0,
        .padding_top = 5.0,
        .padding_bottom = 5.0,
    }, SharedConfig{ .bg_r = 0.5, .bg_g = 0.1, .bg_b = 0.5, .bg_a = 1.0 }, null, ClipConfig{ .horizontal = 1, .vertical = 1, .child_offset_x = 0.0, .child_offset_y = -10.0 });
    ring_buffer[@intCast(next_slot - 1)].dimensions_h = 200.0;

    // --- Text element: id=500 ---
    _ = elementOpenText(500, LayoutConfig{
        .sizing_w_type = SIZE_GROW,
        .sizing_h_type = SIZE_FIT,
    }, "Hello World Layout Test", TextConfig{ .color_r = 1.0, .color_g = 1.0, .color_b = 1.0, .color_a = 1.0, .font_id = 0, .font_size = 16, .line_height = 20, .wrap_mode = 0 }, null);
    elementClose(); // close 500

    // --- Aspect ratio child: id=600 ---
    _ = elementOpen(600, LayoutConfig{
        .sizing_w_type = SIZE_FIXED,
        .sizing_w_min = 100.0,
        .sizing_w_max = 100.0,
        .sizing_h_type = SIZE_FIT,
    }, SharedConfig{ .bg_r = 0.1, .bg_g = 0.5, .bg_b = 0.8, .bg_a = 1.0 }, null, null);
    ring_buffer[@intCast(next_slot - 1)].dimensions_w = 100.0;
    ring_buffer[@intCast(next_slot - 1)].config_aspect = next_aspect_config;
    aspect_configs[@intCast(next_aspect_config)] = 2.0; // aspect ratio 2.0
    next_aspect_config += 1;
    elementClose(); // close 600

    elementClose(); // close 400

    // --- Floating element: id=700, attached to element 300 ---
    _ = elementOpenFloating(700, LayoutConfig{
        .sizing_w_type = SIZE_FIXED,
        .sizing_w_min = 60.0,
        .sizing_w_max = 60.0,
        .sizing_h_type = SIZE_FIXED,
        .sizing_h_min = 40.0,
        .sizing_h_max = 40.0,
    }, FloatingConfig{
        .attach_to = 2, // element_with_id
        .parent_id = 300, // attach to element 300
        .attach_parent = 4, // center_center on parent
        .attach_element = 4, // center_center on self
        .offset_x = 10.0,
        .offset_y = 10.0,
        .z_index = 1,
        .capture_mode = 0, // capture
    }, SharedConfig{ .bg_r = 0.9, .bg_g = 0.5, .bg_b = 0.1, .bg_a = 1.0 });
    ring_buffer[@intCast(next_slot - 1)].dimensions_w = 60.0;
    ring_buffer[@intCast(next_slot - 1)].dimensions_h = 40.0;
    elementClose(); // close 700

    elementClose(); // close 100 — root

    // Root element also gets a TreeRoot entry (it's the main layout root)
    _ = allocTreeRoot(TreeRoot{
        .layout_element_index = 0, // root is slot 0
        .parent_id = -1,
        .clip_element_id = -1,
        .z_index = 0,
    });

    std.debug.print("--- Pass 1: declaration complete. {} slots, {} tree roots ---\n", .{ next_slot, next_tree_root });
}

// --- PASS 2: size_x ---
// BFS top-down per tree root. Resolve X dimensions.

fn passSizeX() void {
    assertDepsAndMark(BIT_SIZE_X, BIT_DECLARATION);

    // BFS queue — static array, no alloc
    var queue: [SLOT_COUNT]i32 = [_]i32{-1} ** SLOT_COUNT;
    var q_head: i32 = 0;
    var q_tail: i32 = 0;

    // Seed BFS from each tree root
    var r: i32 = 0;
    while (r < next_tree_root) {
        const root_slot = tree_roots[@intCast(r)].layout_element_index;
        if (root_slot >= 0) {
            queue[@intCast(q_tail)] = root_slot;
            q_tail += 1;
        }
        r += 1;
    }

    while (q_head < q_tail) {
        const slot_idx = queue[@intCast(q_head)];
        q_head += 1;

        const lc_idx = ring_buffer[@intCast(slot_idx)].layout_config_idx;
        if (lc_idx == -1) continue;
        const lc = &layout_configs[@intCast(lc_idx)];
        const parent_w: f32 = ring_buffer[@intCast(slot_idx)].dimensions_w;

        // Resolve children X
        var i: i32 = ring_buffer[@intCast(slot_idx)].children_start;
        while (i < ring_buffer[@intCast(slot_idx)].children_end) {
            if (isChildLive(i) and isChildNonFloating(i)) {
                const child_lc_idx = ring_buffer[@intCast(i)].layout_config_idx;
                if (child_lc_idx == -1) {
                    i += 1;
                    continue;
                }
                const child_lc = &layout_configs[@intCast(child_lc_idx)];
                const content_w: f32 = parent_w - lc.padding_left - lc.padding_right;

                if (lc.layout_direction == LAYOUT_LEFT_TO_RIGHT) {
                    // Along axis
                    switch (child_lc.sizing_w_type) {
                        SIZE_FIXED => {
                            ring_buffer[@intCast(i)].dimensions_w = child_lc.sizing_w_min;
                        },
                        SIZE_PERCENT => {
                            // Count non-grow children for gap calc
                            var nfc: i32 = 0;
                            var j: i32 = ring_buffer[@intCast(slot_idx)].children_start;
                            while (j < ring_buffer[@intCast(slot_idx)].children_end) {
                                if (isChildLive(j) and isChildNonFloating(j)) nfc += 1;
                                j += 1;
                            }
                            const gap_total: f32 = if (nfc > 1) lc.child_gap * @as(f32, @intCast(nfc - 1)) else 0.0;
                            ring_buffer[@intCast(i)].dimensions_w = (content_w - gap_total) * child_lc.sizing_w_percent;
                        },
                        SIZE_GROW => {
                            // GROW distribution — simple equal split among all GROW children
                            var non_grow_sum: f32 = 0.0;
                            var grow_count: i32 = 0;
                            var nfc2: i32 = 0;
                            var j2: i32 = ring_buffer[@intCast(slot_idx)].children_start;
                            while (j2 < ring_buffer[@intCast(slot_idx)].children_end) {
                                if (isChildLive(j2) and isChildNonFloating(j2)) {
                                    nfc2 += 1;
                                    const cj_lc_idx = ring_buffer[@intCast(j2)].layout_config_idx;
                                    if (cj_lc_idx != -1) {
                                        const cj_lc = &layout_configs[@intCast(cj_lc_idx)];
                                        if (cj_lc.sizing_w_type == SIZE_GROW) {
                                            grow_count += 1;
                                        } else {
                                            non_grow_sum += ring_buffer[@intCast(j2)].dimensions_w;
                                        }
                                    }
                                }
                                j2 += 1;
                            }
                            const gap_total2: f32 = if (nfc2 > 1) lc.child_gap * @as(f32, @intCast(nfc2 - 1)) else 0.0;
                            const remaining: f32 = content_w - gap_total2 - non_grow_sum;
                            if (grow_count > 0 and remaining > 0) {
                                var grown: f32 = remaining / @as(f32, @intCast(grow_count));
                                grown = @max(grown, child_lc.sizing_w_min);
                                grown = @min(grown, child_lc.sizing_w_max);
                                ring_buffer[@intCast(i)].dimensions_w = grown;
                            }
                        },
                        else => {}, // FIT — already set in declaration
                    }
                } else {
                    // Off axis (X for TOP_TO_BOTTOM)
                    switch (child_lc.sizing_w_type) {
                        SIZE_GROW => {
                            ring_buffer[@intCast(i)].dimensions_w = @max(@min(content_w, child_lc.sizing_w_max), child_lc.sizing_w_min);
                        },
                        SIZE_PERCENT => {
                            ring_buffer[@intCast(i)].dimensions_w = @max(@min(content_w * child_lc.sizing_w_percent, child_lc.sizing_w_max), child_lc.sizing_w_min);
                        },
                        SIZE_FIT => {
                            ring_buffer[@intCast(i)].dimensions_w = @max(@min(ring_buffer[@intCast(i)].dimensions_w, child_lc.sizing_w_max), child_lc.sizing_w_min);
                        },
                        else => {}, // FIXED already set
                    }
                }

                // Enqueue child for its own children
                queue[@intCast(q_tail)] = i;
                q_tail += 1;
            }
            i += 1;
        }
    }

    std.debug.print("--- Pass 2: size_x complete ---\n", .{});
}

// --- PASS 3: text_wrap ---
// Linear scan. Simplified: assume ~8px per character at font_size 16.
// No real font measurement — this is a structural test.

fn passTextWrap() void {
    assertDepsAndMark(BIT_TEXT_WRAP, BIT_SIZE_X);

    var i: i32 = 0;
    while (i < next_slot) {
        if (ring_buffer[@intCast(i)].text_data_idx != -1) {
            const td_idx = ring_buffer[@intCast(i)].text_data_idx;
            const td = &text_data[@intCast(td_idx)];
            const tc_idx = ring_buffer[@intCast(i)].config_text;
            const tc = &text_configs[@intCast(tc_idx)];

            const container_w: f32 = ring_buffer[@intCast(i)].dimensions_w;
            const char_w: f32 = @as(f32, @intCast(tc.font_size)) * 0.5; // simplified: half font size per char
            const line_h: f32 = @as(f32, @intCast(tc.line_height));

            // Simple word wrap: walk text, break at spaces where line exceeds container_w
            td.wrapped_lines_start = next_wrapped_line;

            var line_start: usize = 0;
            var line_w: f32 = 0.0;
            var pos: usize = 0;

            while (pos <= td.text_len) {
                const at_end = pos == td.text_len;
                const at_space = if (!at_end) td.text[pos] == ' ' else false;

                if (at_end or at_space) {
                    // End of word or end of text
                    if (pos > line_start) {
                        const word_len = pos - line_start;
                        const word_w: f32 = @as(f32, @intCast(word_len)) * char_w;

                        if (line_w + word_w > container_w and line_w > 0.0) {
                            // Emit current line (before this word)
                            // Find where the previous word ended
                            var prev_end: usize = line_start;
                            // We need to track line content differently.
                            // Simplified: emit a line for everything up to the last space before overflow
                            _ = allocWrappedLine(WrappedLine{
                                .dim_w = line_w,
                                .dim_h = line_h,
                                .text_start = line_start,
                                .text_len = if (line_start < pos) pos - line_start - 1 else 0,
                                .source_text_data_idx = td_idx,
                            });
                            line_start = pos; // after the space we haven't consumed yet
                            if (at_space) line_start = pos + 1;
                            line_w = word_w;
                            prev_end = prev_end; // suppress unused warning
                        } else {
                            line_w += word_w;
                            if (at_space) line_w += char_w; // space width
                        }
                    }
                    if (at_end and line_start < td.text_len) {
                        // Emit final line
                        _ = allocWrappedLine(WrappedLine{
                            .dim_w = line_w,
                            .dim_h = line_h,
                            .text_start = line_start,
                            .text_len = td.text_len - line_start,
                            .source_text_data_idx = td_idx,
                        });
                    }
                }
                pos += 1;
            }

            td.wrapped_lines_end = next_wrapped_line;

            // Update element height = lineHeight * number of wrapped lines
            const line_count: i32 = td.wrapped_lines_end - td.wrapped_lines_start;
            ring_buffer[@intCast(i)].dimensions_h = line_h * @as(f32, @intCast(line_count));

            std.debug.print("  text_wrap: slot {} -> {} lines, h={}\n", .{ i, line_count, ring_buffer[@intCast(i)].dimensions_h });
        }
        i += 1;
    }

    std.debug.print("--- Pass 3: text_wrap complete ---\n", .{});
}

// --- PASS 4: aspect_ratio_v ---
// Linear scan. height = width / aspect_ratio.

fn passAspectRatioV() void {
    assertDepsAndMark(BIT_ASPECT_RATIO_V, BIT_SIZE_X);

    var i: i32 = 0;
    while (i < next_slot) {
        if (configPresentAspect(i)) {
            const ar = aspect_configs[@intCast(configLookupAspect(i))];
            if (ar != 0.0) {
                ring_buffer[@intCast(i)].dimensions_h = ring_buffer[@intCast(i)].dimensions_w / ar;
                std.debug.print("  aspect_ratio_v: slot {} -> h={}\n", .{ i, ring_buffer[@intCast(i)].dimensions_h });
            }
        }
        i += 1;
    }

    std.debug.print("--- Pass 4: aspect_ratio_v complete ---\n", .{});
}

// --- PASS 5: propagate_heights ---
// DFS bottom-up. Recompute parent heights after text_wrap and aspect_ratio_v.

fn passPropagateHeights() void {
    assertDepsAndMark(BIT_PROPAGATE_HEIGHTS, BIT_TEXT_WRAP | BIT_ASPECT_RATIO_V);

    // DFS bottom-up via post-order traversal
    // Use iterative post-order: two-stack approach
    var stack1: [SLOT_COUNT]i32 = [_]i32{-1} ** SLOT_COUNT;
    var stack2: [SLOT_COUNT]i32 = [_]i32{-1} ** SLOT_COUNT;
    var s1_top: i32 = -1;
    var s2_top: i32 = -1;

    // Seed from tree roots
    var r: i32 = 0;
    while (r < next_tree_root) {
        const root_slot = tree_roots[@intCast(r)].layout_element_index;
        if (root_slot >= 0) {
            s1_top += 1;
            stack1[@intCast(s1_top)] = root_slot;
        }
        r += 1;
    }

    // Build post-order in stack2
    while (s1_top >= 0) {
        const node = stack1[@intCast(s1_top)];
        s1_top -= 1;
        s2_top += 1;
        stack2[@intCast(s2_top)] = node;

        // Push children
        var i: i32 = ring_buffer[@intCast(node)].children_start;
        while (i < ring_buffer[@intCast(node)].children_end) {
            if (isChildLive(i) and isChildNonFloating(i)) {
                s1_top += 1;
                stack1[@intCast(s1_top)] = i;
            }
            i += 1;
        }
    }

    // Process stack2 (post-order = children before parents)
    while (s2_top >= 0) {
        const slot_idx = stack2[@intCast(s2_top)];
        s2_top -= 1;

        const lc_idx = ring_buffer[@intCast(slot_idx)].layout_config_idx;
        if (lc_idx == -1) continue;
        const lc = &layout_configs[@intCast(lc_idx)];

        // Only recompute if this element has children and sizing is FIT on H
        if (lc.sizing_h_type != SIZE_FIT) continue;
        if (ring_buffer[@intCast(slot_idx)].children_start == ring_buffer[@intCast(slot_idx)].children_end) continue;

        var child_count: i32 = 0;
        var max_child_h: f32 = 0.0;
        var sum_child_h: f32 = 0.0;

        var i: i32 = ring_buffer[@intCast(slot_idx)].children_start;
        while (i < ring_buffer[@intCast(slot_idx)].children_end) {
            if (isChildLive(i) and isChildNonFloating(i)) {
                child_count += 1;
                const ch = ring_buffer[@intCast(i)].dimensions_h;
                sum_child_h += ch;
                if (ch > max_child_h) max_child_h = ch;
            }
            i += 1;
        }

        const gap_total: f32 = if (child_count > 1) lc.child_gap * @as(f32, @intCast(child_count - 1)) else 0.0;

        var new_h: f32 = if (lc.layout_direction == LAYOUT_LEFT_TO_RIGHT) {
            max_child_h + lc.padding_top + lc.padding_bottom;
        } else {
            sum_child_h + gap_total + lc.padding_top + lc.padding_bottom;
        };

        new_h = @max(@min(new_h, lc.sizing_h_max), lc.sizing_h_min);
        ring_buffer[@intCast(slot_idx)].dimensions_h = new_h;
    }

    std.debug.print("--- Pass 5: propagate_heights complete ---\n", .{});
}

// --- PASS 6: size_y ---
// BFS top-down. Same algorithm as size_x but for Y axis.

fn passSizeY() void {
    assertDepsAndMark(BIT_SIZE_Y, BIT_PROPAGATE_HEIGHTS);

    var queue: [SLOT_COUNT]i32 = [_]i32{-1} ** SLOT_COUNT;
    var q_head: i32 = 0;
    var q_tail: i32 = 0;

    var r: i32 = 0;
    while (r < next_tree_root) {
        const root_slot = tree_roots[@intCast(r)].layout_element_index;
        if (root_slot >= 0) {
            queue[@intCast(q_tail)] = root_slot;
            q_tail += 1;
        }
        r += 1;
    }

    while (q_head < q_tail) {
        const slot_idx = queue[@intCast(q_head)];
        q_head += 1;

        const lc_idx = ring_buffer[@intCast(slot_idx)].layout_config_idx;
        if (lc_idx == -1) continue;
        const lc = &layout_configs[@intCast(lc_idx)];
        const parent_h: f32 = ring_buffer[@intCast(slot_idx)].dimensions_h;

        var i: i32 = ring_buffer[@intCast(slot_idx)].children_start;
        while (i < ring_buffer[@intCast(slot_idx)].children_end) {
            if (isChildLive(i) and isChildNonFloating(i)) {
                const child_lc_idx = ring_buffer[@intCast(i)].layout_config_idx;
                if (child_lc_idx == -1) {
                    i += 1;
                    continue;
                }
                const child_lc = &layout_configs[@intCast(child_lc_idx)];
                const content_h: f32 = parent_h - lc.padding_top - lc.padding_bottom;

                if (lc.layout_direction == LAYOUT_TOP_TO_BOTTOM) {
                    // Along axis (Y for TOP_TO_BOTTOM)
                    switch (child_lc.sizing_h_type) {
                        SIZE_FIXED => {
                            ring_buffer[@intCast(i)].dimensions_h = child_lc.sizing_h_min;
                        },
                        SIZE_PERCENT => {
                            var nfc: i32 = 0;
                            var j: i32 = ring_buffer[@intCast(slot_idx)].children_start;
                            while (j < ring_buffer[@intCast(slot_idx)].children_end) {
                                if (isChildLive(j) and isChildNonFloating(j)) nfc += 1;
                                j += 1;
                            }
                            const gap_total: f32 = if (nfc > 1) lc.child_gap * @as(f32, @intCast(nfc - 1)) else 0.0;
                            ring_buffer[@intCast(i)].dimensions_h = (content_h - gap_total) * child_lc.sizing_h_percent;
                        },
                        SIZE_GROW => {
                            var non_grow_sum: f32 = 0.0;
                            var grow_count: i32 = 0;
                            var nfc2: i32 = 0;
                            var j2: i32 = ring_buffer[@intCast(slot_idx)].children_start;
                            while (j2 < ring_buffer[@intCast(slot_idx)].children_end) {
                                if (isChildLive(j2) and isChildNonFloating(j2)) {
                                    nfc2 += 1;
                                    const cj_lc_idx = ring_buffer[@intCast(j2)].layout_config_idx;
                                    if (cj_lc_idx != -1) {
                                        const cj_lc = &layout_configs[@intCast(cj_lc_idx)];
                                        if (cj_lc.sizing_h_type == SIZE_GROW) {
                                            grow_count += 1;
                                        } else {
                                            non_grow_sum += ring_buffer[@intCast(j2)].dimensions_h;
                                        }
                                    }
                                }
                                j2 += 1;
                            }
                            const gap_total2: f32 = if (nfc2 > 1) lc.child_gap * @as(f32, @intCast(nfc2 - 1)) else 0.0;
                            const remaining: f32 = content_h - gap_total2 - non_grow_sum;
                            if (grow_count > 0 and remaining > 0) {
                                var grown: f32 = remaining / @as(f32, @intCast(grow_count));
                                grown = @max(grown, child_lc.sizing_h_min);
                                grown = @min(grown, child_lc.sizing_h_max);
                                ring_buffer[@intCast(i)].dimensions_h = grown;
                            }
                        },
                        else => {}, // FIT already set
                    }
                } else {
                    // Off axis (Y for LEFT_TO_RIGHT)
                    switch (child_lc.sizing_h_type) {
                        SIZE_GROW => {
                            ring_buffer[@intCast(i)].dimensions_h = @max(@min(content_h, child_lc.sizing_h_max), child_lc.sizing_h_min);
                        },
                        SIZE_PERCENT => {
                            ring_buffer[@intCast(i)].dimensions_h = @max(@min(content_h * child_lc.sizing_h_percent, child_lc.sizing_h_max), child_lc.sizing_h_min);
                        },
                        SIZE_FIT => {
                            ring_buffer[@intCast(i)].dimensions_h = @max(@min(ring_buffer[@intCast(i)].dimensions_h, child_lc.sizing_h_max), child_lc.sizing_h_min);
                        },
                        else => {},
                    }
                }

                queue[@intCast(q_tail)] = i;
                q_tail += 1;
            }
            i += 1;
        }
    }

    std.debug.print("--- Pass 6: size_y complete ---\n", .{});
}

// --- PASS 7: aspect_ratio_h ---
// Linear scan. width = aspect_ratio * height.

fn passAspectRatioH() void {
    assertDepsAndMark(BIT_ASPECT_RATIO_H, BIT_SIZE_Y);

    var i: i32 = 0;
    while (i < next_slot) {
        if (configPresentAspect(i)) {
            const ar = aspect_configs[@intCast(configLookupAspect(i))];
            if (ar != 0.0) {
                // Only write if aspect was used in V pass (height was derived from width).
                // In H pass, width = ratio * height. This is the mirror.
                // For our test, aspect_ratio_v already set h = w/ratio.
                // aspect_ratio_h would override w = ratio * h, which is a no-op
                // if h was already derived from w. We write it for completeness.
                ring_buffer[@intCast(i)].dimensions_w = ar * ring_buffer[@intCast(i)].dimensions_h;
                std.debug.print("  aspect_ratio_h: slot {} -> w={}\n", .{ i, ring_buffer[@intCast(i)].dimensions_w });
            }
        }
        i += 1;
    }

    std.debug.print("--- Pass 7: aspect_ratio_h complete ---\n", .{});
}

// --- PASS 8: sort_z ---
// Bubble sort tree_roots by z_index ascending.

fn passSortZ() void {
    assertDepsAndMark(BIT_SORT_Z, BIT_SIZE_Y);

    // Bubble sort — progressive, correct for near-sorted input
    var swapped: bool = true;
    while (swapped) {
        swapped = false;
        var i: i32 = 0;
        while (i < next_tree_root - 1) {
            if (tree_roots[@intCast(i)].z_index > tree_roots[@intCast(i + 1)].z_index) {
                const tmp = tree_roots[@intCast(i)];
                tree_roots[@intCast(i)] = tree_roots[@intCast(i + 1)];
                tree_roots[@intCast(i + 1)] = tmp;
                swapped = true;
            }
            i += 1;
        }
    }

    std.debug.print("--- Pass 8: sort_z complete. Tree roots sorted: ", .{});
    var r: i32 = 0;
    while (r < next_tree_root) {
        std.debug.print("[slot={} z={}] ", .{ tree_roots[@intCast(r)].layout_element_index, tree_roots[@intCast(r)].z_index });
        r += 1;
    }
    std.debug.print("---\n", .{});
}

// --- PASS 9: final_layout ---
// DFS top-down per tree root, in sorted z-order.
// Manual stack. Children pushed in reverse order.
// Two-visit: down (first) and up (second).

const DFS_VISIT_DOWN: i32 = 0;
const DFS_VISIT_UP: i32 = 1;

const DFSEntry = struct {
    slot_idx: i32 = -1,
    visit: i32 = DFS_VISIT_DOWN,
    parent_bbox_x: f32 = 0.0,
    parent_bbox_y: f32 = 0.0,
    next_child_offset_x: f32 = 0.0,
    next_child_offset_y: f32 = 0.0,
    scroll_offset_x: f32 = 0.0,
    scroll_offset_y: f32 = 0.0,
};

fn resolveAttachPoint(attach_idx: i32, bbox_x: f32, bbox_y: f32, bbox_w: f32, bbox_h: f32) struct { x: f32, y: f32 } {
    // 9 attach points:
    // 0=left_top  1=left_center  2=left_bottom
    // 3=center_top 4=center_center 5=center_bottom
    // 6=right_top 7=right_center 8=right_bottom
    const col = attach_idx % 3; // 0=left, 1=center, 2=right
    const row = attach_idx / 3; // 0=top, 1=center, 2=bottom
    const x: f32 = switch (col) {
        0 => bbox_x,
        1 => bbox_x + bbox_w * 0.5,
        else => bbox_x + bbox_w,
    };
    const y: f32 = switch (row) {
        0 => bbox_y,
        1 => bbox_y + bbox_h * 0.5,
        else => bbox_y + bbox_h,
    };
    return .{ .x = x, .y = y };
}

fn resolveElementAttachOffset(attach_idx: i32, dim_w: f32, dim_h: f32) struct { x: f32, y: f32 } {
    const col = attach_idx % 3;
    const row = attach_idx / 3;
    const x: f32 = switch (col) {
        0 => 0.0,
        1 => dim_w * 0.5,
        else => dim_w,
    };
    const y: f32 = switch (row) {
        0 => 0.0,
        1 => dim_h * 0.5,
        else => dim_h,
    };
    return .{ .x = x, .y = y };
}

fn isCulled(bbox_x: f32, bbox_y: f32, bbox_w: f32, bbox_h: f32) bool {
    return bbox_x > layout_width or
        bbox_y > layout_height or
        bbox_x + bbox_w < 0.0 or
        bbox_y + bbox_h < 0.0;
}

fn passFinalLayout() void {
    assertDepsAndMark(BIT_FINAL_LAYOUT, BIT_ASPECT_RATIO_H | BIT_SORT_Z);

    var dfs_stack: [SLOT_COUNT]DFSEntry = [_]DFSEntry{DFSEntry{}} ** SLOT_COUNT;
    var dfs_top: i32 = -1;

    // Process each tree root in sorted z-order
    var r: i32 = 0;
    while (r < next_tree_root) {
        const root_slot = tree_roots[@intCast(r)].layout_element_index;
        if (root_slot < 0) {
            r += 1;
            continue;
        }

        // Determine if this is a floating root (has floating config)
        const is_floating_root: bool = configPresentFloating(root_slot);

        // Seed DFS
        dfs_top = 0;
        dfs_stack[0] = DFSEntry{
            .slot_idx = root_slot,
            .visit = DFS_VISIT_DOWN,
            .parent_bbox_x = 0.0,
            .parent_bbox_y = 0.0,
            .next_child_offset_x = 0.0,
            .next_child_offset_y = 0.0,
            .scroll_offset_x = 0.0,
            .scroll_offset_y = 0.0,
        };

        while (dfs_top >= 0) {
            const entry = dfs_stack[@intCast(dfs_top)];
            dfs_top -= 1;
            const slot_idx = entry.slot_idx;

            if (entry.visit == DFS_VISIT_DOWN) {
                // --- FIRST VISIT: going down ---

                var bbox_x: f32 = entry.parent_bbox_x + entry.next_child_offset_x + entry.scroll_offset_x;
                var bbox_y: f32 = entry.parent_bbox_y + entry.next_child_offset_y + entry.scroll_offset_y;
                var bbox_w: f32 = ring_buffer[@intCast(slot_idx)].dimensions_w;
                var bbox_h: f32 = ring_buffer[@intCast(slot_idx)].dimensions_h;

                // Floating element positioning
                if (is_floating_root and slot_idx == root_slot) {
                    const fc_idx = configLookupFloating(slot_idx);
                    const fc = &floating_configs[@intCast(fc_idx)];

                    // Step 1: resolve target bbox
                    var target_bbox_x: f32 = 0.0;
                    var target_bbox_y: f32 = 0.0;
                    var target_bbox_w: f32 = layout_width;
                    var target_bbox_h: f32 = layout_height;

                    if (fc.attach_to == 1) {
                        // Parent — use parent on stack (not available here simply, use parent_slot_idx)
                        const parent_slot = ring_buffer[@intCast(slot_idx)].parent_slot_idx;
                        if (parent_slot >= 0) {
                            target_bbox_x = ring_buffer[@intCast(parent_slot)].bbox_x;
                            target_bbox_y = ring_buffer[@intCast(parent_slot)].bbox_y;
                            target_bbox_w = ring_buffer[@intCast(parent_slot)].bbox_w;
                            target_bbox_h = ring_buffer[@intCast(parent_slot)].bbox_h;
                        }
                    } else if (fc.attach_to == 2) {
                        // element_with_id — hash lookup
                        const target_slot = hashChainWalk(fc.parent_id);
                        if (target_slot >= 0) {
                            target_bbox_x = ring_buffer[@intCast(target_slot)].bbox_x;
                            target_bbox_y = ring_buffer[@intCast(target_slot)].bbox_y;
                            target_bbox_w = ring_buffer[@intCast(target_slot)].bbox_w;
                            target_bbox_h = ring_buffer[@intCast(target_slot)].bbox_h;
                        }
                    }
                    // attach_to == 3 (root) — already set to layout dimensions

                    // Step 1: resolve parent attach point
                    const parent_pt = resolveAttachPoint(fc.attach_parent, target_bbox_x, target_bbox_y, target_bbox_w, target_bbox_h);

                    // Step 2: subtract element attach offset
                    const elem_off = resolveElementAttachOffset(fc.attach_element, bbox_w, bbox_h);

                    // Step 3: add config offset
                    bbox_x = parent_pt.x - elem_off.x + fc.offset_x;
                    bbox_y = parent_pt.y - elem_off.y + fc.offset_y;

                    // Expand bbox symmetrically (does not affect children)
                    bbox_x -= fc.expand_w;
                    bbox_y -= fc.expand_h;
                    bbox_w += fc.expand_w * 2.0;
                    bbox_h += fc.expand_h * 2.0;
                }

                // Write bbox
                ring_buffer[@intCast(slot_idx)].bbox_x = bbox_x;
                ring_buffer[@intCast(slot_idx)].bbox_y = bbox_y;
                ring_buffer[@intCast(slot_idx)].bbox_w = bbox_w;
                ring_buffer[@intCast(slot_idx)].bbox_h = bbox_h;

                // Scroll offset for children
                var scroll_x: f32 = entry.scroll_offset_x;
                var scroll_y: f32 = entry.scroll_offset_y;
                if (configPresentClip(slot_idx)) {
                    const cc_idx = configLookupClip(slot_idx);
                    scroll_x += clip_configs[@intCast(cc_idx)].child_offset_x;
                    scroll_y += clip_configs[@intCast(cc_idx)].child_offset_y;
                }

                // Culling check
                const culled = isCulled(bbox_x, bbox_y, bbox_w, bbox_h);

                if (!culled) {
                    // Emit render commands — DOWN order
                    // SCISSOR_START
                    if (configPresentClip(slot_idx)) {
                        emitRenderCommand(RenderCommand{
                            .cmd_type = CMD_SCISSOR_START,
                            .x = bbox_x,
                            .y = bbox_y,
                            .w = bbox_w,
                            .h = bbox_h,
                            .slot_id = ring_buffer[@intCast(slot_idx)].id,
                        });
                    }
                    // RECTANGLE (background)
                    if (configPresentShared(slot_idx)) {
                        const sc = &shared_configs[@intCast(configLookupShared(slot_idx))];
                        if (sc.bg_a > 0.0) {
                            emitRenderCommand(RenderCommand{
                                .cmd_type = CMD_RECTANGLE,
                                .x = bbox_x,
                                .y = bbox_y,
                                .w = bbox_w,
                                .h = bbox_h,
                                .color_r = sc.bg_r,
                                .color_g = sc.bg_g,
                                .color_b = sc.bg_b,
                                .color_a = sc.bg_a,
                                .corner_tl = sc.corner_tl,
                                .corner_tr = sc.corner_tr,
                                .corner_bl = sc.corner_bl,
                                .corner_br = sc.corner_br,
                                .slot_id = ring_buffer[@intCast(slot_idx)].id,
                            });
                        }
                    }
                    // IMAGE
                    if (configPresentImage(slot_idx)) {
                        emitRenderCommand(RenderCommand{
                            .cmd_type = CMD_IMAGE,
                            .x = bbox_x,
                            .y = bbox_y,
                            .w = bbox_w,
                            .h = bbox_h,
                            .slot_id = ring_buffer[@intCast(slot_idx)].id,
                        });
                    }
                    // TEXT — one per wrapped line
                    if (ring_buffer[@intCast(slot_idx)].text_data_idx != -1) {
                        const td_idx = ring_buffer[@intCast(slot_idx)].text_data_idx;
                        const td = &text_data[@intCast(td_idx)];
                        var line_y: f32 = bbox_y;
                        var wl: i32 = td.wrapped_lines_start;
                        while (wl < td.wrapped_lines_end) {
                            const wline = &wrapped_lines[@intCast(wl)];
                            emitRenderCommand(RenderCommand{
                                .cmd_type = CMD_TEXT,
                                .x = bbox_x,
                                .y = line_y,
                                .w = wline.dim_w,
                                .h = wline.dim_h,
                                .text_data_idx = td_idx,
                                .wrapped_line_idx = wl,
                                .slot_id = ring_buffer[@intCast(slot_idx)].id,
                            });
                            line_y += wline.dim_h;
                            wl += 1;
                        }
                    }
                    // CUSTOM
                    if (configPresentCustom(slot_idx)) {
                        emitRenderCommand(RenderCommand{
                            .cmd_type = CMD_CUSTOM,
                            .x = bbox_x,
                            .y = bbox_y,
                            .w = bbox_w,
                            .h = bbox_h,
                            .slot_id = ring_buffer[@intCast(slot_idx)].id,
                        });
                    }
                }

                // Push UP visit for this node (will be processed after all children)
                dfs_top += 1;
                dfs_stack[@intCast(dfs_top)] = DFSEntry{
                    .slot_idx = slot_idx,
                    .visit = DFS_VISIT_UP,
                    .parent_bbox_x = bbox_x,
                    .parent_bbox_y = bbox_y,
                    .scroll_offset_x = scroll_x,
                    .scroll_offset_y = scroll_y,
                };

                // Push children in REVERSE order
                const lc_idx = ring_buffer[@intCast(slot_idx)].layout_config_idx;
                if (lc_idx != -1) {
                    const lc = &layout_configs[@intCast(lc_idx)];

                    // First pass: collect live non-floating children and compute offsets
                    // We need reverse order, so collect indices first
                    var child_indices: [256]i32 = [_]i32{-1} ** 256;
                    var child_count: i32 = 0;
                    var ci: i32 = ring_buffer[@intCast(slot_idx)].children_start;
                    while (ci < ring_buffer[@intCast(slot_idx)].children_end) {
                        if (isChildLive(ci) and isChildNonFloating(ci)) {
                            child_indices[@intCast(child_count)] = ci;
                            child_count += 1;
                        }
                        ci += 1;
                    }

                    // Compute child offsets forward, push in reverse
                    var offset_x: f32 = lc.padding_left;
                    var offset_y: f32 = lc.padding_top;

                    // Pre-compute all offsets
                    var offsets_x: [256]f32 = [_]f32{0.0} ** 256;
                    var offsets_y: [256]f32 = [_]f32{0.0} ** 256;
                    var oi: i32 = 0;
                    while (oi < child_count) {
                        offsets_x[@intCast(oi)] = offset_x;
                        offsets_y[@intCast(oi)] = offset_y;
                        const child_idx = child_indices[@intCast(oi)];
                        if (lc.layout_direction == LAYOUT_LEFT_TO_RIGHT) {
                            offset_x += ring_buffer[@intCast(child_idx)].dimensions_w + lc.child_gap;
                        } else {
                            offset_y += ring_buffer[@intCast(child_idx)].dimensions_h + lc.child_gap;
                        }
                        oi += 1;
                    }

                    // Push in reverse
                    var pi: i32 = child_count - 1;
                    while (pi >= 0) {
                        dfs_top += 1;
                        dfs_stack[@intCast(dfs_top)] = DFSEntry{
                            .slot_idx = child_indices[@intCast(pi)],
                            .visit = DFS_VISIT_DOWN,
                            .parent_bbox_x = bbox_x,
                            .parent_bbox_y = bbox_y,
                            .next_child_offset_x = offsets_x[@intCast(pi)],
                            .next_child_offset_y = offsets_y[@intCast(pi)],
                            .scroll_offset_x = scroll_x,
                            .scroll_offset_y = scroll_y,
                        };
                        pi -= 1;
                    }
                }
            } else {
                // --- SECOND VISIT: going up ---
                const bbox_x = ring_buffer[@intCast(slot_idx)].bbox_x;
                const bbox_y = ring_buffer[@intCast(slot_idx)].bbox_y;
                const bbox_w = ring_buffer[@intCast(slot_idx)].bbox_w;
                const bbox_h = ring_buffer[@intCast(slot_idx)].bbox_h;
                const culled = isCulled(bbox_x, bbox_y, bbox_w, bbox_h);

                if (!culled) {
                    // BORDER
                    if (configPresentBorder(slot_idx)) {
                        const bc = &border_configs[@intCast(configLookupBorder(slot_idx))];
                        emitRenderCommand(RenderCommand{
                            .cmd_type = CMD_BORDER,
                            .x = bbox_x,
                            .y = bbox_y,
                            .w = bbox_w,
                            .h = bbox_h,
                            .color_r = bc.color_r,
                            .color_g = bc.color_g,
                            .color_b = bc.color_b,
                            .color_a = bc.color_a,
                            .border_left = bc.left,
                            .border_right = bc.right,
                            .border_top = bc.top,
                            .border_bottom = bc.bottom,
                            .slot_id = ring_buffer[@intCast(slot_idx)].id,
                        });

                        // Between-children borders
                        if (bc.between > 0 and bc.color_a > 0.0) {
                            const lc_idx = ring_buffer[@intCast(slot_idx)].layout_config_idx;
                            if (lc_idx != -1) {
                                const lc = &layout_configs[@intCast(lc_idx)];
                                var child_count: i32 = 0;
                                var border_offset_x: f32 = lc.padding_left;
                                var border_offset_y: f32 = lc.padding_top;
                                var first: bool = true;

                                var ci: i32 = ring_buffer[@intCast(slot_idx)].children_start;
                                while (ci < ring_buffer[@intCast(slot_idx)].children_end) {
                                    if (isChildLive(ci) and isChildNonFloating(ci)) {
                                        if (!first) {
                                            // Emit between-children rectangle
                                            if (lc.layout_direction == LAYOUT_LEFT_TO_RIGHT) {
                                                emitRenderCommand(RenderCommand{
                                                    .cmd_type = CMD_RECTANGLE,
                                                    .x = bbox_x + border_offset_x - @as(f32, @intCast(bc.between)) * 0.5,
                                                    .y = bbox_y,
                                                    .w = @as(f32, @intCast(bc.between)),
                                                    .h = bbox_h,
                                                    .color_r = bc.color_r,
                                                    .color_g = bc.color_g,
                                                    .color_b = bc.color_b,
                                                    .color_a = bc.color_a,
                                                    .slot_id = ring_buffer[@intCast(slot_idx)].id,
                                                });
                                            } else {
                                                emitRenderCommand(RenderCommand{
                                                    .cmd_type = CMD_RECTANGLE,
                                                    .x = bbox_x,
                                                    .y = bbox_y + border_offset_y - @as(f32, @intCast(bc.between)) * 0.5,
                                                    .w = bbox_w,
                                                    .h = @as(f32, @intCast(bc.between)),
                                                    .color_r = bc.color_r,
                                                    .color_g = bc.color_g,
                                                    .color_b = bc.color_b,
                                                    .color_a = bc.color_a,
                                                    .slot_id = ring_buffer[@intCast(slot_idx)].id,
                                                });
                                            }
                                        }
                                        first = false;
                                        child_count += 1;
                                        if (lc.layout_direction == LAYOUT_LEFT_TO_RIGHT) {
                                            border_offset_x += ring_buffer[@intCast(ci)].dimensions_w + lc.child_gap;
                                        } else {
                                            border_offset_y += ring_buffer[@intCast(ci)].dimensions_h + lc.child_gap;
                                        }
                                    }
                                    ci += 1;
                                }
                                // _ = child_count; // used implicitly
                            }
                        }
                    }

                    // SCISSOR_END
                    if (configPresentClip(slot_idx)) {
                        emitRenderCommand(RenderCommand{
                            .cmd_type = CMD_SCISSOR_END,
                            .slot_id = ring_buffer[@intCast(slot_idx)].id,
                        });
                    }
                }
            }
        }

        r += 1;
    }

    std.debug.print("--- Pass 9: final_layout complete. {} render commands ---\n", .{next_render_cmd});
}

// --- PASS 0: pointer_detection ---
// Reverse z-order traversal. Hit test against previous frame bboxes.

fn passPointerDetection(pointer_x: f32, pointer_y: f32, pointer_down: bool) void {
    assertDepsAndMark(BIT_POINTER_DETECTION, BIT_FINAL_LAYOUT);

    // Pointer state machine
    pointer_state = switch (pointer_state) {
        PTR_RELEASED => if (pointer_down) PTR_PRESSED_THIS_FRAME else PTR_RELEASED,
        PTR_PRESSED_THIS_FRAME => if (pointer_down) PTR_PRESSED else PTR_RELEASED_THIS_FRAME,
        PTR_PRESSED => if (!pointer_down) PTR_RELEASED_THIS_FRAME else PTR_PRESSED,
        PTR_RELEASED_THIS_FRAME => if (!pointer_down) PTR_RELEASED else PTR_PRESSED_THIS_FRAME,
        else => PTR_RELEASED,
    };

    pointer_over_write_head = 0;

    // Traverse tree roots in REVERSE z-order (highest z first)
    var r: i32 = next_tree_root - 1;
    while (r >= 0) {
        const root_slot = tree_roots[@intCast(r)].layout_element_index;
        if (root_slot < 0) {
            r -= 1;
            continue;
        }

        // DFS per root
        var dfs_stack: [SLOT_COUNT]i32 = [_]i32{-1} ** SLOT_COUNT;
        var dfs_top: i32 = 0;
        dfs_stack[0] = root_slot;
        var captured: bool = false;

        while (dfs_top >= 0) {
            const slot_idx = dfs_stack[@intCast(dfs_top)];
            dfs_top -= 1;

            // Hit test
            const bx = ring_buffer[@intCast(slot_idx)].bbox_x;
            const by = ring_buffer[@intCast(slot_idx)].bbox_y;
            const bw = ring_buffer[@intCast(slot_idx)].bbox_w;
            const bh = ring_buffer[@intCast(slot_idx)].bbox_h;

            var hit: bool = pointer_x >= bx and pointer_x < bx + bw and
                pointer_y >= by and pointer_y < by + bh;

            // Clip container check
            if (hit) {
                const clip_id = tree_roots[@intCast(r)].clip_element_id;
                if (clip_id != -1) {
                    const clip_slot = hashChainWalk(clip_id);
                    if (clip_slot >= 0) {
                        const cx = ring_buffer[@intCast(clip_slot)].bbox_x;
                        const cy = ring_buffer[@intCast(clip_slot)].bbox_y;
                        const cw = ring_buffer[@intCast(clip_slot)].bbox_w;
                        const ch = ring_buffer[@intCast(clip_slot)].bbox_h;
                        if (pointer_x < cx or pointer_x >= cx + cw or pointer_y < cy or pointer_y >= cy + ch) {
                            hit = false;
                        }
                    }
                }
            }

            if (hit) {
                // Record in pointer_over_ids
                pointer_over_ids[@intCast(pointer_over_write_head)] = ring_buffer[@intCast(slot_idx)].id;
                pointer_over_write_head = (pointer_over_write_head + 1) % @as(i32, POINTER_OVER_COUNT);
                std.debug.assert(pointer_over_write_head != 0 or true); // debug assertion placeholder

                // Check capture on floating root
                if (slot_idx == root_slot and configPresentFloating(slot_idx)) {
                    const fc_idx = configLookupFloating(slot_idx);
                    if (floating_configs[@intCast(fc_idx)].capture_mode == 0) {
                        captured = true;
                    }
                }
            }

            // Push children (continue traversal regardless of hit)
            var ci: i32 = ring_buffer[@intCast(slot_idx)].children_start;
            while (ci < ring_buffer[@intCast(slot_idx)].children_end) {
                if (isChildLive(ci)) {
                    dfs_top += 1;
                    dfs_stack[@intCast(dfs_top)] = ci;
                }
                ci += 1;
            }
        }

        if (captured) break; // capture mode stops root traversal

        r -= 1;
    }

    std.debug.print("--- Pass 0: pointer_detection complete. state={}, hits: ", .{pointer_state});
    var pi: i32 = 0;
    while (pi < pointer_over_write_head) {
        std.debug.print("{} ", .{pointer_over_ids[@intCast(pi)]});
        pi += 1;
    }
    std.debug.print("---\n", .{});
}

// ============================================================
// PHASE 9: RENDER COMMAND OUTPUT + FULL TEST RUNNER
// ============================================================

const cmd_names = [_][]const u8{
    "SCISSOR_START",
    "RECTANGLE",
    "IMAGE",
    "TEXT",
    "CUSTOM",
    "BORDER",
    "SCISSOR_END",
};

fn printRenderCommands() void {
    std.debug.print("\n=== RENDER COMMANDS ===\n", .{});
    var i: i32 = 0;
    while (i < next_render_cmd) {
        const cmd = &render_commands[@intCast(i)];
        const name = cmd_names[@intCast(cmd.cmd_type)];
        std.debug.print("[{d:3}] {s:14} id={d:4} pos=({d:.1},{d:.1}) dim=({d:.1},{d:.1})", .{ i, name, cmd.slot_id, cmd.x, cmd.y, cmd.w, cmd.h });
        if (cmd.cmd_type == CMD_RECTANGLE or cmd.cmd_type == CMD_BORDER) {
            std.debug.print(" rgba=({d:.2},{d:.2},{d:.2},{d:.2})", .{ cmd.color_r, cmd.color_g, cmd.color_b, cmd.color_a });
        }
        if (cmd.cmd_type == CMD_BORDER) {
            std.debug.print(" border=L{}R{}T{}B{}", .{ cmd.border_left, cmd.border_right, cmd.border_top, cmd.border_bottom });
        }
        if (cmd.cmd_type == CMD_TEXT) {
            std.debug.print(" td={} wl={}", .{ cmd.text_data_idx, cmd.wrapped_line_idx });
        }
        std.debug.print("\n", .{});
        i += 1;
    }
    std.debug.print("=== END RENDER COMMANDS ===\n\n", .{});
}

fn printSlotState() void {
    std.debug.print("\n=== SLOT STATE ===\n", .{});
    var i: i32 = 0;
    while (i < next_slot) {
        const s = &ring_buffer[@intCast(i)];
        if (s.state == STATE_LIVE) {
            std.debug.print("slot[{d:2}] id={d:4} dim=({d:7.1},{d:7.1}) bbox=({d:7.1},{d:7.1},{d:7.1},{d:7.1}) children=[{d},{d}) clip_id={d}\n", .{ i, s.id, s.dimensions_w, s.dimensions_h, s.bbox_x, s.bbox_y, s.bbox_w, s.bbox_h, s.children_start, s.children_end, s.clip_element_id });
        }
        i += 1;
    }
    std.debug.print("=== END SLOT STATE ===\n\n", .{});
}

pub fn main() void {
    std.debug.print("============================================================\n", .{});
    std.debug.print("  Clay Layout Engine — Zero-Pointer Ring Buffer Test\n", .{});
    std.debug.print("============================================================\n\n", .{});

    // Run all passes in canonical order
    passDeclaration(); // Pass 1
    passSizeX(); // Pass 2
    passTextWrap(); // Pass 3
    passAspectRatioV(); // Pass 4
    passPropagateHeights(); // Pass 5
    passSizeY(); // Pass 6
    passAspectRatioH(); // Pass 7
    passSortZ(); // Pass 8
    passFinalLayout(); // Pass 9

    // Print intermediate state
    printSlotState();
    printRenderCommands();

    // Run pointer detection with test point inside element 300 (green square)
    // Element 300 should be at approximately (10+10, 10+10) = (20,20) with size 50x50
    // So test point (40, 40) should hit it
    passes_completed = passes_completed; // keep completed flags
    passPointerDetection(40.0, 40.0, false); // Pass 0

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("  Test complete.\n", .{});
    std.debug.print("============================================================\n", .{});
}
