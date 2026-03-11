const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gio/gio.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const DesktopEntry = struct {
    name: []const u8,
    icon: []const u8,
    path: []const u8,
    exec: []const u8,
    package: []const u8,
    name_owned: bool = false,
    icon_owned: bool = false,
    exec_owned: bool = false,
    package_owned: bool = false,
};

const PackageInfo = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    url: []const u8,
    license: []const u8,
    depends: []const u8,
    name_owned: bool = false,
    version_owned: bool = false,
    description_owned: bool = false,
    url_owned: bool = false,
    license_owned: bool = false,
    depends_owned: bool = false,
};

const DetailDialogData = struct {
    path: [:0]const u8,
    pkg_info: *PackageInfo,
};

const ResponseData = struct {
    path: [:0]const u8,
};

const DialogCleanupData = struct {
    detail_data: ?*DetailDialogData,
    open_data: ?*ResponseData,
};

// Use AlignedManaged which stores the allocator
const DesktopEntryList = std.array_list.AlignedManaged(DesktopEntry, null);

var search_entries: DesktopEntryList = undefined;
var list_box: ?*c.GtkListBox = null;
var search_entry: ?*c.GtkSearchEntry = null;
var title_label_widget: ?*c.GtkWidget = null;
var main_window: ?*c.GtkWidget = null;
var search_thread: ?std.Thread = null;
var search_mutex: std.Thread.Mutex = .{};
var search_cancelled: bool = false;

// Standard paths for desktop files
const standard_paths = [_][]const u8{
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
};

fn getHomeApplicationsPath(alloc: std.mem.Allocator) ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    return std.fs.path.join(alloc, &.{ home, ".local/share/applications" }) catch null;
}

fn loadDesktopFile(path: []const u8) ?DesktopEntry {
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    var name: ?[]const u8 = null;
    var icon: ?[]const u8 = null;
    var exec: ?[]const u8 = null;
    var name_owned = false;
    var icon_owned = false;
    var exec_owned = false;
    var in_desktop_entry = false;

    // Read entire file into memory
    const content = file.readToEndAlloc(allocator, 65536) catch return null;
    defer allocator.free(content);

    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (std.mem.startsWith(u8, trimmed, "[Desktop Entry]")) {
            in_desktop_entry = true;
            continue;
        }
        if (std.mem.startsWith(u8, trimmed, "[") and !std.mem.startsWith(u8, trimmed, "[Desktop Entry]")) {
            in_desktop_entry = false;
            continue;
        }
        if (!in_desktop_entry) continue;

        if (std.mem.startsWith(u8, trimmed, "Name=")) {
            const val = trimmed[5..];
            name = allocator.dupe(u8, val) catch null;
            if (name != null) name_owned = true;
        } else if (std.mem.startsWith(u8, trimmed, "Name[")) {
            // Handle localized name - skip for now, use generic Name
        } else if (std.mem.startsWith(u8, trimmed, "Icon=")) {
            const val = trimmed[5..];
            icon = allocator.dupe(u8, val) catch null;
            if (icon != null) icon_owned = true;
        } else if (std.mem.startsWith(u8, trimmed, "Exec=")) {
            const val = trimmed[5..];
            exec = allocator.dupe(u8, val) catch null;
            if (exec != null) exec_owned = true;
        }
    }

    if (name) |n| {
        const path_copy = allocator.dupe(u8, path) catch {
            if (name_owned) allocator.free(n);
            if (icon) |i| if (icon_owned) allocator.free(i);
            if (exec) |e| if (exec_owned) allocator.free(e);
            return null;
        };
        
        // Don't lookup package here - too slow for startup
        // We'll do it in showDetailDialog when user clicks
        
        return .{
            .name = n,
            .icon = icon orelse "application-x-executable",
            .path = path_copy,
            .exec = exec orelse "",
            .package = "",
            .name_owned = name_owned,
            .icon_owned = icon_owned,
            .exec_owned = exec_owned,
            .package_owned = false,
        };
    }

    return null;
}

