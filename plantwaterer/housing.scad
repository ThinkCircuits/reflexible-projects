$fn = 128;

// Plant Waterer Enclosure
// Houses SparkFun Qwiic Twist, OLED 128x32, Pico W, and Single Relay
// Three printable parts: enclosure, lid, shelf

/* [Part Selection] */
// Which part to render (for STL export)
part = "assembly"; // [assembly:Assembly View, enclosure:Enclosure Only, lid:Lid Only, shelf:Shelf Only]

/* [Assembly View Options] */
show_enclosure = true;
show_lid = true;
show_shelf = true;
show_boards = true;  // Shadow models for visualization

/* [Enclosure Parameters] */
wall_thickness = 2.5;
corner_radius = 3;
lid_overlap = 4;        // How far lid overlaps into enclosure
board_clearance = 3;    // Clearance around boards
lid_clearance = 0.4;    // Clearance for lid lip fit

/* [Screw Parameters] */
m3_hole_dia = 3.4;      // Clearance hole for M3
m3_tap_dia = 2.5;       // Hole for self-tapping M3 into plastic
m3_head_dia = 6;        // M3 screw head diameter
screw_boss_dia = 7;

/* [Shelf Parameters] */
shelf_thickness = 2.5;
shelf_post_h = 12;          // Height of support posts in enclosure
shelf_post_dia = 6;         // Diameter of support posts (M3 self-tap)
shelf_post_inset_x = 6;     // Distance from inner wall (X)
shelf_post_front_y = 10;    // Distance from front inner wall
shelf_post_back_y = 25;     // Distance from back inner wall (avoids capacitor)
shelf_standoff_h = 3;       // Height of board standoffs on shelf
shelf_clearance = 2;        // Clearance around shelf edges
shelf_corner_notch = 10;    // Size of corner notches to clear lid gussets

/* [Board Dimensions - SparkFun Qwiic Twist] */
// RGB Rotary Encoder Breakout (DEV-15083)
twist_pcb_w = 25.4;
twist_pcb_l = 30.48;
twist_pcb_h = 1.6;
twist_encoder_dia = 12;
twist_encoder_h = 7;
twist_shaft_dia = 6;
twist_shaft_h = 15;
twist_total_h = 25;
twist_mount_hole_dia = 1.65;
twist_mount_spacing_x = 25.4;
twist_mount_spacing_y = 20.32;
twist_hole_edge_offset = 2.54;

/* [Board Dimensions - SparkFun OLED 128x32] */
// 0.91" OLED Display (LCD-24606 v1.1)
oled_pcb_w = 44.45;
oled_pcb_l = 12.7;
oled_pcb_h = 1.6;
oled_display_w = 32;
oled_display_l = 12;
oled_display_offset_x = (oled_pcb_w - oled_display_w) / 2;
oled_glass_h = 1.5;
oled_total_h = 4;
oled_mount_hole_dia = 2.5;
oled_mount_spacing = 38.61;
oled_hole_from_edge_x = 3.81;
oled_hole_from_edge_y = 2.54;

/* [Board Dimensions - SparkFun Qwiic Single Relay] */
relay_pcb_w = 27;
relay_pcb_l = 58;
relay_pcb_h = 1.6;
relay_component_h = 16;
relay_total_h = 20;
relay_mount_hole_dia = 1.65;
relay_mount_spacing_x = 20.32;
relay_mount_spacing_y = 50.8;
relay_hole_edge_offset = 3.0;

/* [Board Dimensions - Raspberry Pi Pico W] */
pico_pcb_w = 21;
pico_pcb_l = 51;
pico_pcb_h = 1.0;
pico_total_h = 3.5;
pico_usb_w = 8;
pico_usb_l = 7.5;
pico_usb_h = 3;
pico_mount_hole_dia = 2.1;
pico_hole_from_end = 4.8;
pico_hole_from_side = 2.4;
pico_hole_spacing_x = pico_pcb_w - 2*pico_hole_from_side;
pico_hole_spacing_y = pico_pcb_l - 2*pico_hole_from_end;

