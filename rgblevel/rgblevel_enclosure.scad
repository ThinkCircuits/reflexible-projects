// RGB Level Enclosure
// Houses: Adafruit NeoPixel 8x8 Matrix, Raspberry Pi Pico, SparkFun BNO086 IMU
// Designed for thin profile with LED pass-through lid

$fn = 64;

/* [Part Selection] */
part = "assembly"; // [assembly:Assembly View, body:Body Only, lid:Lid Only]

/* [Assembly View Options] */
show_body = true;
show_lid = true;
show_components = true;     // Shadow models for visualization
explode_lid = true;        // Explode lid (with NeoPixel) upward
explode_distance = 25;      // Distance to explode lid

/* [Component Dimensions - Adafruit NeoPixel 8x8 Matrix] */
neopixel_pcb_w = 71.2;      // mm
neopixel_pcb_l = 71.2;      // mm
neopixel_pcb_h = 3.3;       // mm
neopixel_led_pitch = 8.9;   // ~71mm / 8 LEDs
neopixel_led_size = 5.0;    // 5050 SMD LED size
neopixel_led_offset = 4.45; // offset from edge to first LED center

/* [Component Dimensions - Raspberry Pi Pico] */
pico_pcb_w = 21;            // mm
pico_pcb_l = 51;            // mm
pico_pcb_h = 1.0;           // mm (PCB only)
pico_total_h = 3.5;         // with components
pico_usb_w = 8;
pico_usb_l = 7.5;
pico_usb_h = 3;
pico_hole_dia = 2.1;        // mounting hole diameter
pico_hole_from_end = 4.8;   // from short edge to hole center
pico_hole_from_side = 2.0;  // from long edge to hole center
pico_hole_spacing_x = pico_pcb_w - 2*pico_hole_from_side;
pico_hole_spacing_y = pico_pcb_l - 2*pico_hole_from_end;

/* [USB Port Cutout] */
usb_plug_w = 10;            // USB plug width (rounded oval)
usb_plug_h = 6;             // USB plug height

/* [Component Dimensions - SparkFun BNO086 IMU] */
bno_pcb_w = 25.4;           // mm (1 inch)
bno_pcb_l = 30.5;           // mm (1.2 inch)
bno_pcb_h = 1.6;            // PCB thickness
bno_total_h = 4;            // with components
bno_hole_dia = 2.4;         // M2.5 compatible hole
bno_hole_spacing_y = 25.4;  // hole spacing along length (1.0")
bno_hole_edge_offset = 2.54; // offset from edge

/* [Enclosure Parameters] */
wall_thickness = 2.5;
corner_radius = 3;
floor_thickness = 2.0;      // mm
lid_thickness = 1.5;        // mm - thin lid so LEDs poke through
lid_overlap = 4;            // How far lid overlaps into enclosure
lid_clearance = 0.4;        // Clearance for lid lip fit
inner_clearance = 1.0;      // clearance around components

/* [Screw Parameters] */
m3_hole_dia = 3.4;          // Clearance hole for M3
m3_tap_dia = 2.5;           // Hole for self-tapping M3 into plastic
m3_head_dia = 6;            // M3 screw head diameter
screw_boss_dia = 7;

m2_tap_dia = 1.8;           // M2 tap hole for Pico
m2_screw_post_dia = 5.0;    // diameter of screw post

// ============================================================
// CALCULATED DIMENSIONS
// ============================================================

// Interior dimensions - sized so NeoPixel fits inside corner screw bosses
// Need clearance for screw_boss_dia on each side plus inner_clearance
interior_w = neopixel_pcb_w + 2 * screw_boss_dia + 2 * inner_clearance;
interior_l = neopixel_pcb_l + 2 * screw_boss_dia + 2 * inner_clearance;

// Height: floor + component clearance underneath + neopixel
component_stack_height = 8;  // space for Pico + BNO underneath NeoPixel
interior_h = component_stack_height + neopixel_pcb_h + 2;

// Enclosure outer dimensions
enclosure_w = interior_w + 2*wall_thickness;
enclosure_l = interior_l + 2*wall_thickness;
enclosure_h = interior_h + floor_thickness;