fn lookupPacmanPackage(exec_line: []const u8) ?[]const u8 {
    // Extract the actual executable from the exec line
    // Remove env vars like env VAR=VAL, % arguments, quotes, etc.
    var exec_buf: [256]u8 = undefined;
    
    // Skip leading env assignments like "env GTK_THEME=dark "
    var start: usize = 0;
    if (std.mem.startsWith(u8, exec_line, "env ")) {
        start = 4;
        // Skip until we find something that looks like an executable
        while (start < exec_line.len) {
            const remaining = exec_line[start..];
            // Check if this looks like an env var assignment (contains = before space)
            if (std.mem.indexOf(u8, remaining, "=")) |eq_pos| {
                if (std.mem.indexOf(u8, remaining, " ")) |space_pos| {
                    if (eq_pos < space_pos) {
                        // It's an env var, skip it
                        start = start + space_pos + 1;
                        // Skip any whitespace
                        while (start < exec_line.len and (exec_line[start] == ' ' or exec_line[start] == '\t')) {
                            start += 1;
                        }
                        continue;
                    }
                }
            }
            break;
        }
    }
    
    // Get the executable name (first non-whitespace token, removing quotes)
    var exec_end: usize = start;
    var in_quote = false;
    while (exec_end < exec_line.len) {
        const ch = exec_line[exec_end];
        if (ch == '"') {
            in_quote = !in_quote;
            exec_end += 1;
            continue;
        }
        if (!in_quote and (ch == ' ' or ch == '\t' or ch == '%')) {
            break;
        }
        exec_end += 1;
    }
    
    if (exec_end <= start) {
        c.g_print("lookupPacmanPackage: exec_end <= start\n");
        return null;
    }
    const exec_name = exec_line[start..exec_end];
    c.g_print("lookupPacmanPackage: exec_name='%.*s'\n", @as(c_int, @intCast(exec_name.len)), exec_name.ptr);
    
    // For pacman -Qo, we need the path to query. Use full path if absolute
    const query_path = if (exec_name[0] == '/') exec_name else std.fs.path.basename(exec_name);
    c.g_print("lookupPacmanPackage: query_path='%.*s'\n", @as(c_int, @intCast(query_path.len)), query_path.ptr);
    if (query_path.len == 0) return null;
    
    // For relative paths, we can't easily check - just skip
    if (query_path[0] != '/') {
        c.g_print("lookupPacmanPackage: relative path, skipping\n");
        return null;
    }
    
    // Copy to buffer for null termination
    const exec_z = std.fmt.bufPrintZ(&exec_buf, "{s}", .{query_path}) catch return null;
    
    c.g_print("Looking up package for: %s\n", exec_z.ptr);
    
    // Run pacman -Qo to find the package
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "pacman", "-Qo", exec_z },
    }) catch |err| {
        c.g_print("Child.run failed: %d\n", @intFromError(err));
        return null;
    };
    
    defer {
        if (result.stdout.len > 0) allocator.free(result.stdout);
        if (result.stderr.len > 0) allocator.free(result.stderr);
    }
    
    // Check exit code
    if (result.term != .Exited or result.term.Exited != 0) {
        const exit_code = if (result.term == .Exited) result.term.Exited else 255;
        c.g_print("pacman -Qo failed with exit code: %d\n", @as(c_int, @intCast(exit_code)));
        if (result.stderr.len > 0) {
            c.g_print("stderr: %.*s\n", @as(c_int, @intCast(result.stderr.len)), result.stderr.ptr);
        }
        return null;
    }
    
    c.g_print("pacman stdout: %.*s\n", @as(c_int, @intCast(result.stdout.len)), result.stdout.ptr);
    
    // Parse output: "/usr/bin/zed is owned by zed 0.171.0-1"
    const stdout = result.stdout;
    c.g_print("Parsing stdout (len=%d): %.*s\n", @as(c_int, @intCast(stdout.len)), @as(c_int, @intCast(stdout.len)), stdout.ptr);
    if (stdout.len == 0) return null;
    
    const needle = "is owned by ";
    c.g_print("Looking for: '%s'\n", needle.ptr);
    
    if (std.mem.indexOf(u8, stdout, needle)) |idx| {
        c.g_print("Found at index: %d\n", @as(c_int, @intCast(idx)));
        const after = stdout[idx + needle.len ..];
        c.g_print("After match: %.*s\n", @as(c_int, @intCast(after.len)), after.ptr);
        
        // Find the package name (first word after "is owned by ")
        var pkg_end: usize = 0;
        while (pkg_end < after.len and after[pkg_end] != ' ' and after[pkg_end] != '\n') {
            pkg_end += 1;
        }
        c.g_print("Package name length: %d\n", @as(c_int, @intCast(pkg_end)));
        if (pkg_end > 0) {
            const pkg = allocator.dupe(u8, after[0..pkg_end]) catch return null;
            c.g_print("Found package name: %.*s\n", @as(c_int, @intCast(pkg.len)), pkg.ptr);
            return pkg;
        }
    } else {
        c.g_print("Did not find 'is owned by' in output\n");
    }
    
    return null;
}

fn getPackageInfo(package_name: []const u8) ?PackageInfo {
    var pkg_buf: [128]u8 = undefined;
    const pkg_z = std.fmt.bufPrintZ(&pkg_buf, "{s}", .{package_name}) catch return null;
    
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "pacman", "-Qi", pkg_z },
    }) catch return null;
    
    defer {
        if (result.stdout.len > 0) allocator.free(result.stdout);
        if (result.stderr.len > 0) allocator.free(result.stderr);
    }
    
    const stdout = result.stdout;
    if (stdout.len == 0) return null;
    
    var info = PackageInfo{
        .name = "",
        .version = "",
        .description = "",
        .url = "",
        .license = "",
        .depends = "",
    };
    
    // Parse pacman -Qi output line by line
    var lines = std.mem.splitSequence(u8, stdout, "\n");
    while (lines.next()) |line| {
        // Lines are like "Name            : zed"
        if (std.mem.indexOf(u8, line, ":")) |colon| {
            const key = std.mem.trim(u8, line[0..colon], " ");
            const value = std.mem.trim(u8, line[colon + 1 ..], " ");
            
            if (std.mem.eql(u8, key, "Name")) {
                info.name = allocator.dupe(u8, value) catch "";
                info.name_owned = true;
            } else if (std.mem.eql(u8, key, "Version")) {
                info.version = allocator.dupe(u8, value) catch "";
                info.version_owned = true;
            } else if (std.mem.eql(u8, key, "Description")) {
                info.description = allocator.dupe(u8, value) catch "";
                info.description_owned = true;
            } else if (std.mem.eql(u8, key, "URL")) {
                info.url = allocator.dupe(u8, value) catch "";
                info.url_owned = true;
            } else if (std.mem.eql(u8, key, "Licenses")) {
                info.license = allocator.dupe(u8, value) catch "";
                info.license_owned = true;
            } else if (std.mem.eql(u8, key, "Depends On")) {
                info.depends = allocator.dupe(u8, value) catch "";
                info.depends_owned = true;
            }
        }
    }
    
    if (info.name.len == 0) return null;
    return info;
}