/* [Component Dimensions - Filtering Capacitor] */
cap_dia = 13.5;
cap_h = 31;
cap_lead_dia = 0.8;
cap_lead_len = 6;

// ============================================================
// CALCULATED DIMENSIONS
// ============================================================

// Interior dimensions
floor_boards_w = pico_pcb_w + relay_pcb_w + 1.5 + 2*1;
interior_w = max(oled_pcb_w + 2*1, floor_boards_w);
interior_l = relay_pcb_l + board_clearance + 12.5;
interior_h = max(relay_total_h + 10, cap_h + 5);

// Enclosure outer dimensions
enclosure_w = interior_w + 2*wall_thickness;
enclosure_l = interior_l + 2*wall_thickness;
enclosure_h = interior_h + wall_thickness;

// Shelf dimensions
shelf_w = interior_w - 2*shelf_clearance;
shelf_l = interior_l - 2*shelf_clearance;

// Front board standoff heights
twist_standoff_h = twist_encoder_h + 2;
oled_standoff_h = 1;
twist_rot = 90;

// Board positions
twist_x = 0;
twist_y = interior_l/2 - twist_pcb_l/2 - board_clearance - 4;
oled_x = 0;
oled_y = -interior_l/2 + oled_pcb_l/2 + board_clearance + 7;
relay_x = interior_w/2 - relay_pcb_w/2 - 1;
relay_y = 0;
pico_x = -interior_w/2 + pico_pcb_w/2 + 1;
pico_y = 0;
cap_x = 0;
cap_y = interior_l/2 - cap_dia/2 - board_clearance;

// Z positions
shelf_z = wall_thickness + shelf_post_h;
board_z = shelf_z + shelf_thickness + shelf_standoff_h;

// ============================================================
// SHADOW MODELS (for visualization)
// ============================================================

module qwiic_twist_shadow() {
    color("green", 0.7) {
        cube([twist_pcb_w, twist_pcb_l, twist_pcb_h], center=true);
        translate([0, 0, twist_pcb_h/2 + twist_encoder_h/2])
            cylinder(d=twist_encoder_dia, h=twist_encoder_h, center=true);
        translate([0, 0, twist_pcb_h/2 + twist_encoder_h + twist_shaft_h/2])
            cylinder(d=twist_shaft_dia, h=twist_shaft_h, center=true);
        translate([0, -twist_pcb_l/2 + 4, -twist_pcb_h/2 - 2])
            cube([8, 6, 4], center=true);
        translate([0, twist_pcb_l/2 - 4, -twist_pcb_h/2 - 2])
            cube([8, 6, 4], center=true);
    }
}

module qwiic_oled_shadow() {
    color("purple", 0.7) {
        cube([oled_pcb_w, oled_pcb_l, oled_pcb_h], center=true);
        display_center_x = -oled_pcb_w/2 + oled_display_offset_x + oled_display_w/2;
        translate([display_center_x, 0, oled_pcb_h/2 + oled_glass_h/2])
            cube([oled_display_w + 2, oled_display_l + 2, oled_glass_h], center=true);
        color("black", 0.9)
        translate([display_center_x, 0, oled_pcb_h/2 + oled_glass_h + 0.1])
            cube([oled_display_w, oled_display_l, 0.2], center=true);
        translate([-oled_pcb_w/2 + 5, 0, -oled_pcb_h/2 - 2])
            cube([6, 8, 4], center=true);
    }
}

module qwiic_relay_shadow() {
    color("red", 0.7) {
        cube([relay_pcb_w, relay_pcb_l, relay_pcb_h], center=true);
        translate([0, -5, relay_pcb_h/2 + relay_component_h/2])
            cube([15, 20, relay_component_h], center=true);
        translate([0, relay_pcb_l/2 - 8, relay_pcb_h/2 + 5])
            cube([relay_pcb_w - 4, 10, 10], center=true);
        translate([0, -relay_pcb_l/2 + 4, -relay_pcb_h/2 - 2])
            cube([8, 6, 4], center=true);
    }
}

