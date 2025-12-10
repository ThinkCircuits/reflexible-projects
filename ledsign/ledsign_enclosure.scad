// LED Sign Enclosure
// 16x16 WS2812 LED array on flex PCB
// Two pieces: Face (with LED holes) + Back (with integrated stand bump-out)

$fn = 64;

/* [Part Selection] */
part = "assembly"; // [assembly:Assembly View, face:Face Only, back:Back Only]

/* [Assembly View Options] */
show_face = true;
show_back = true;
show_components = true;
explode_view = false;
explode_distance = 30;

/* [LED Array - 16x16 WS2812] */
led_count_x = 16;
led_count_y = 16;
led_pitch = 10;             // 10mm spacing
led_size = 5.0;             // 5050 SMD LED
flex_pcb_thickness = 0.3;   // Very thin flex PCB

// Calculated LED array size
led_array_w = (led_count_x - 1) * led_pitch + led_size;  // 155mm
led_array_h = (led_count_y - 1) * led_pitch + led_size;  // 155mm
led_margin = 12;            // Margin around LED array (enough for screw bosses)

/* [Raspberry Pi Pico W] */
pico_pcb_w = 21;
pico_pcb_l = 51;
pico_pcb_h = 1.0;
pico_total_h = 3.5;
pico_usb_w = 8;
pico_usb_h = 3;
pico_hole_from_end = 4.8;
pico_hole_from_side = 2.0;
pico_hole_spacing_x = pico_pcb_w - 2*pico_hole_from_side;
pico_hole_spacing_y = pico_pcb_l - 2*pico_hole_from_end;

/* [Barrel Jack - LUORNG DC-099 5.5x2.1mm] */
// https://www.amazon.com/LUORNG-Threaded-Connector-Pre-soldered-Waterproof/dp/B09H5L3KN5
barrel_jack_hole_dia = 12;      // 12mm mounting hole required
barrel_jack_body_dia = 14;      // Outer body diameter
barrel_jack_depth = 15;         // Depth behind panel

/* [Enclosure Parameters] */
wall_thickness = 2.0;
enclosure_depth = 12;       // Total depth of assembled enclosure
corner_radius = 3;

/* [Face Parameters] */
face_thickness = 1.2;       // Very thin face for signage
led_hole_size = 7.0;        // Square hole for each LED
face_rim_height = 4;        // Rim around edge that overlaps back

/* [Logo] */
logo_file = "logo_cropped.svg";
logo_width = 42.5;          // SVG content width in mm
logo_height = 41.3;         // SVG content height in mm
logo_scale = 0.25;          // Scale factor for logo
logo_depth = 1.0;           // Emboss depth (raised above surface)

/* [Stand Parameters] */
stand_angle = 15;           // Tilt angle
stand_bump_depth = 80;      // How far stand extends from back (needs depth for stability)
stand_height = 40;          // Height of stand bump

/* [Screw Parameters] */
m3_hole_dia = 3.4;
m3_tap_dia = 2.5;
m3_head_dia = 6;
m2_tap_dia = 1.8;
screw_boss_dia = 7;

// ============================================================
// CALCULATED DIMENSIONS
// ============================================================

// Interior sized for LED array
interior_w = led_array_w + led_margin * 2;
interior_h = led_array_h + led_margin * 2;

// Outer dimensions
outer_w = interior_w + wall_thickness * 2;
outer_h = interior_h + wall_thickness * 2;

// Back piece depth (without stand)
back_depth = enclosure_depth - face_thickness;

// ============================================================
// SHADOW MODELS
// ============================================================

module led_array_shadow() {
    // Flex PCB - dark purple
    color("indigo", 0.9)
        cube([led_array_w + 10, led_array_h + 10, flex_pcb_thickness], center=true);
    // LEDs - rainbow pattern
    for (i = [0:led_count_x-1])
        for (j = [0:led_count_y-1]) {
            led_x = -led_array_w/2 + led_size/2 + i * led_pitch;
            led_y = -led_array_h/2 + led_size/2 + j * led_pitch;
            // Rainbow hue based on position
            hue = ((i + j) % 16) / 16;
            translate([led_x, led_y, flex_pcb_thickness/2 + 0.5])
                color([cos(hue*360)*0.5+0.5, cos((hue+0.33)*360)*0.5+0.5, cos((hue+0.66)*360)*0.5+0.5], 0.95)
                    cube([led_size, led_size, 1], center=true);
        }
}