fn freePackageInfo(info: *PackageInfo) void {
    if (info.name_owned) allocator.free(info.name);
    if (info.version_owned) allocator.free(info.version);
    if (info.description_owned) allocator.free(info.description);
    if (info.url_owned) allocator.free(info.url);
    if (info.license_owned) allocator.free(info.license);
    if (info.depends_owned) allocator.free(info.depends);
}

fn scanDirectory(dir_path: []const u8, entries: *DesktopEntryList) void {
    var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (search_cancelled) return;

        const ext = std.fs.path.extension(entry.name);
        if (std.mem.eql(u8, ext, ".desktop")) {
            const full_path = std.fs.path.join(allocator, &.{ dir_path, entry.name }) catch continue;
            if (loadDesktopFile(full_path)) |de| {
                entries.append(de) catch {};
            }
            allocator.free(full_path);
        }
    }
}

fn scanAllDirectories() void {
    search_mutex.lock();
    defer search_mutex.unlock();

    for (standard_paths) |path| {
        if (search_cancelled) return;
        scanDirectory(path, &search_entries);
    }

    // Check home directory
    if (getHomeApplicationsPath(allocator)) |home_path| {
        defer allocator.free(home_path);
        if (!search_cancelled) {
            scanDirectory(home_path, &search_entries);
        }
    }
}

fn freeDesktopEntries(entries: *DesktopEntryList) void {
    for (entries.items) |entry| {
        if (entry.name_owned) allocator.free(entry.name);
        if (entry.icon_owned) allocator.free(entry.icon);
        if (entry.exec_owned) allocator.free(entry.exec);
        if (entry.package_owned) allocator.free(entry.package);
        allocator.free(entry.path);
    }
    entries.deinit();
}

fn matchesSearch(entry: *const DesktopEntry, query: []const u8) bool {
    if (query.len == 0) return true;
    const lower_query = std.ascii.allocLowerString(allocator, query) catch return false;
    defer allocator.free(lower_query);

    const lower_name = std.ascii.allocLowerString(allocator, entry.name) catch return false;
    defer allocator.free(lower_name);

    return std.mem.indexOf(u8, lower_name, lower_query) != null;
}

fn iconFromName(icon_name: [*:0]const u8) ?*c.GtkWidget {
    const icon_theme = c.gtk_icon_theme_get_for_display(c.gdk_display_get_default());
    var icon: ?*c.GtkIconPaintable = null;

    // Check if icon_name is an absolute path
    if (icon_name[0] == '/') {
        const file = c.g_file_new_for_path(icon_name);
        icon = c.gtk_icon_paintable_new_for_file(file, 32, 1);
        c.g_object_unref(file);
    } else {
        // Try to lookup the icon
        icon = c.gtk_icon_theme_lookup_icon(
            icon_theme,
            icon_name,
            null,
            32,
            1,
            c.GTK_TEXT_DIR_NONE,
            c.GTK_ICON_LOOKUP_PRELOAD,
        );
        if (icon == null) {
            // Try as symbolic icon
            var symbolic_name: [256]u8 = undefined;
            const symbolic_slice = std.fmt.bufPrintZ(&symbolic_name, "{s}-symbolic", .{icon_name}) catch return null;
            icon = c.gtk_icon_theme_lookup_icon(
                icon_theme,
                symbolic_slice.ptr,
                null,
                32,
                1,
                c.GTK_TEXT_DIR_NONE,
                c.GTK_ICON_LOOKUP_PRELOAD,
            );
        }
        if (icon == null) {
            // Fallback to generic icon
            icon = c.gtk_icon_theme_lookup_icon(
                icon_theme,
                "application-x-executable",
                null,
                32,
                1,
                c.GTK_TEXT_DIR_NONE,
                c.GTK_ICON_LOOKUP_PRELOAD,
            );
        }
    }

    if (icon) |ic| {
        const image = c.gtk_image_new_from_paintable(@ptrCast(ic));
        c.g_object_unref(ic);
        return image;
    }

    return c.gtk_image_new_from_icon_name("application-x-executable");
}

fn createResultRow(entry: *const DesktopEntry, index: usize) ?*c.GtkWidget {
    const box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 12);
    c.gtk_widget_set_margin_start(box, 8);
    c.gtk_widget_set_margin_end(box, 8);
    c.gtk_widget_set_margin_top(box, 4);
    c.gtk_widget_set_margin_bottom(box, 4);

    // Store index as name for retrieval
    var index_buf: [20]u8 = undefined;
    const index_str = std.fmt.bufPrintZ(&index_buf, "{}", .{index}) catch return null;
    c.gtk_widget_set_name(box, index_str.ptr);

    // Icon
    const icon_name_z = allocator.dupeZ(u8, entry.icon) catch return null;
    defer allocator.free(icon_name_z);

    const icon_widget = iconFromName(icon_name_z.ptr) orelse c.gtk_image_new_from_icon_name("application-x-executable");
    c.gtk_widget_set_valign(icon_widget, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), icon_widget);

    // Name and path container
    const vbox = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 2);
    c.gtk_widget_set_hexpand(vbox, 1);
    c.gtk_widget_set_valign(vbox, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(box), vbox);

    // Name label
    const name_z = allocator.dupeZ(u8, entry.name) catch return null;
    defer allocator.free(name_z);
    const name_label = c.gtk_label_new(name_z.ptr);
    c.gtk_widget_set_halign(name_label, c.GTK_ALIGN_START);
    c.gtk_label_set_xalign(@ptrCast(name_label), 0.0);
    const name_attrs = c.pango_attr_list_new();
    const weight_attr = c.pango_attr_weight_new(c.PANGO_WEIGHT_BOLD);
    c.pango_attr_list_insert(name_attrs, weight_attr);
    c.gtk_label_set_attributes(@ptrCast(name_label), name_attrs);
    c.pango_attr_list_unref(name_attrs);
    c.gtk_box_append(@ptrCast(vbox), name_label);

    // Path label
    const path_z = allocator.dupeZ(u8, entry.path) catch return null;
    defer allocator.free(path_z);
    const path_label = c.gtk_label_new(path_z.ptr);
    c.gtk_widget_set_halign(path_label, c.GTK_ALIGN_START);
    c.gtk_label_set_xalign(@ptrCast(path_label), 0.0);
    c.gtk_widget_add_css_class(path_label, "dim-label");
    c.gtk_widget_add_css_class(path_label, "caption");
    c.gtk_box_append(@ptrCast(vbox), path_label);

    return box;
}