module pico_w_shadow() {
    color("green", 0.7) {
        cube([pico_pcb_w, pico_pcb_l, pico_pcb_h], center=true);
        translate([0, -pico_pcb_l/2 - pico_usb_l/2 + 2, pico_pcb_h/2 + pico_usb_h/2 - 1])
            cube([pico_usb_w, pico_usb_l, pico_usb_h], center=true);
        translate([0, 5, pico_pcb_h/2 + 1])
            cube([7, 7, 1], center=true);
        translate([0, -10, pico_pcb_h/2 + 1.2])
            cube([10, 12, 2], center=true);
        for (side = [-1, 1])
            translate([side * (pico_pcb_w/2 - 1), 0, pico_pcb_h/2 + 0.2])
                cube([2, 46, 0.3], center=true);
    }
}

module capacitor_shadow() {
    color("darkblue", 0.7) {
        cylinder(d=cap_dia, h=cap_h, center=true);
        translate([0, 0, cap_h/2 - 0.5])
            cylinder(d=cap_dia - 2, h=1, center=true);
    }
    color("gray", 0.8)
        translate([cap_dia/2 - 0.5, 0, 0])
            cube([1, 3, cap_h - 4], center=true);
    color("silver", 0.9) {
        translate([0, 0, -cap_h/2 - cap_lead_len/2])
            cylinder(d=cap_lead_dia, h=cap_lead_len, center=true);
        translate([0, 0, cap_h/2 + cap_lead_len/2])
            cylinder(d=cap_lead_dia, h=cap_lead_len, center=true);
    }
}

// ============================================================
// COMMON MODULES
// ============================================================

module rounded_box(w, l, h, r) {
    hull() {
        for (x = [-w/2 + r, w/2 - r])
            for (y = [-l/2 + r, l/2 - r])
                translate([x, y, 0])
                    cylinder(r=r, h=h);
    }
}

module lid_screw_positions() {
    inner_w = enclosure_w - 2*wall_thickness;
    inner_l = enclosure_l - 2*wall_thickness;
    offset = screw_boss_dia/2 - 1;
    for (sx = [-1, 1])
        for (sy = [-1, 1])
            translate([sx * (inner_w/2 - offset), sy * (inner_l/2 - offset), 0])
                children();
}

module shelf_screw_positions() {
    // Single front post - centered, between OLED and front wall
    translate([0, oled_y - oled_pcb_l/2 - 5, 0])
        children();
    // Back posts (moved forward to avoid capacitor)
    for (sx = [-1, 1])
        translate([sx * (interior_w/2 - shelf_post_inset_x),
                   interior_l/2 - shelf_post_back_y, 0])
            children();
}

// ============================================================
// ENCLOSURE
// ============================================================

module enclosure_body() {
    display_margin = 2;
    display_center_x = -oled_pcb_w/2 + oled_display_offset_x + oled_display_w/2;
    oled_cutout_x = oled_x + display_center_x;
    oled_cutout_y = oled_y;

