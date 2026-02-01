const std = @import("std");

const pass = @import("pass.zig");
const RenderCommand = pass.RenderCommand;
const LayoutConfig = pass.LayoutConfig;
const SharedConfig = pass.SharedConfig;
const BorderConfig = pass.BorderConfig;
const FloatingConfig = pass.FloatingConfig;
const TextConfig = pass.TextConfig;
const ClipConfig = pass.ClipConfig;

// --- Allocate helpers for configs ---

fn emitRenderCommand(cmd: RenderCommand) void {
    pass.render_commands[@intCast(pass.next_render_cmd)] = cmd;
    pass.next_render_cmd += 1;
}

// --- Declaration helpers: open / close element ---

fn elementOpen(id: i32, layout: LayoutConfig, shared: ?SharedConfig, border: ?BorderConfig, clip: ?ClipConfig) i32 {
    const slot_idx = pass.allocSlot();
    pass.ring_buffer[@intCast(slot_idx)].id = id;
    pass.ring_buffer[@intCast(slot_idx)].state = pass.STATE_LIVE;
    pass.ring_buffer[@intCast(slot_idx)].layout_config_idx = pass.allocLayoutConfig(layout);
    pass.ring_buffer[@intCast(slot_idx)].children_start = pass.next_slot; // children will follow

    if (shared) |s| {
        pass.ring_buffer[@intCast(slot_idx)].config_shared = pass.allocSharedConfig(s);
    }
    if (border) |b| {
        pass.ring_buffer[@intCast(slot_idx)].config_border = pass.allocBorderConfig(b);
    }
    if (clip) |c| {
        pass.ring_buffer[@intCast(slot_idx)].config_clip = pass.allocClipConfig(c);
    }

    // Inherit clip_element_id from parent
    if (pass.decl_stack_top >= 0) {
        const parent_idx = pass.decl_stack[@intCast(pass.decl_stack_top)];
        pass.ring_buffer[@intCast(slot_idx)].parent_slot_idx = parent_idx;
        // If this element IS a clip container, it becomes its own clip_element_id
        if (pass.ring_buffer[@intCast(slot_idx)].config_clip != -1) {
            pass.ring_buffer[@intCast(slot_idx)].clip_element_id = id;
        } else {
            pass.ring_buffer[@intCast(slot_idx)].clip_element_id = pass.ring_buffer[@intCast(parent_idx)].clip_element_id;
        }
    } else {
        // Root element
        if (pass.ring_buffer[@intCast(slot_idx)].config_clip != -1) {
            pass.ring_buffer[@intCast(slot_idx)].clip_element_id = id;
        }
    }

    // Push onto declaration stack
    pass.decl_stack_top += 1;
    pass.decl_stack[@intCast(pass.decl_stack_top)] = slot_idx;

    // Hash insert
    _ = pass.hashInsert(id, slot_idx);

    return slot_idx;
}

// Replacement elementClose — identical logic, no changes needed here.
// The close itself is correct. The iteration is what was wrong.
// This is included for completeness so you have the full function.
fn elementClose() void {
    const slot_idx = pass.decl_stack[@intCast(pass.decl_stack_top)];
    pass.decl_stack_top -= 1;

    pass.ring_buffer[@intCast(slot_idx)].children_end = pass.next_slot;

    const lc_idx = pass.ring_buffer[@intCast(slot_idx)].layout_config_idx;
    const lc = &pass.layout_configs[@intCast(lc_idx)];

    var fit_w: f32 = lc.padding_left + lc.padding_right;
    var fit_h: f32 = lc.padding_top + lc.padding_bottom;
    var child_count: i32 = 0;
    var max_child_w: f32 = 0.0;
    var max_child_h: f32 = 0.0;
    var sum_child_w: f32 = 0.0;
    var sum_child_h: f32 = 0.0;

    var i: i32 = pass.ring_buffer[@intCast(slot_idx)].children_start;
    while (i < pass.ring_buffer[@intCast(slot_idx)].children_end) {
        if (pass.isChildLive(i)) {
            if (pass.configPresentFloating(i)) {
                pass.ring_buffer[@intCast(slot_idx)].floating_children_count += 1;
                const fc_idx = pass.configLookupFloating(i);
                const fc = &pass.floating_configs[@intCast(fc_idx)];
                _ = pass.allocTreeRoot(pass.TreeRoot{
                    .layout_element_index = i,
                    .parent_id = fc.parent_id,
                    .clip_element_id = pass.ring_buffer[@intCast(i)].clip_element_id,
                    .z_index = fc.z_index,
                });
            } else {
                child_count += 1;
                const cw = pass.ring_buffer[@intCast(i)].dimensions_w;
                const ch = pass.ring_buffer[@intCast(i)].dimensions_h;
                sum_child_w += cw;
                sum_child_h += ch;
                if (cw > max_child_w) max_child_w = cw;
                if (ch > max_child_h) max_child_h = ch;
            }
        }
        i = pass.nextSibling(i);
    }

    const gap_total: f32 = if (child_count > 1) lc.child_gap * @as(f32, @intCast(child_count - 1)) else 0.0;

    if (lc.layout_direction == pass.LAYOUT_LEFT_TO_RIGHT) {
        fit_w += sum_child_w + gap_total;
        fit_h += max_child_h;
    } else {
        fit_h += sum_child_h + gap_total;
        fit_w += max_child_w;
    }

    if (lc.sizing_w_type == pass.SIZE_FIT) {
        pass.ring_buffer[@intCast(slot_idx)].dimensions_w = fit_w;
    }
    if (lc.sizing_h_type == pass.SIZE_FIT) {
        pass.ring_buffer[@intCast(slot_idx)].dimensions_h = fit_h;
    }
}