fn showDetailDialog(entry: *const DesktopEntry) void {
    if (main_window == null) return;

    c.g_print("showDetailDialog: name='%.*s' (len=%d)\n", @as(c_int, @intCast(entry.name.len)), entry.name.ptr, @as(c_int, @intCast(entry.name.len)));
    
    // Get package info - lookup NOW, not during scan
    var pkg_info: ?PackageInfo = null;
    if (entry.exec.len > 0) {
        if (lookupPacmanPackage(entry.exec)) |pkg_name| {
            c.g_print("Found package: %s\n", pkg_name.ptr);
            pkg_info = getPackageInfo(pkg_name);
            allocator.free(pkg_name);
            if (pkg_info) |pi| {
                c.g_print("Package info: name='%s' version='%s'\n", pi.name.ptr, pi.version.ptr);
            } else {
                c.g_print("Failed to get package info from pacman -Qi\n");
            }
        } else {
            c.g_print("lookupPacmanPackage returned null\n");
        }
    }

    // Create a regular dialog (not app chooser)
    const dialog = c.gtk_dialog_new();
    c.gtk_window_set_title(@ptrCast(dialog), "Desktop File Details");
    c.gtk_window_set_default_size(@ptrCast(dialog), 500, 400);
    c.gtk_window_set_modal(@ptrCast(dialog), 1);
    c.gtk_window_set_transient_for(@ptrCast(dialog), @ptrCast(main_window));
    c.gtk_window_set_destroy_with_parent(@ptrCast(dialog), 1);
    
    const content_area = c.gtk_dialog_get_content_area(@ptrCast(dialog));
    c.gtk_box_set_spacing(@ptrCast(content_area), 12);
    c.gtk_widget_set_margin_start(content_area, 16);
    c.gtk_widget_set_margin_end(content_area, 16);
    c.gtk_widget_set_margin_top(content_area, 16);
    c.gtk_widget_set_margin_bottom(content_area, 16);
    
    // Header with icon and name
    const header_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 12);
    c.gtk_box_append(@ptrCast(content_area), header_box);
    
    // Icon
    const icon_name_z = allocator.dupeZ(u8, entry.icon) catch return;
    defer allocator.free(icon_name_z);
    const icon_widget = iconFromName(icon_name_z.ptr) orelse c.gtk_image_new_from_icon_name("application-x-executable");
    c.gtk_image_set_pixel_size(@ptrCast(icon_widget), 48);
    c.gtk_box_append(@ptrCast(header_box), icon_widget);
    
    // Name and path
    const name_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 4);
    c.gtk_widget_set_hexpand(name_box, 1);
    c.gtk_widget_set_valign(name_box, c.GTK_ALIGN_CENTER);
    c.gtk_box_append(@ptrCast(header_box), name_box);
    
    const name_z = allocator.dupeZ(u8, entry.name) catch return;
    defer allocator.free(name_z);
    const name_label = c.gtk_label_new(name_z.ptr);
    c.gtk_widget_set_halign(name_label, c.GTK_ALIGN_START);
    c.gtk_label_set_xalign(@ptrCast(name_label), 0.0);
    const name_attrs = c.pango_attr_list_new();
    const size_attr = c.pango_attr_size_new(14 * c.PANGO_SCALE);
    const weight_attr = c.pango_attr_weight_new(c.PANGO_WEIGHT_BOLD);
    c.pango_attr_list_insert(name_attrs, size_attr);
    c.pango_attr_list_insert(name_attrs, weight_attr);
    c.gtk_label_set_attributes(@ptrCast(name_label), name_attrs);
    c.pango_attr_list_unref(name_attrs);
    c.gtk_box_append(@ptrCast(name_box), name_label);
    
    const path_z = allocator.dupeZ(u8, entry.path) catch return;
    defer allocator.free(path_z);
    const path_label = c.gtk_label_new(path_z.ptr);
    c.gtk_widget_set_halign(path_label, c.GTK_ALIGN_START);
    c.gtk_label_set_xalign(@ptrCast(path_label), 0.0);
    c.gtk_widget_add_css_class(path_label, "dim-label");
    c.gtk_widget_add_css_class(path_label, "caption");
    c.gtk_box_append(@ptrCast(name_box), path_label);
    
    // Separator
    const sep = c.gtk_separator_new(c.GTK_ORIENTATION_HORIZONTAL);
    c.gtk_widget_set_margin_top(sep, 8);
    c.gtk_widget_set_margin_bottom(sep, 8);
    c.gtk_box_append(@ptrCast(content_area), sep);
    
    // Package info section
    c.g_print("Creating package section, pkg_info is %s\n", if (pkg_info != null) @as([*:0]const u8, "present") else @as([*:0]const u8, "null"));
    if (pkg_info) |info| {
        c.g_print("Creating package frame for: %s\n", info.name.ptr);
        const pkg_frame = c.gtk_frame_new(null);
        c.gtk_widget_set_margin_bottom(pkg_frame, 12);
        c.gtk_box_append(@ptrCast(content_area), pkg_frame);
        
        const pkg_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 8);
        c.gtk_widget_set_margin_start(pkg_box, 12);
        c.gtk_widget_set_margin_end(pkg_box, 12);
        c.gtk_widget_set_margin_top(pkg_box, 12);
        c.gtk_widget_set_margin_bottom(pkg_box, 12);
        c.gtk_frame_set_child(@ptrCast(pkg_frame), pkg_box);
        
        // Package name and version header
        const pkg_header = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_box_append(@ptrCast(pkg_box), pkg_header);
        
        const pkg_icon = c.gtk_image_new_from_icon_name("package-x-generic");
        c.gtk_image_set_pixel_size(@ptrCast(pkg_icon), 24);
        c.gtk_box_append(@ptrCast(pkg_header), pkg_icon);
        
        var pkg_title_buf: [256]u8 = undefined;
        const pkg_title = std.fmt.bufPrintZ(&pkg_title_buf, "{s} {s}", .{info.name, info.version}) catch "";
        const pkg_title_label = c.gtk_label_new(pkg_title.ptr);
        c.gtk_widget_set_halign(pkg_title_label, c.GTK_ALIGN_START);
        const title_attrs = c.pango_attr_list_new();
        const title_weight = c.pango_attr_weight_new(c.PANGO_WEIGHT_BOLD);
        c.pango_attr_list_insert(title_attrs, title_weight);
        c.gtk_label_set_attributes(@ptrCast(pkg_title_label), title_attrs);
        c.pango_attr_list_unref(title_attrs);
        c.gtk_box_append(@ptrCast(pkg_header), pkg_title_label);
        
        // Description
        if (info.description.len > 0) {
            const desc_label = c.gtk_label_new(info.description.ptr);
            c.gtk_widget_set_halign(desc_label, c.GTK_ALIGN_START);
            c.gtk_label_set_xalign(@ptrCast(desc_label), 0.0);
            c.gtk_label_set_wrap(@ptrCast(desc_label), 1);
            c.gtk_widget_add_css_class(desc_label, "caption");
            c.gtk_box_append(@ptrCast(pkg_box), desc_label);
        }
        
        // URL
        if (info.url.len > 0) {
            const url_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 4);
            c.gtk_box_append(@ptrCast(pkg_box), url_box);
            
            const url_label_title = c.gtk_label_new("URL:");
            c.gtk_widget_add_css_class(url_label_title, "dim-label");
            c.gtk_widget_add_css_class(url_label_title, "caption");
            c.gtk_box_append(@ptrCast(url_box), url_label_title);
            
            const url_label = c.gtk_label_new(info.url.ptr);
            c.gtk_widget_add_css_class(url_label, "caption");
            c.gtk_label_set_xalign(@ptrCast(url_label), 0.0);
            const url_attrs = c.pango_attr_list_new();
            const url_mono = c.pango_attr_family_new("monospace");
            c.pango_attr_list_insert(url_attrs, url_mono);
            c.gtk_label_set_attributes(@ptrCast(url_label), url_attrs);
            c.pango_attr_list_unref(url_attrs);
            c.gtk_box_append(@ptrCast(url_box), url_label);
        }
        
        // License
        if (info.license.len > 0) {
            const lic_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 4);
            c.gtk_box_append(@ptrCast(pkg_box), lic_box);
            
            const lic_label_title = c.gtk_label_new("License:");
            c.gtk_widget_add_css_class(lic_label_title, "dim-label");
            c.gtk_widget_add_css_class(lic_label_title, "caption");
            c.gtk_box_append(@ptrCast(lic_box), lic_label_title);
            
            const lic_label = c.gtk_label_new(info.license.ptr);
            c.gtk_widget_add_css_class(lic_label, "caption");
            c.gtk_box_append(@ptrCast(lic_box), lic_label);
        }
    }
    
    // Exec line
    if (entry.exec.len > 0) {
        const exec_frame = c.gtk_frame_new(null);
        c.gtk_box_append(@ptrCast(content_area), exec_frame);
        
        const exec_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
        c.gtk_widget_set_margin_start(exec_box, 8);
        c.gtk_widget_set_margin_end(exec_box, 8);
        c.gtk_widget_set_margin_top(exec_box, 8);
        c.gtk_widget_set_margin_bottom(exec_box, 8);
        c.gtk_frame_set_child(@ptrCast(exec_frame), exec_box);
        
        const exec_title = c.gtk_label_new("Exec:");
        c.gtk_widget_add_css_class(exec_title, "dim-label");
        c.gtk_widget_add_css_class(exec_title, "caption");
        c.gtk_box_append(@ptrCast(exec_box), exec_title);
        
        const exec_z = allocator.dupeZ(u8, entry.exec) catch return;
        defer allocator.free(exec_z);
        const exec_label = c.gtk_label_new(exec_z.ptr);
        c.gtk_label_set_xalign(@ptrCast(exec_label), 0.0);
        c.gtk_widget_set_hexpand(exec_label, 1);
        const exec_attrs = c.pango_attr_list_new();
        const exec_mono = c.pango_attr_family_new("monospace");
        const exec_size = c.pango_attr_size_new(9 * c.PANGO_SCALE);
        c.pango_attr_list_insert(exec_attrs, exec_mono);
        c.pango_attr_list_insert(exec_attrs, exec_size);
        c.gtk_label_set_attributes(@ptrCast(exec_label), exec_attrs);
        c.pango_attr_list_unref(exec_attrs);
        c.gtk_box_append(@ptrCast(exec_box), exec_label);
    }
    
    // Buttons
    const action_box = c.gtk_box_new(c.GTK_ORIENTATION_HORIZONTAL, 8);
    c.gtk_widget_set_halign(action_box, c.GTK_ALIGN_END);
    c.gtk_widget_set_margin_top(action_box, 12);
    c.gtk_box_append(@ptrCast(content_area), action_box);
    
    // Close button
    const close_btn = c.gtk_button_new_with_label("Close");
    c.gtk_widget_add_css_class(close_btn, "pill");
    _ = c.g_signal_connect_data(close_btn, "clicked", @ptrCast(&onCloseClicked), dialog, null, c.G_CONNECT_DEFAULT);
    c.gtk_box_append(@ptrCast(action_box), close_btn);
    
    // Create a cleanup structure to track all allocations
    const cleanup_data = allocator.create(DialogCleanupData) catch return;
    cleanup_data.* = .{ .detail_data = null, .open_data = null };
    
    // Connect destroy handler first (before any early returns)
    _ = c.g_signal_connect_data(dialog, "destroy", @ptrCast(&onDialogDestroy), cleanup_data, null, c.G_CONNECT_DEFAULT);
    
    // Store path in dialog for use by callbacks
    // Allocate with glib allocator so g_free works
    const path_copy = c.g_strdup(entry.path.ptr);
    _ = c.g_object_set_data_full(@ptrCast(dialog), "desktop-file-path", path_copy, @ptrCast(&c.g_free));

    // Choose Application button
    const choose_btn = c.gtk_button_new_with_label("Choose Application...");
    c.gtk_widget_add_css_class(choose_btn, "pill");
    
    // Store data for choose button callback
    const response_path = allocator.dupeZ(u8, entry.path) catch {
        c.gtk_window_destroy(@ptrCast(dialog));
        return;
    };
    const detail_data = allocator.create(DetailDialogData) catch {
        allocator.free(response_path);
        c.gtk_window_destroy(@ptrCast(dialog));
        return;
    };
    // We need to store pkg_info pointer - allocate it separately for the callback
    const pkg_info_for_cb = allocator.create(PackageInfo) catch {
        allocator.free(response_path);
        allocator.destroy(detail_data);
        c.gtk_window_destroy(@ptrCast(dialog));
        return;
    };
    if (pkg_info) |info| {
        pkg_info_for_cb.* = info;
    } else {
        pkg_info_for_cb.* = .{
            .name = "",
            .version = "",
            .description = "",
            .url = "",
            .license = "",
            .depends = "",
        };
    }
    detail_data.* = .{ .path = response_path, .pkg_info = pkg_info_for_cb };
    cleanup_data.detail_data = detail_data;
    
    _ = c.g_signal_connect_data(choose_btn, "clicked", @ptrCast(&onChooseAppClicked), detail_data, null, c.G_CONNECT_DEFAULT);
    c.gtk_box_append(@ptrCast(action_box), choose_btn);
    
    // Open in Default Editor button (if we have a package)
    if (pkg_info != null) {
        const open_btn = c.gtk_button_new_with_label("Open in Default Editor");
        c.gtk_widget_add_css_class(open_btn, "pill");
        c.gtk_widget_add_css_class(open_btn, "suggested-action");
        
        const open_path = allocator.dupeZ(u8, entry.path) catch {
            c.gtk_window_destroy(@ptrCast(dialog));
            return;
        };
        const open_data = allocator.create(ResponseData) catch {
            allocator.free(open_path);
            c.gtk_window_destroy(@ptrCast(dialog));
            return;
        };
        open_data.* = .{ .path = open_path };
        cleanup_data.open_data = open_data;
        
        _ = c.g_signal_connect_data(open_btn, "clicked", @ptrCast(&onOpenDefaultClicked), open_data, null, c.G_CONNECT_DEFAULT);
        c.gtk_box_append(@ptrCast(action_box), open_btn);
    }

    c.gtk_widget_show(@ptrCast(dialog));
    
    // Clean up package info after dialog is shown (GTK has copied the strings)
    if (pkg_info) |*info| {
        freePackageInfo(info);
    }
}