    difference() {
        rounded_box(enclosure_w, enclosure_l, enclosure_h, corner_radius);

        // Inner cavity
        translate([0, 0, wall_thickness])
            rounded_box(
                enclosure_w - 2*wall_thickness,
                enclosure_l - 2*wall_thickness,
                enclosure_h,
                max(1, corner_radius - wall_thickness)
            );

        // Encoder shaft hole
        translate([twist_x, twist_y, -1])
            cylinder(d=twist_shaft_dia + 1, h=wall_thickness + 2);

        // OLED display window
        translate([oled_cutout_x, oled_cutout_y, (wall_thickness + enclosure_h)/2])
            cube([oled_display_w + 2*display_margin, oled_display_l + 2*display_margin, enclosure_h - wall_thickness + 10], center=true);

        // Relay wiring notch - rectangular slot from top of oval to top of wall
        relay_hole_w = 2.25 * 3;  // oval width
        relay_hole_h = 2.25;      // oval height
        // Slot from top of oval upward
        translate([relay_x + 2.25, enclosure_l/2 - wall_thickness/2, enclosure_h - (lid_overlap - relay_hole_h/2)/2])
            cube([relay_hole_w, wall_thickness + 2, lid_overlap - relay_hole_h/2 + 1], center=true);
        // Oval at bottom (extend upward to ensure clean cut)
        translate([relay_x, enclosure_l/2 - wall_thickness/2, enclosure_h - lid_overlap])
            rotate([90, 0, 0])
                hull() {
                    cylinder(d=relay_hole_h, h=wall_thickness + 2, center=true);
                    translate([2.25*2, 0, 0]) cylinder(d=relay_hole_h, h=wall_thickness + 2, center=true);
                }

        // I2C wiring notch - rectangular slot from top of circle to top of wall
        i2c_hole_d = 2;
        // Slot from top of circle upward
        translate([-10, enclosure_l/2 - wall_thickness/2, enclosure_h - (lid_overlap - i2c_hole_d/2)/2])
            cube([i2c_hole_d, wall_thickness + 2, lid_overlap - i2c_hole_d/2 + 1], center=true);
        // Circle at bottom
        translate([-10, enclosure_l/2 - wall_thickness/2, enclosure_h - lid_overlap])
            rotate([90, 0, 0])
                cylinder(d=i2c_hole_d, h=wall_thickness + 2, center=true);

        // Lid screw holes
        lid_screw_positions()
            translate([0, 0, enclosure_h - lid_overlap])
                cylinder(d=m3_tap_dia, h=lid_overlap + 1);
    }

    // Twist mounting posts
    color("gray") {
        post_x_offset = twist_pcb_w/2 - twist_hole_edge_offset;
        post_y_offset = twist_pcb_l/2 - twist_hole_edge_offset;
        translate([twist_x, twist_y, wall_thickness])
            rotate([0, 0, twist_rot])
                for (dx = [-post_x_offset, post_x_offset])
                    for (dy = [-post_y_offset, post_y_offset])
                        translate([dx, dy, 0])
                            difference() {
                                cylinder(d=5, h=twist_standoff_h);
                                cylinder(d=1.8, h=twist_standoff_h + 1);
                            }
    }

    // OLED mounting posts (rotated 180deg, holes now on -Y side)
    oled_hole_y_offset = oled_pcb_l/2 - oled_hole_from_edge_y;
    color("gray") {
        for (dx = [-oled_mount_spacing/2, oled_mount_spacing/2])
            translate([oled_x + dx, oled_y - oled_hole_y_offset, wall_thickness])
                difference() {
                    cylinder(d=5, h=oled_standoff_h);
                    cylinder(d=1.8, h=oled_standoff_h + 1);
                    translate([oled_cutout_x - (oled_x + dx), oled_cutout_y - (oled_y - oled_hole_y_offset), (enclosure_h - wall_thickness)/2])
                        cube([oled_display_w + 2*display_margin, oled_display_l + 2*display_margin, enclosure_h - wall_thickness + 10], center=true);
                }
    }

    // Shelf support posts
    color("gray")
        shelf_screw_positions()
            translate([0, 0, wall_thickness])
                difference() {
                    cylinder(d=shelf_post_dia, h=shelf_post_h);
                    cylinder(d=m3_tap_dia, h=shelf_post_h + 1);
                }

    // Lid screw gussets
    boss_h = enclosure_h - wall_thickness - 0.5;
    gusset_len = 6;
    inner_half_w = (enclosure_w - 2*wall_thickness) / 2;
    inner_half_l = (enclosure_l - 2*wall_thickness) / 2;
    boss_inset = screw_boss_dia/2 - 1;