// Component positions (centered coordinate system)
// Pico centered at front, USB port facing front wall, pulled back 4mm from edge
pico_x = 0;  // centered
pico_y = -interior_l/2 + pico_pcb_l/2 + 5;  // USB end near front wall, +4mm back

// BNO086 positioned to the side of the Pico
bno_x = pico_x + pico_pcb_w/2 + bno_pcb_w/2 + 2;  // to the right of Pico with 2mm gap
bno_y = pico_y - pico_pcb_l/2 + bno_pcb_l/2;  // aligned with front of Pico

// NeoPixel mounted against underside of lid (LEDs facing up through holes)
neopixel_z = enclosure_h - neopixel_pcb_h;  // top of NeoPixel touches lid

// ============================================================
// SHADOW MODELS (for visualization)
// ============================================================

module neopixel_shadow() {
    color("green", 0.7) {
        // PCB
        cube([neopixel_pcb_w, neopixel_pcb_l, neopixel_pcb_h], center=true);
        // LEDs as small bumps
        for (i = [0:7])
            for (j = [0:7]) {
                led_x = -neopixel_pcb_w/2 + neopixel_led_offset + i * neopixel_led_pitch;
                led_y = -neopixel_pcb_l/2 + neopixel_led_offset + j * neopixel_led_pitch;
                translate([led_x, led_y, neopixel_pcb_h/2])
                    color("white", 0.9)
                        cube([neopixel_led_size, neopixel_led_size, 1], center=true);
            }
        // Qwiic connectors on sides
        translate([0, -neopixel_pcb_l/2 + 4, -neopixel_pcb_h/2 - 1])
            cube([8, 6, 2], center=true);
        translate([0, neopixel_pcb_l/2 - 4, -neopixel_pcb_h/2 - 1])
            cube([8, 6, 2], center=true);
    }
}

module pico_shadow() {
    color("green", 0.7) {
        // PCB
        cube([pico_pcb_w, pico_pcb_l, pico_pcb_h], center=true);
        // USB connector (at -Y end, overhanging PCB edge)
        translate([0, -pico_pcb_l/2, pico_pcb_h/2 + pico_usb_h/2])
            color("silver", 0.9)
                cube([pico_usb_w, pico_usb_l, pico_usb_h], center=true);
        // RP2040 chip
        translate([0, 5, pico_pcb_h/2 + 0.5])
            cube([7, 7, 1], center=true);
        // Wireless module (Pico W)
        translate([0, -10, pico_pcb_h/2 + 1])
            color("silver", 0.8)
                cube([10, 12, 2], center=true);
        // Pin headers (ghost)
        for (side = [-1, 1])
            translate([side * (pico_pcb_w/2 - 1), 0, pico_pcb_h/2 + 0.2])
                cube([2, 46, 0.3], center=true);
    }
}