export fn onCloseClicked(btn: *c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    _ = btn;
    const dialog: *c.GtkDialog = @ptrCast(@alignCast(user_data));
    c.gtk_window_destroy(@ptrCast(dialog));
}

export fn onDialogDestroy(dialog: *c.GtkDialog, user_data: ?*anyopaque) callconv(.c) void {
    _ = dialog;
    const cleanup: *DialogCleanupData = @ptrCast(@alignCast(user_data));
    
    // Free detail_data if it wasn't consumed
    if (cleanup.detail_data) |detail| {
        allocator.free(detail.path);
        if (detail.pkg_info.name_owned) allocator.free(detail.pkg_info.name);
        if (detail.pkg_info.version_owned) allocator.free(detail.pkg_info.version);
        if (detail.pkg_info.description_owned) allocator.free(detail.pkg_info.description);
        if (detail.pkg_info.url_owned) allocator.free(detail.pkg_info.url);
        if (detail.pkg_info.license_owned) allocator.free(detail.pkg_info.license);
        if (detail.pkg_info.depends_owned) allocator.free(detail.pkg_info.depends);
        allocator.destroy(detail.pkg_info);
        allocator.destroy(detail);
    }
    
    // Free open_data if it wasn't consumed
    if (cleanup.open_data) |open| {
        allocator.free(open.path);
        allocator.destroy(open);
    }
    
    allocator.destroy(cleanup);
}