    for (sx = [-1, 1])
        for (sy = [-1, 1]) {
            corner_x = sx * inner_half_w;
            corner_y = sy * inner_half_l;
            screw_x = corner_x - sx * boss_inset;
            screw_y = corner_y - sy * boss_inset;

            difference() {
                translate([0, 0, wall_thickness])
                    hull() {
                        translate([screw_x, screw_y, 0])
                            cylinder(d=screw_boss_dia, h=boss_h);
                        translate([corner_x, corner_y, 0])
                            cylinder(d=3, h=boss_h);
                        translate([corner_x - sx*gusset_len, corner_y, 0])
                            cylinder(d=3, h=boss_h);
                        translate([corner_x, corner_y - sy*gusset_len, 0])
                            cylinder(d=3, h=boss_h);
                    }

                translate([screw_x, screw_y, wall_thickness + boss_h - lid_overlap - 0.5])
                    cylinder(d=m3_tap_dia, h=lid_overlap + 2);

                translate([oled_cutout_x, oled_cutout_y, (wall_thickness + enclosure_h)/2])
                    cube([oled_display_w + 2*display_margin, oled_display_l + 2*display_margin, enclosure_h], center=true);
            }
        }
}

// ============================================================
// LID
// ============================================================

module enclosure_lid() {
    difference() {
        union() {
            rounded_box(enclosure_w, enclosure_l, wall_thickness, corner_radius);
            translate([0, 0, -lid_overlap + wall_thickness])
                rounded_box(
                    enclosure_w - 2*wall_thickness - lid_clearance,
                    enclosure_l - 2*wall_thickness - lid_clearance,
                    lid_overlap,
                    max(1, corner_radius - wall_thickness)
                );
        }

        lid_screw_positions()
            translate([0, 0, -lid_overlap]) {
                cylinder(d=m3_hole_dia, h=wall_thickness + lid_overlap + 1);
                translate([0, 0, lid_overlap])
                    cylinder(d=m3_head_dia, h=wall_thickness + 1);
            }

        // Ventilation slots
        for (i = [-1:1])
            translate([i * 12, 0, -1])
                cube([4, enclosure_l - 25, wall_thickness + 2], center=true);
    }

    // Relay wiring tab - fills rectangular slot, semicircle cutout at bottom
    relay_hole_w = 2.25 * 3;
    relay_hole_h = 2.25;
    tab_clearance = 0.3;  // Clearance for sliding fit
    difference() {
        translate([relay_x + 2.25, enclosure_l/2 - wall_thickness/2, -lid_overlap/2])
            cube([relay_hole_w - tab_clearance, wall_thickness, lid_overlap], center=true);
        // Semicircle cutout at bottom
        translate([relay_x, enclosure_l/2 - wall_thickness/2, -lid_overlap])
            rotate([90, 0, 0])
                hull() {
                    cylinder(d=relay_hole_h, h=wall_thickness + 2, center=true);
                    translate([2.25*2, 0, 0]) cylinder(d=relay_hole_h, h=wall_thickness + 2, center=true);
                }
    }

    // I2C wiring tab - fills rectangular slot, semicircle cutout at bottom
    i2c_hole_d = 2;
    difference() {
        translate([-10, enclosure_l/2 - wall_thickness/2, -lid_overlap/2])
            cube([i2c_hole_d - tab_clearance, wall_thickness, lid_overlap], center=true);
        // Semicircle cutout at bottom
        translate([-10, enclosure_l/2 - wall_thickness/2, -lid_overlap])
            rotate([90, 0, 0])
                cylinder(d=i2c_hole_d, h=wall_thickness + 2, center=true);
    }
}

// ============================================================
// SHELF
// ============================================================