fn elementOpenFloating(id: i32, layout: LayoutConfig, float_cfg: FloatingConfig, shared: ?SharedConfig) i32 {
    const slot_idx = elementOpen(id, layout, shared, null, null);
    pass.ring_buffer[@intCast(slot_idx)].config_floating = pass.allocFloatingConfig(float_cfg);
    return slot_idx;
}

fn elementOpenText(id: i32, layout: LayoutConfig, text: []const u8, text_cfg: TextConfig, shared: ?SharedConfig) i32 {
    const slot_idx = elementOpen(id, layout, shared, null, null);
    pass.ring_buffer[@intCast(slot_idx)].config_text = pass.allocTextConfig(text_cfg);
    pass.ring_buffer[@intCast(slot_idx)].text_data_idx = pass.allocTextData(text, slot_idx);
    return slot_idx;
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
    const col = @mod(attach_idx, 3); // 0=left, 1=center, 2=right
    const row = @divTrunc(attach_idx, 3); // 0=top, 1=center, 2=bottom
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
    const col = @mod(attach_idx, 3);
    const row = @divTrunc(attach_idx, 3);
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
    return bbox_x > pass.layout_width or
        bbox_y > pass.layout_height or
        bbox_x + bbox_w < 0.0 or
        bbox_y + bbox_h < 0.0;
}