export fn onChooseAppClicked(btn: *c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    const data: *DetailDialogData = @ptrCast(@alignCast(user_data));
    
    // Find the parent dialog from the button
    const button_widget: *c.GtkWidget = @ptrCast(btn);
    const dialog_root = c.gtk_widget_get_root(button_widget);
    const dialog: *c.GtkDialog = @ptrCast(@alignCast(dialog_root));
    
    // Create app chooser dialog
    const app_dialog = c.gtk_app_chooser_dialog_new_for_content_type(
        @ptrCast(main_window),
        c.GTK_DIALOG_MODAL | c.GTK_DIALOG_DESTROY_WITH_PARENT,
        "application/x-desktop",
    );
    
    c.gtk_window_set_title(@ptrCast(app_dialog), "Choose Editor");
    c.gtk_window_set_default_size(@ptrCast(app_dialog), 500, 400);
    
    _ = c.gtk_dialog_add_button(@ptrCast(app_dialog), "Cancel", c.GTK_RESPONSE_CANCEL);
    _ = c.gtk_dialog_add_button(@ptrCast(app_dialog), "Open", c.GTK_RESPONSE_ACCEPT);
    
    // Create response data with the path (transfer ownership from detail_data)
    const response_path = allocator.dupeZ(u8, data.path) catch return;
    const response_data = allocator.create(ResponseData) catch {
        allocator.free(response_path);
        return;
    };
    response_data.* = .{ .path = response_path };
    
    _ = c.g_signal_connect_data(app_dialog, "response", @ptrCast(&onEditorResponse), response_data, null, c.G_CONNECT_DEFAULT);
    
    c.gtk_widget_show(@ptrCast(app_dialog));
    
    // Close parent detail dialog (destroy handler will clean up)
    c.gtk_window_destroy(@ptrCast(dialog));
}