module pico_shadow() {
    // PCB - bright green
    color("limegreen", 0.85)
        cube([pico_pcb_w, pico_pcb_l, pico_pcb_h], center=true);
    // USB connector - chrome
    translate([0, -pico_pcb_l/2, pico_pcb_h/2 + pico_usb_h/2])
        color("silver", 0.95)
            cube([pico_usb_w, 6, pico_usb_h], center=true);
    // RP2040 chip - black with gold text
    translate([0, -5, pico_pcb_h/2 + 1])
        color("black", 0.9)
            cube([10, 12, 2], center=true);
    // Wireless module - shiny metal
    translate([0, 10, pico_pcb_h/2 + 1])
        color("steelblue", 0.9)
            cube([10, 10, 2], center=true);
}

module barrel_jack_shadow() {
    // LUORNG DC-099 panel mount barrel jack
    // Threaded body - brass colored
    color("goldenrod", 0.9)
        cylinder(d=barrel_jack_hole_dia - 0.5, h=barrel_jack_depth, center=true);
    // Hex nut flange (outside panel) - chrome
    translate([0, 0, barrel_jack_depth/2])
        color("silver", 0.95)
            cylinder(d=16, h=3, $fn=6, center=true);
    // Inner barrel - copper
    translate([0, 0, -barrel_jack_depth/2])
        color("orangered", 0.9)
            cylinder(d=8, h=10, center=true);
    // Center pin
    translate([0, 0, -barrel_jack_depth/2 - 5])
        color("gold", 1.0)
            cylinder(d=2.1, h=12, center=true);
}

// ============================================================
// COMMON MODULES
// ============================================================

module rounded_rect(w, h, d, r) {
    hull() {
        for (x = [-w/2 + r, w/2 - r])
            for (y = [-h/2 + r, h/2 - r])
                translate([x, y, 0])
                    cylinder(r=r, h=d);
    }
}

module screw_positions() {
    inset = screw_boss_dia/2 + 3;
    for (sx = [-1, 1])
        for (sy = [-1, 1])
            translate([sx * (outer_w/2 - inset), sy * (outer_h/2 - inset), 0])
                children();
}

module pico_screw_positions() {
    for (dx = [-pico_hole_spacing_x/2, pico_hole_spacing_x/2])
        for (dy = [-pico_hole_spacing_y/2, pico_hole_spacing_y/2])
            translate([dx, dy, 0])
                children();
}

// ============================================================
// LOGO
// ============================================================

module logo_2d() {
    // Import cropped SVG (viewBox 0 0 42.5 41.3) and center it
    translate([-logo_width/2, -logo_height/2])
        import(logo_file);
}

module logo_embossed() {
    // Embossed logo for face - raised above surface
    // Use offset(0) to fix winding direction issues with SVG
    linear_extrude(height=logo_depth)
        offset(delta=0)
            scale([logo_scale, logo_scale])
                logo_2d();
}

// ============================================================
// FACE (front piece with LED holes)
// ============================================================

module sign_face() {
    union() {
        difference() {
            union() {
                // Main face plate (at Z=0, this is the front surface)
                rounded_rect(outer_w, outer_h, face_thickness, corner_radius);

                // Rim that extends into back piece (in +Z direction)
                translate([0, 0, face_thickness])
                    difference() {
                        rounded_rect(outer_w, outer_h, face_rim_height, corner_radius);
                        translate([0, 0, -0.1])
                            rounded_rect(outer_w - wall_thickness*2, outer_h - wall_thickness*2,
                                        face_rim_height + 0.2, max(1, corner_radius - wall_thickness));
                    }
            }

            // LED holes - 16x16 grid (cut through face plate)
            for (i = [0:led_count_x-1])
                for (j = [0:led_count_y-1]) {
                    led_x = -led_array_w/2 + led_size/2 + i * led_pitch;
                    led_y = -led_array_h/2 + led_size/2 + j * led_pitch;
                    translate([led_x - led_hole_size/2, led_y - led_hole_size/2, -0.1])
                        cube([led_hole_size, led_hole_size, face_thickness + 0.2]);
                }

            // Screw holes (straight through for pan-head screws)
            screw_positions()
                translate([0, 0, -0.1])
                    cylinder(d=m3_hole_dia, h=face_thickness + face_rim_height + 0.2);
        }