fn passFinalLayout() void {
    pass.assertDepsAndMark(pass.BIT_FINAL_LAYOUT, pass.BIT_ASPECT_RATIO_H | pass.BIT_SORT_Z);

    var dfs_stack: [pass.SLOT_COUNT]DFSEntry = [_]DFSEntry{DFSEntry{}} ** pass.SLOT_COUNT;
    var dfs_top: i32 = -1;

    var r: i32 = 0;
    while (r < pass.next_tree_root) {
        const root_slot = pass.tree_roots[@intCast(r)].layout_element_index;
        if (root_slot < 0) {
            r += 1;
            continue;
        }

        const is_floating_root: bool = pass.configPresentFloating(root_slot);

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
                var bbox_x: f32 = entry.parent_bbox_x + entry.next_child_offset_x + entry.scroll_offset_x;
                var bbox_y: f32 = entry.parent_bbox_y + entry.next_child_offset_y + entry.scroll_offset_y;
                var bbox_w: f32 = pass.ring_buffer[@intCast(slot_idx)].dimensions_w;
                var bbox_h: f32 = pass.ring_buffer[@intCast(slot_idx)].dimensions_h;

                if (is_floating_root and slot_idx == root_slot) {
                    const fc_idx = pass.configLookupFloating(slot_idx);
                    const fc = &pass.floating_configs[@intCast(fc_idx)];

                    var target_bbox_x: f32 = 0.0;
                    var target_bbox_y: f32 = 0.0;
                    var target_bbox_w: f32 = pass.layout_width;
                    var target_bbox_h: f32 = pass.layout_height;

                    if (fc.attach_to == 1) {
                        const parent_slot = pass.ring_buffer[@intCast(slot_idx)].parent_slot_idx;
                        if (parent_slot >= 0) {
                            target_bbox_x = pass.ring_buffer[@intCast(parent_slot)].bbox_x;
                            target_bbox_y = pass.ring_buffer[@intCast(parent_slot)].bbox_y;
                            target_bbox_w = pass.ring_buffer[@intCast(parent_slot)].bbox_w;
                            target_bbox_h = pass.ring_buffer[@intCast(parent_slot)].bbox_h;
                        }
                    } else if (fc.attach_to == 2) {
                        const target_slot = pass.hashChainWalk(fc.parent_id);
                        if (target_slot >= 0) {
                            target_bbox_x = pass.ring_buffer[@intCast(target_slot)].bbox_x;
                            target_bbox_y = pass.ring_buffer[@intCast(target_slot)].bbox_y;
                            target_bbox_w = pass.ring_buffer[@intCast(target_slot)].bbox_w;
                            target_bbox_h = pass.ring_buffer[@intCast(target_slot)].bbox_h;
                        }
                    }

                    const parent_pt = resolveAttachPoint(fc.attach_parent, target_bbox_x, target_bbox_y, target_bbox_w, target_bbox_h);
                    const elem_off = resolveElementAttachOffset(fc.attach_element, bbox_w, bbox_h);

                    bbox_x = parent_pt.x - elem_off.x + fc.offset_x;
                    bbox_y = parent_pt.y - elem_off.y + fc.offset_y;

                    bbox_x -= fc.expand_w;
                    bbox_y -= fc.expand_h;
                    bbox_w += fc.expand_w * 2.0;
                    bbox_h += fc.expand_h * 2.0;
                }

                pass.ring_buffer[@intCast(slot_idx)].bbox_x = bbox_x;
                pass.ring_buffer[@intCast(slot_idx)].bbox_y = bbox_y;
                pass.ring_buffer[@intCast(slot_idx)].bbox_w = bbox_w;
                pass.ring_buffer[@intCast(slot_idx)].bbox_h = bbox_h;

                var scroll_x: f32 = entry.scroll_offset_x;
                var scroll_y: f32 = entry.scroll_offset_y;
                if (pass.configPresentClip(slot_idx)) {
                    const cc_idx = pass.configLookupClip(slot_idx);
                    scroll_x += pass.clip_configs[@intCast(cc_idx)].child_offset_x;
                    scroll_y += pass.clip_configs[@intCast(cc_idx)].child_offset_y;
                }

                const culled = isCulled(bbox_x, bbox_y, bbox_w, bbox_h);

                if (!culled) {
                    if (pass.configPresentClip(slot_idx)) {
                        emitRenderCommand(RenderCommand{
                            .cmd_type = pass.CMD_SCISSOR_START,
                            .x = bbox_x,
                            .y = bbox_y,
                            .w = bbox_w,
                            .h = bbox_h,
                            .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                        });
                    }
                    if (pass.configPresentShared(slot_idx)) {
                        const sc = &pass.shared_configs[@intCast(pass.configLookupShared(slot_idx))];
                        if (sc.bg_a > 0.0) {
                            emitRenderCommand(RenderCommand{
                                .cmd_type = pass.CMD_RECTANGLE,
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
                                .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                            });
                        }
                    }
                    if (pass.configPresentImage(slot_idx)) {
                        emitRenderCommand(RenderCommand{
                            .cmd_type = pass.CMD_IMAGE,
                            .x = bbox_x,
                            .y = bbox_y,
                            .w = bbox_w,
                            .h = bbox_h,
                            .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                        });
                    }
                    if (pass.ring_buffer[@intCast(slot_idx)].text_data_idx != -1) {
                        const td_idx = pass.ring_buffer[@intCast(slot_idx)].text_data_idx;
                        const td = &pass.text_data[@intCast(td_idx)];

                        std.debug.print("TEXT EMIT: slot={}  id={}  bbox=({},{})  cmd#={}\n", .{ slot_idx, pass.ring_buffer[@intCast(slot_idx)].id, bbox_x, bbox_y, pass.next_render_cmd });

                        var line_y: f32 = bbox_y;
                        var wl: i32 = td.wrapped_lines_start;
                        while (wl < td.wrapped_lines_end) {
                            const wline = &pass.wrapped_lines[@intCast(wl)];
                            emitRenderCommand(RenderCommand{
                                .cmd_type = pass.CMD_TEXT,
                                .x = bbox_x,
                                .y = line_y,
                                .w = wline.dim_w,
                                .h = wline.dim_h,
                                .text_data_idx = td_idx,
                                .wrapped_line_idx = wl,
                                .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                            });
                            line_y += wline.dim_h;
                            wl += 1;
                        }
                    }
                    if (pass.configPresentCustom(slot_idx)) {
                        emitRenderCommand(RenderCommand{
                            .cmd_type = pass.CMD_CUSTOM,
                            .x = bbox_x,
                            .y = bbox_y,
                            .w = bbox_w,
                            .h = bbox_h,
                            .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                        });
                    }
                }

                // Push UP visit
                dfs_top += 1;
                dfs_stack[@intCast(dfs_top)] = DFSEntry{
                    .slot_idx = slot_idx,
                    .visit = DFS_VISIT_UP,
                    .parent_bbox_x = bbox_x,
                    .parent_bbox_y = bbox_y,
                    .scroll_offset_x = scroll_x,
                    .scroll_offset_y = scroll_y,
                };

                // Push children in REVERSE order — FIXED: use pass.nextSibling
                const lc_idx = pass.ring_buffer[@intCast(slot_idx)].layout_config_idx;
                if (lc_idx != -1) {
                    const lc = &pass.layout_configs[@intCast(lc_idx)];

                    var child_indices: [256]i32 = [_]i32{-1} ** 256;
                    var child_count: i32 = 0;
                    var ci: i32 = pass.ring_buffer[@intCast(slot_idx)].children_start;
                    while (ci < pass.ring_buffer[@intCast(slot_idx)].children_end) {
                        if (pass.isChildLive(ci) and pass.isChildNonFloating(ci)) {
                            child_indices[@intCast(child_count)] = ci;
                            child_count += 1;
                        }
                        ci = pass.nextSibling(ci);
                    }

                    var offset_x: f32 = lc.padding_left;
                    var offset_y: f32 = lc.padding_top;

                    var offsets_x: [256]f32 = [_]f32{0.0} ** 256;
                    var offsets_y: [256]f32 = [_]f32{0.0} ** 256;
                    var oi: i32 = 0;
                    while (oi < child_count) {
                        offsets_x[@intCast(oi)] = offset_x;
                        offsets_y[@intCast(oi)] = offset_y;
                        const child_idx = child_indices[@intCast(oi)];
                        if (lc.layout_direction == pass.LAYOUT_LEFT_TO_RIGHT) {
                            offset_x += pass.ring_buffer[@intCast(child_idx)].dimensions_w + lc.child_gap;
                        } else {
                            offset_y += pass.ring_buffer[@intCast(child_idx)].dimensions_h + lc.child_gap;
                        }
                        oi += 1;
                    }

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
                // UP visit
                const bbox_x = pass.ring_buffer[@intCast(slot_idx)].bbox_x;
                const bbox_y = pass.ring_buffer[@intCast(slot_idx)].bbox_y;
                const bbox_w = pass.ring_buffer[@intCast(slot_idx)].bbox_w;
                const bbox_h = pass.ring_buffer[@intCast(slot_idx)].bbox_h;
                const culled = isCulled(bbox_x, bbox_y, bbox_w, bbox_h);

                if (!culled) {
                    if (pass.configPresentBorder(slot_idx)) {
                        const bc = &pass.border_configs[@intCast(pass.configLookupBorder(slot_idx))];
                        emitRenderCommand(RenderCommand{
                            .cmd_type = pass.CMD_BORDER,
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
                            .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                        });

                        if (bc.between > 0 and bc.color_a > 0.0) {
                            const lc_idx = pass.ring_buffer[@intCast(slot_idx)].layout_config_idx;
                            if (lc_idx != -1) {
                                const lc = &pass.layout_configs[@intCast(lc_idx)];
                                var border_offset_x: f32 = lc.padding_left;
                                var border_offset_y: f32 = lc.padding_top;
                                var first: bool = true;

                                var ci: i32 = pass.ring_buffer[@intCast(slot_idx)].children_start;
                                while (ci < pass.ring_buffer[@intCast(slot_idx)].children_end) {
                                    if (pass.isChildLive(ci) and pass.isChildNonFloating(ci)) {
                                        if (!first) {
                                            if (lc.layout_direction == pass.LAYOUT_LEFT_TO_RIGHT) {
                                                emitRenderCommand(RenderCommand{
                                                    .cmd_type = pass.CMD_RECTANGLE,
                                                    .x = bbox_x + border_offset_x - @as(f32, @intCast(bc.between)) * 0.5,
                                                    .y = bbox_y,
                                                    .w = @as(f32, @intCast(bc.between)),
                                                    .h = bbox_h,
                                                    .color_r = bc.color_r,
                                                    .color_g = bc.color_g,
                                                    .color_b = bc.color_b,
                                                    .color_a = bc.color_a,
                                                    .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                                                });
                                            } else {
                                                emitRenderCommand(RenderCommand{
                                                    .cmd_type = pass.CMD_RECTANGLE,
                                                    .x = bbox_x,
                                                    .y = bbox_y + border_offset_y - @as(f32, @intCast(bc.between)) * 0.5,
                                                    .w = bbox_w,
                                                    .h = @as(f32, @intCast(bc.between)),
                                                    .color_r = bc.color_r,
                                                    .color_g = bc.color_g,
                                                    .color_b = bc.color_b,
                                                    .color_a = bc.color_a,
                                                    .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                                                });
                                            }
                                        }
                                        first = false;
                                        if (lc.layout_direction == pass.LAYOUT_LEFT_TO_RIGHT) {
                                            border_offset_x += pass.ring_buffer[@intCast(ci)].dimensions_w + lc.child_gap;
                                        } else {
                                            border_offset_y += pass.ring_buffer[@intCast(ci)].dimensions_h + lc.child_gap;
                                        }
                                    }
                                    ci = pass.nextSibling(ci);
                                }
                            }
                        }
                    }

                    if (pass.configPresentClip(slot_idx)) {
                        emitRenderCommand(RenderCommand{
                            .cmd_type = pass.CMD_SCISSOR_END,
                            .slot_id = pass.ring_buffer[@intCast(slot_idx)].id,
                        });
                    }
                }
            }
        }

        r += 1;
    }

    std.debug.print("--- Pass 9: final_layout complete. {} render commands ---\n", .{pass.next_render_cmd});
}