export fn onOpenDefaultClicked(btn: *c.GtkButton, user_data: ?*anyopaque) callconv(.c) void {
    _ = user_data; // Will be freed by destroy handler
    
    // Find the parent dialog from the button
    const button_widget: *c.GtkWidget = @ptrCast(btn);
    const dialog_root = c.gtk_widget_get_root(button_widget);
    const dialog: *c.GtkDialog = @ptrCast(@alignCast(dialog_root));
    
    // Get the path from the dialog's data
    const path_ptr: ?*anyopaque = c.g_object_get_data(@ptrCast(@alignCast(dialog)), "desktop-file-path");
    if (path_ptr == null) return;
    const path: [:0]const u8 = @ptrCast(path_ptr);
    
    // Open with default app for application/x-desktop
    const file = c.g_file_new_for_path(path.ptr);
    const file_list: ?*c.GList = c.g_list_append(null, file);
    
    // Get default app for application/x-desktop
    const app_info = c.g_app_info_get_default_for_type("application/x-desktop", 0);
    if (app_info) |info| {
        var gerror: ?*c.GError = null;
        _ = c.g_app_info_launch(info, file_list, null, &gerror);
        if (gerror) |err| {
            c.g_print("Error launching: %s\n", err.*.message);
            c.g_error_free(err);
        }
        c.g_object_unref(info);
    }
    
    c.g_list_free(file_list);
    c.g_object_unref(file);
    
    // Close the detail dialog
    c.gtk_window_destroy(@ptrCast(dialog));
}

export fn onEditorResponse(dialog: *c.GtkAppChooserDialog, response_id: c_int, user_data: ?*anyopaque) callconv(.c) void {
    const data: *ResponseData = @ptrCast(@alignCast(user_data));
    
    if (response_id == c.GTK_RESPONSE_ACCEPT) {
        const app_info = c.gtk_app_chooser_get_app_info(@ptrCast(dialog));
        if (app_info) |info| {
            // Create GFile for the desktop file
            const file = c.g_file_new_for_path(data.path.ptr);
            
            // Create GList with the file
            const file_list: ?*c.GList = c.g_list_append(null, file);
            
            // Launch the editor with the file
            var gerror: ?*c.GError = null;
            _ = c.g_app_info_launch(info, file_list, null, &gerror);
            if (gerror) |err| {
                c.g_print("Error launching editor: %s\n", err.*.message);
                c.g_error_free(err);
            }
            c.g_list_free(file_list);
            c.g_object_unref(file);
            c.g_object_unref(info);
        }
    }
    
    // Cleanup
    allocator.free(data.path);
    allocator.destroy(data);
    c.gtk_window_destroy(@ptrCast(@alignCast(dialog)));
}

fn updateResultsUI() callconv(.c) void {
    if (list_box == null or search_entry == null) return;

    // Clear existing rows
    var child = c.gtk_list_box_get_row_at_index(list_box, 0);
    while (child != null) {
        const next = c.gtk_list_box_get_row_at_index(list_box, c.gtk_list_box_row_get_index(child) + 1);
        c.gtk_list_box_remove(list_box, @ptrCast(child));
        child = next;
    }

    // Add matching rows
    search_mutex.lock();
    defer search_mutex.unlock();

    const query_text = c.gtk_editable_get_text(@ptrCast(search_entry));
    const query = if (query_text != null) std.mem.span(query_text) else "";

    for (search_entries.items, 0..) |entry, index| {
        if (matchesSearch(&entry, query)) {
            if (createResultRow(&entry, index)) |row| {
                c.gtk_list_box_append(list_box, row);
            }
        }
    }

    // Show count
    var count_buf: [64]u8 = undefined;
    const count_text = std.fmt.bufPrintZ(&count_buf, "Found {} desktop files", .{search_entries.items.len}) catch return;
    if (title_label_widget) |tl| {
        c.gtk_label_set_text(@ptrCast(tl), count_text.ptr);
    }
}