module bno086_shadow() {
    color("red", 0.7) {
        // PCB
        cube([bno_pcb_w, bno_pcb_l, bno_pcb_h], center=true);
        // BNO086 sensor (small square)
        translate([0, -3, bno_pcb_h/2 + 1])
            cube([5, 5, 2], center=true);
        // Qwiic connectors
        translate([0, -bno_pcb_l/2 + 4, -bno_pcb_h/2 - 1])
            cube([8, 6, 2], center=true);
        translate([0, bno_pcb_l/2 - 4, -bno_pcb_h/2 - 1])
            cube([8, 6, 2], center=true);
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

module pico_screw_positions() {
    for (dx = [-pico_hole_spacing_x/2, pico_hole_spacing_x/2])
        for (dy = [-pico_hole_spacing_y/2, pico_hole_spacing_y/2])
            translate([pico_x + dx, pico_y + dy, 0])
                children();
}

module bno_screw_positions() {
    // BNO has 2 holes on one edge (using left edge)
    for (dy = [-bno_hole_spacing_y/2, bno_hole_spacing_y/2])
        translate([bno_x - bno_pcb_w/2 + bno_hole_edge_offset, bno_y + dy, 0])
            children();
}

// ============================================================
// ENCLOSURE BODY
// ============================================================

module enclosure_body() {
    pico_standoff_h = 3;  // Height of Pico standoffs
    bno_standoff_h = 3;   // Height of BNO standoffs

    difference() {
        union() {
            // Main box with rounded corners
            rounded_box(enclosure_w, enclosure_l, enclosure_h, corner_radius);
        }

        // Inner cavity
        translate([0, 0, floor_thickness])
            rounded_box(
                enclosure_w - 2*wall_thickness,
                enclosure_l - 2*wall_thickness,
                enclosure_h,
                max(1, corner_radius - wall_thickness)
            );

        // USB port cutout (rounded oval on front wall for Pico)
        // Pico USB is centered on board width, at -Y end
        // Position hole at Pico's USB height (standoff + PCB + USB center)
        usb_z = floor_thickness + pico_standoff_h + pico_pcb_h + pico_usb_h/2;
        translate([pico_x, -enclosure_l/2 - 0.1, usb_z])
            rotate([-90, 0, 0])
                hull() {
                    // Rounded oval: two circles connected
                    translate([-(usb_plug_w - usb_plug_h)/2, 0, 0])
                        cylinder(d=usb_plug_h, h=wall_thickness + 0.4);
                    translate([(usb_plug_w - usb_plug_h)/2, 0, 0])
                        cylinder(d=usb_plug_h, h=wall_thickness + 0.4);
                }

        // Lid screw holes (tap holes in body)
        lid_screw_positions()
            translate([0, 0, enclosure_h - lid_overlap])
                cylinder(d=m3_tap_dia, h=lid_overlap + 1);
    }

    // Pico mounting posts
    color("gray")
        pico_screw_positions()
            translate([0, 0, floor_thickness])
                difference() {
                    cylinder(d=m2_screw_post_dia, h=pico_standoff_h);
                    cylinder(d=m2_tap_dia, h=pico_standoff_h + 1);
                }

    // BNO086 mounting posts
    color("gray")
        bno_screw_positions()
            translate([0, 0, floor_thickness])
                difference() {
                    cylinder(d=m2_screw_post_dia, h=bno_standoff_h);
                    cylinder(d=m2_tap_dia, h=bno_standoff_h + 1);
                }

    // Corner gussets with integrated screw bosses
    boss_h = enclosure_h - floor_thickness - 0.5;
    gusset_len = 8;
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
                translate([0, 0, floor_thickness])
                    hull() {
                        // Screw boss
                        translate([screw_x, screw_y, 0])
                            cylinder(d=screw_boss_dia, h=boss_h);
                        // Corner connection
                        translate([corner_x, corner_y, 0])
                            cylinder(d=3, h=boss_h);
                        // Gusset arms along walls
                        translate([corner_x - sx*gusset_len, corner_y, 0])
                            cylinder(d=3, h=boss_h);
                        translate([corner_x, corner_y - sy*gusset_len, 0])
                            cylinder(d=3, h=boss_h);
                    }

                // Screw tap hole
                translate([screw_x, screw_y, floor_thickness + boss_h - lid_overlap - 0.5])
                    cylinder(d=m3_tap_dia, h=lid_overlap + 2);
            }
        }
}

// ============================================================
// ENCLOSURE LID
// ============================================================

module enclosure_lid() {
    rim_width = 3.0;      // Rim around outer edge
    m3_head_h = 2.5;      // M3 button/pan head height