// --- PASS 0: pointer_detection ---
// Reverse z-order traversal. Hit test against previous frame bboxes.

fn passPointerDetection(pointer_x: f32, pointer_y: f32, pointer_down: bool) void {
    pass.assertDepsAndMark(pass.BIT_POINTER_DETECTION, pass.BIT_FINAL_LAYOUT);

    pass.pointer_state = switch (pass.pointer_state) {
        pass.PTR_RELEASED => if (pointer_down) pass.PTR_PRESSED_THIS_FRAME else pass.PTR_RELEASED,
        pass.PTR_PRESSED_THIS_FRAME => if (pointer_down) pass.PTR_PRESSED else pass.PTR_RELEASED_THIS_FRAME,
        pass.PTR_PRESSED => if (!pointer_down) pass.PTR_RELEASED_THIS_FRAME else pass.PTR_PRESSED,
        pass.PTR_RELEASED_THIS_FRAME => if (!pointer_down) pass.PTR_RELEASED else pass.PTR_PRESSED_THIS_FRAME,
        else => pass.PTR_RELEASED,
    };

    pass.pointer_over_write_head = 0;

    var r: i32 = pass.next_tree_root - 1;
    while (r >= 0) {
        const root_slot = pass.tree_roots[@intCast(r)].layout_element_index;
        if (root_slot < 0) {
            r -= 1;
            continue;
        }

        var dfs_stack: [pass.SLOT_COUNT]i32 = [_]i32{-1} ** pass.SLOT_COUNT;
        var dfs_top: i32 = 0;
        dfs_stack[0] = root_slot;
        var captured: bool = false;

        while (dfs_top >= 0) {
            const slot_idx = dfs_stack[@intCast(dfs_top)];
            dfs_top -= 1;

            const bx = pass.ring_buffer[@intCast(slot_idx)].bbox_x;
            const by = pass.ring_buffer[@intCast(slot_idx)].bbox_y;
            const bw = pass.ring_buffer[@intCast(slot_idx)].bbox_w;
            const bh = pass.ring_buffer[@intCast(slot_idx)].bbox_h;

            var hit: bool = pointer_x >= bx and pointer_x < bx + bw and
                pointer_y >= by and pointer_y < by + bh;

            if (hit) {
                const clip_id = pass.tree_roots[@intCast(r)].clip_element_id;
                if (clip_id != -1) {
                    const clip_slot = pass.hashChainWalk(clip_id);
                    if (clip_slot >= 0) {
                        const cx = pass.ring_buffer[@intCast(clip_slot)].bbox_x;
                        const cy = pass.ring_buffer[@intCast(clip_slot)].bbox_y;
                        const cw = pass.ring_buffer[@intCast(clip_slot)].bbox_w;
                        const ch = pass.ring_buffer[@intCast(clip_slot)].bbox_h;
                        if (pointer_x < cx or pointer_x >= cx + cw or pointer_y < cy or pointer_y >= cy + ch) {
                            hit = false;
                        }
                    }
                }
            }

            if (hit) {
                pass.pointer_over_ids[@intCast(pass.pointer_over_write_head)] = pass.ring_buffer[@intCast(slot_idx)].id;
                pass.pointer_over_write_head = (pass.pointer_over_write_head + 1) % @as(i32, pass.POINTER_OVER_COUNT);

                if (slot_idx == root_slot and pass.configPresentFloating(slot_idx)) {
                    const fc_idx = pass.configLookupFloating(slot_idx);
                    if (pass.floating_configs[@intCast(fc_idx)].capture_mode == 0) {
                        captured = true;
                    }
                }
            }

            // Push children — FIXED: use pass.nextSibling
            var ci: i32 = pass.ring_buffer[@intCast(slot_idx)].children_start;
            while (ci < pass.ring_buffer[@intCast(slot_idx)].children_end) {
                if (pass.isChildLive(ci)) {
                    dfs_top += 1;
                    dfs_stack[@intCast(dfs_top)] = ci;
                }
                ci = pass.nextSibling(ci);
            }
        }

        if (captured) break;

        r -= 1;
    }

    std.debug.print("--- Pass 0: pointer_detection complete. state={}, hits: ", .{pass.pointer_state});
    var pi: i32 = 0;
    while (pi < pass.pointer_over_write_head) {
        std.debug.print("{} ", .{pass.pointer_over_ids[@intCast(pi)]});
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
    while (i < pass.next_render_cmd) {
        const cmd = &pass.render_commands[@intCast(i)];
        const name = cmd_names[@intCast(cmd.cmd_type)];
        std.debug.print("[{d:3}] {s:14} id={d:4} pos=({d:.1},{d:.1}) dim=({d:.1},{d:.1})", .{ i, name, cmd.slot_id, cmd.x, cmd.y, cmd.w, cmd.h });
        if (cmd.cmd_type == pass.CMD_RECTANGLE or cmd.cmd_type == pass.CMD_BORDER) {
            std.debug.print(" rgba=({d:.2},{d:.2},{d:.2},{d:.2})", .{ cmd.color_r, cmd.color_g, cmd.color_b, cmd.color_a });
        }
        if (cmd.cmd_type == pass.CMD_BORDER) {
            std.debug.print(" border=L{}R{}T{}B{}", .{ cmd.border_left, cmd.border_right, cmd.border_top, cmd.border_bottom });
        }
        if (cmd.cmd_type == pass.CMD_TEXT) {
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
    while (i < pass.next_slot) {
        const s = &pass.ring_buffer[@intCast(i)];
        if (s.state == pass.STATE_LIVE) {
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
    pass.passDeclaration(); // Pass 1
    pass.passSizeX(); // Pass 2
    pass.passTextWrap(); // Pass 3
    pass.passAspectRatioV(); // Pass 4
    pass.passPropagateHeights(); // Pass 5
    pass.passSizeY(); // Pass 6
    pass.passAspectRatioH(); // Pass 7
    pass.passSortZ(); // Pass 8
    passFinalLayout(); // Pass 9

    // Print intermediate state
    printSlotState();
    printRenderCommands();

    // Run pointer detection with test point inside element 300 (green square)
    // Element 300 should be at approximately (10+10, 10+10) = (20,20) with size 50x50
    // So test point (40, 40) should hit it
    pass.passes_completed = pass.passes_completed; // keep completed flags
    passPointerDetection(40.0, 40.0, false); // Pass 0

    std.debug.print("\n============================================================\n", .{});
    std.debug.print("  Test complete.\n", .{});
    std.debug.print("============================================================\n", .{});
}