export fn onSearchChanged(entry: *c.GtkSearchEntry, user_data: ?*anyopaque) callconv(.c) void {
    _ = entry;
    _ = user_data;
    updateResultsUI();
}

export fn onRowActivated(box: *c.GtkListBox, row: *c.GtkListBoxRow, user_data: ?*anyopaque) callconv(.c) void {
    _ = box;
    _ = user_data;

    const child = c.gtk_list_box_row_get_child(row);
    const index_str = c.gtk_widget_get_name(child);
    const index = std.fmt.parseInt(usize, std.mem.span(index_str), 10) catch return;

    search_mutex.lock();
    defer search_mutex.unlock();

    if (index < search_entries.items.len) {
        // Copy the entry to a local variable while holding the lock
        const entry_copy = search_entries.items[index];
        showDetailDialog(&entry_copy);
    }
}

export fn onActivate(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
    _ = user_data;

    const window = c.gtk_application_window_new(app);
    main_window = window;
    c.gtk_window_set_title(@ptrCast(window), "Desktop File Search");
    c.gtk_window_set_default_size(@ptrCast(window), 800, 600);

    // Main container
    const main_box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 12);
    c.gtk_widget_set_margin_start(main_box, 12);
    c.gtk_widget_set_margin_end(main_box, 12);
    c.gtk_widget_set_margin_top(main_box, 12);
    c.gtk_widget_set_margin_bottom(main_box, 12);
    c.gtk_window_set_child(@ptrCast(window), main_box);

    // Header with title
    title_label_widget = c.gtk_label_new("Scanning for desktop files...");
    c.gtk_widget_set_halign(title_label_widget, c.GTK_ALIGN_START);
    const title_attrs = c.pango_attr_list_new();
    const size_attr = c.pango_attr_size_new(14 * c.PANGO_SCALE);
    c.pango_attr_list_insert(title_attrs, size_attr);
    c.gtk_label_set_attributes(@ptrCast(title_label_widget), title_attrs);
    c.pango_attr_list_unref(title_attrs);
    c.gtk_box_append(@ptrCast(main_box), title_label_widget);

    // Search entry
    const search_entry_widget = c.gtk_search_entry_new();
    search_entry = @ptrCast(search_entry_widget);
    c.gtk_search_entry_set_placeholder_text(search_entry, "Search desktop files...");
    c.gtk_widget_set_size_request(search_entry_widget, 300, -1);
    c.gtk_box_append(@ptrCast(main_box), search_entry_widget);

    // Scrolled window for results
    const scrolled = c.gtk_scrolled_window_new();
    c.gtk_widget_set_vexpand(scrolled, 1);
    c.gtk_scrolled_window_set_policy(@ptrCast(scrolled), c.GTK_POLICY_NEVER, c.GTK_POLICY_AUTOMATIC);
    c.gtk_box_append(@ptrCast(main_box), scrolled);

    // Results list
    const list_box_widget = c.gtk_list_box_new();
    list_box = @ptrCast(list_box_widget);
    c.gtk_list_box_set_selection_mode(list_box, c.GTK_SELECTION_SINGLE);
    c.gtk_scrolled_window_set_child(@ptrCast(scrolled), list_box_widget);

    // Connect signals
    _ = c.g_signal_connect_data(search_entry_widget, "search-changed", @ptrCast(&onSearchChanged), null, null, c.G_CONNECT_DEFAULT);
    _ = c.g_signal_connect_data(list_box_widget, "row-activated", @ptrCast(&onRowActivated), null, null, c.G_CONNECT_DEFAULT);

    c.gtk_window_present(@ptrCast(window));

    // Start scanning in background
    search_cancelled = false;
    search_thread = std.Thread.spawn(.{}, scanThreadWrapper, .{}) catch null;
}

fn scanThreadWrapper() void {
    scanAllDirectories();
    // Schedule UI update on main thread using idle callback
    _ = c.g_idle_add(@ptrCast(&idleCallback), null);
}

export fn idleCallback(user_data: ?*anyopaque) callconv(.c) c.gboolean {
    _ = user_data;
    updateResultsUI();
    return c.G_SOURCE_REMOVE;
}

export fn onShutdown(app: *c.GtkApplication, user_data: ?*anyopaque) callconv(.c) void {
    _ = app;
    _ = user_data;

    search_cancelled = true;
    if (search_thread) |t| {
        t.join();
    }

    freeDesktopEntries(&search_entries);
}

pub fn main() void {
    defer _ = gpa.deinit();

    search_entries = DesktopEntryList.init(allocator);

    const app = c.gtk_application_new("com.example.desktopfilesearch", c.G_APPLICATION_DEFAULT_FLAGS);
    defer c.g_object_unref(app);

    _ = c.g_signal_connect_data(app, "activate", @ptrCast(&onActivate), null, null, c.G_CONNECT_DEFAULT);
    _ = c.g_signal_connect_data(app, "shutdown", @ptrCast(&onShutdown), null, null, c.G_CONNECT_DEFAULT);

    const status = c.g_application_run(@ptrCast(app), 0, null);
    _ = status;
}