        // Embossed logo in top margin area (between LED array and outer edge)
        // Position: X centered, Y in margin closer to bottom edge, Z on top of face
        translate([0, outer_h/2 - led_margin/2 - wall_thickness + 1.5, -logo_depth])
            linear_extrude(height=logo_depth, convexity=10)
                scale([logo_scale, logo_scale])
                    translate([-logo_width/2, -logo_height/2])
                        import(logo_file, convexity=10);

        // Embossed text at bottom margin (same approach as logo)
        translate([0, -outer_h/2 + led_margin/2 + wall_thickness - 2, -0.6])
            linear_extrude(height=0.6)
                mirror([1, 0, 0])
                    text("Mirror Articulate Intelligence",
                         size=7,
                         font="Liberation Sans:style=Bold",
                         halign="center",
                         valign="center");
    }
}

// ============================================================
// BACK (with integrated stand bump-out)
// ============================================================

module sign_back() {
    difference() {
        union() {
            // Main back plate (solid - no interior cavity)
            rounded_rect(outer_w, outer_h, back_depth, corner_radius);

            // Stand bump-out at bottom - extends from outer back surface
            // Creates angled support for stability
            translate([0, -outer_h/2, back_depth])
                hull() {
                    // Connection edge at back surface
                    translate([0, 1, 0])
                        cube([outer_w - 10, 2, 2], center=true);
                    // Back edge (rests on surface when tilted)
                    translate([0, stand_bump_depth, 0])
                        cube([outer_w - 10, 2, 2], center=true);
                    // Top of bump (angled)
                    translate([0, stand_bump_depth * tan(stand_angle), stand_height])
                        cube([outer_w - 10, 2, 2], center=true);
                    // Connection at top
                    translate([0, 1, stand_height])
                        cube([outer_w - 10, 2, 2], center=true);
                }
        }

        // Barrel jack hole (side of stand bump - near bottom corner)
        // Bump is (outer_w - 10) wide, so edge is at outer_w/2 - 5
        translate([outer_w/2 - 5, -outer_h/2 + 15, back_depth + barrel_jack_hole_dia/2 + 2])
            rotate([0, 90, 0])
                cylinder(d=barrel_jack_hole_dia, h=20, center=true);

        // Screw holes (tap holes) - from front side
        screw_positions()
            translate([0, 0, -0.1])
                cylinder(d=m3_tap_dia, h=8);
    }

}

// ============================================================
// ASSEMBLY
// ============================================================

module assembly() {
    explode_z = explode_view ? explode_distance : 0;

    // Face piece at front (Z=0 is front surface, viewer side)
    if (show_face) {
        color("lightgray", 0.8)
            rotate([stand_angle, 0, 0])
                translate([0, 0, -explode_z])
                    sign_face();
    }

    // Back piece behind face (starts where face rim ends)
    if (show_back) {
        color("dimgray", 0.9)
            rotate([stand_angle, 0, 0])
                translate([0, 0, face_thickness + face_rim_height])
                    sign_back();
    }

    // Component shadows
    if (show_components) {
        // LED array (just behind face, LEDs pointing toward holes)
        rotate([stand_angle, 0, 0])
            translate([0, 0, face_thickness + 2])
                led_array_shadow();

        // Barrel jack in stand bump (near bottom corner)
        rotate([stand_angle, 0, 0])
            translate([outer_w/2 - 5 - barrel_jack_depth/2,
                      -outer_h/2 + 15,
                      face_thickness + face_rim_height + back_depth + barrel_jack_hole_dia/2 + 2])
                rotate([0, 90, 0])
                    barrel_jack_shadow();
    }
}

// ============================================================
// PRINT MODULES
// ============================================================

module face_for_print() {
    // Print with rim facing up (front surface on build plate)
    sign_face();
}

module back_for_print() {
    // Print with front surface on build plate, bump facing up
    sign_back();
}

// ============================================================
// RENDER
// ============================================================

if (part == "assembly") {
    assembly();
} else if (part == "face") {
    face_for_print();
} else if (part == "back") {
    back_for_print();
}

// Dimensions output
echo(str("Outer: ", outer_w, " x ", outer_h, " mm"));
echo(str("LED Array: ", led_array_w, " x ", led_array_h, " mm (", led_count_x, "x", led_count_y, " LEDs)"));
echo(str("Enclosure depth: ", enclosure_depth, " mm"));
echo(str("Face thickness: ", face_thickness, " mm"));
echo(str("Stand bump depth: ", stand_bump_depth, " mm"));
echo(str("Tilt angle: ", stand_angle, " degrees"));