module component_shelf() {
    difference() {
        union() {
            translate([0, 0, shelf_thickness/2])
                cube([shelf_w, shelf_l, shelf_thickness], center=true);

            // Pico W standoffs
            for (dx = [-pico_hole_spacing_x/2, pico_hole_spacing_x/2])
                for (dy = [-pico_hole_spacing_y/2, pico_hole_spacing_y/2])
                    translate([pico_x + dx, pico_y + dy, shelf_thickness])
                        cylinder(d=5, h=shelf_standoff_h);

            // Relay standoffs
            for (dx = [-relay_mount_spacing_x/2, relay_mount_spacing_x/2])
                for (dy = [-relay_mount_spacing_y/2, relay_mount_spacing_y/2])
                    translate([relay_x + dx, relay_y + dy, shelf_thickness])
                        cylinder(d=5, h=shelf_standoff_h);
        }

        // Mounting screw holes (countersunk)
        shelf_screw_positions() {
            translate([0, 0, -1])
                cylinder(d=m3_hole_dia, h=shelf_thickness + 2);
            translate([0, 0, shelf_thickness - 1.5])
                cylinder(d=m3_head_dia, h=2);
        }

        // Pico screw holes
        for (dx = [-pico_hole_spacing_x/2, pico_hole_spacing_x/2])
            for (dy = [-pico_hole_spacing_y/2, pico_hole_spacing_y/2])
                translate([pico_x + dx, pico_y + dy, -1])
                    cylinder(d=2.2, h=shelf_thickness + shelf_standoff_h + 2);

        // Relay screw holes
        for (dx = [-relay_mount_spacing_x/2, relay_mount_spacing_x/2])
            for (dy = [-relay_mount_spacing_y/2, relay_mount_spacing_y/2])
                translate([relay_x + dx, relay_y + dy, -1])
                    cylinder(d=1.8, h=shelf_thickness + shelf_standoff_h + 2);

        // Cable routing cutout
        translate([0, 0, -1])
            cube([15, 30, shelf_thickness + 2], center=true);

        // Corner notches to clear lid gussets
        for (sx = [-1, 1])
            for (sy = [-1, 1])
                translate([sx * (shelf_w/2 - shelf_corner_notch/2 + 1),
                           sy * (shelf_l/2 - shelf_corner_notch/2 + 1), -1])
                    cube([shelf_corner_notch + 2, shelf_corner_notch + 2, shelf_thickness + 2], center=true);
    }
}

// ============================================================
// ASSEMBLY VIEW
// ============================================================

module assembly() {
    if (show_enclosure) {
        color("lightblue", 0.8)
            enclosure_body();
    }

    if (show_lid) {
        color("lightblue", 0.8)
            translate([0, 0, enclosure_h])
                enclosure_lid();
    }

    if (show_shelf) {
        color("orange", 0.8)
            translate([0, 0, shelf_z])
                component_shelf();
    }

    if (show_boards) {
        translate([twist_x, twist_y, wall_thickness + twist_standoff_h + twist_pcb_h/2])
            rotate([180, 0, twist_rot])
                qwiic_twist_shadow();

        translate([oled_x, oled_y, wall_thickness + oled_standoff_h + oled_pcb_h/2])
            rotate([180, 0, 180])
                qwiic_oled_shadow();

        translate([relay_x, relay_y, board_z + relay_pcb_h/2])
            qwiic_relay_shadow();

        translate([pico_x, pico_y, board_z + pico_pcb_h/2])
            pico_w_shadow();

        // Capacitor laying horizontally on top of Pico
        translate([pico_x, pico_y, board_z + pico_total_h + cap_dia/2])
            rotate([0, 90, 90])
                capacitor_shadow();
    }
}

// ============================================================
// PRINT MODULES (oriented for 3D printing)
// ============================================================

module enclosure_for_print() {
    translate([0, 0, enclosure_h])
        rotate([180, 0, 0])
            enclosure_body();
}

module lid_for_print() {
    enclosure_lid();
}

module shelf_for_print() {
    component_shelf();
}

// ============================================================
// RENDER
// ============================================================

if (part == "assembly") {
    assembly();
} else if (part == "enclosure") {
    enclosure_for_print();
} else if (part == "lid") {
    lid_for_print();
} else if (part == "shelf") {
    shelf_for_print();
}

// Dimensions output
echo(str("Enclosure: ", enclosure_w, " x ", enclosure_l, " x ", enclosure_h, " mm"));
echo(str("Interior: ", interior_w, " x ", interior_l, " x ", interior_h, " mm"));
echo(str("Shelf: ", shelf_w, " x ", shelf_l, " x ", shelf_thickness, " mm"));