    difference() {
        union() {
            // Main lid plate with rounded corners
            rounded_box(enclosure_w, enclosure_l, lid_thickness, corner_radius);

            // Outer rim going up (protective bezel) - with cutouts for screw bosses
            difference() {
                rounded_box(enclosure_w, enclosure_l, lid_thickness + rim_width, corner_radius);
                translate([0, 0, -0.1])
                    rounded_box(enclosure_w - 2*rim_width, enclosure_l - 2*rim_width,
                                lid_thickness + rim_width + 0.2, max(1, corner_radius - rim_width));
                // Cut away rim at screw positions
                lid_screw_positions()
                    cylinder(d=m3_head_dia + 4, h=lid_thickness + rim_width + 0.2);
            }

            // Screw bosses at corners (to provide material for counterbore)
            lid_screw_positions()
                cylinder(d=m3_head_dia + 3, h=lid_thickness + m3_head_h);

            // Embossed text on top surface of lid (all 4 edges)
            emboss_text = "Mirror Articulate Intelligence";
            text_size = 3.5;
            text_depth = 0.5;
            text_inset = 5;  // distance from outer edge to text center

            // Front edge (-Y) - text reads from front
            translate([0, -enclosure_l/2 + text_inset, lid_thickness])
                linear_extrude(text_depth)
                    text(emboss_text, size=text_size, halign="center", valign="center", font="Liberation Sans:style=Bold");

            // Back edge (+Y) - text reads from back
            translate([0, enclosure_l/2 - text_inset, lid_thickness])
                rotate([0, 0, 180])
                    linear_extrude(text_depth)
                        text(emboss_text, size=text_size, halign="center", valign="center", font="Liberation Sans:style=Bold");

            // Left edge (-X) - text reads from left
            translate([-enclosure_w/2 + text_inset, 0, lid_thickness])
                rotate([0, 0, 90])
                    linear_extrude(text_depth)
                        text(emboss_text, size=text_size, halign="center", valign="center", font="Liberation Sans:style=Bold");

            // Right edge (+X) - text reads from right
            translate([enclosure_w/2 - text_inset, 0, lid_thickness])
                rotate([0, 0, -90])
                    linear_extrude(text_depth)
                        text(emboss_text, size=text_size, halign="center", valign="center", font="Liberation Sans:style=Bold");
        }

        // LED holes - 8x8 grid (centered in XY, cut through full lid thickness)
        led_hole_size = 6.0;  // slightly larger than 5050 LED for light spread

        for (i = [0:7])
            for (j = [0:7]) {
                led_x = -neopixel_pcb_w/2 + neopixel_led_offset + i * neopixel_led_pitch;
                led_y = -neopixel_pcb_l/2 + neopixel_led_offset + j * neopixel_led_pitch;
                translate([led_x - led_hole_size/2, led_y - led_hole_size/2, -0.1])
                    cube([led_hole_size, led_hole_size, lid_thickness + 0.3]);
            }

        // Lid screw holes with counterbore for M3 head
        lid_screw_positions() {
            // Through hole
            translate([0, 0, -0.1])
                cylinder(d=m3_hole_dia, h=lid_thickness + m3_head_h + 0.2);
            // Counterbore for screw head
            translate([0, 0, lid_thickness])
                cylinder(d=m3_head_dia + 0.5, h=m3_head_h + 0.1);
        }
    }
}

// ============================================================
// ASSEMBLY VIEW
// ============================================================

module assembly() {
    pico_standoff_h = 3;
    bno_standoff_h = 3;

    if (show_body) {
        color("lightblue", 0.8)
            enclosure_body();
    }

    // Calculate explode offset
    explode_z = explode_lid ? explode_distance : 0;

    if (show_lid) {
        color("lightblue", 0.8)
            translate([0, 0, enclosure_h + explode_z])
                enclosure_lid();
    }

    if (show_components) {
        // NeoPixel matrix mounted against underside of lid (moves with lid)
        translate([0, 0, neopixel_z + neopixel_pcb_h/2 + explode_z])
            neopixel_shadow();

        // Pico centered at front
        translate([pico_x, pico_y, floor_thickness + pico_standoff_h + pico_pcb_h/2])
            pico_shadow();

        // BNO086 centered at back
        translate([bno_x, bno_y, floor_thickness + bno_standoff_h + bno_pcb_h/2])
            bno086_shadow();
    }
}

// ============================================================
// PRINT MODULES (oriented for 3D printing)
// ============================================================

module body_for_print() {
    translate([0, 0, enclosure_h])
        rotate([180, 0, 0])
            enclosure_body();
}

module lid_for_print() {
    // Flip so lip faces up, flat surface on build plate
    rim_width = 3.0;
    translate([0, 0, lid_thickness + rim_width])
        rotate([180, 0, 0])
            enclosure_lid();
}

// ============================================================
// RENDER
// ============================================================

if (part == "assembly") {
    assembly();
} else if (part == "body") {
    body_for_print();
} else if (part == "lid") {
    lid_for_print();
}

// Dimensions output
echo(str("Enclosure: ", enclosure_w, " x ", enclosure_l, " x ", enclosure_h, " mm"));
echo(str("Interior: ", interior_w, " x ", interior_l, " x ", interior_h, " mm"));
echo(str("Lid thickness: ", lid_thickness, " mm with 3mm rim"));
