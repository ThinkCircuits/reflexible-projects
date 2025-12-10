# Reflexible Projects

Hardware designs for Reflexible automation projects by ThinkCircuits.

## Projects

### Plant Waterer

An automated plant watering system using SparkFun Qwiic components.

**Components:**
- Raspberry Pi Pico W - Controller
- SparkFun Qwiic Twist - RGB rotary encoder for user input
- SparkFun Qwiic OLED 128x32 - Display
- SparkFun Qwiic Relay - Water pump control
- Filtering capacitor

**Files:**
- `plantwaterer/housing.scad` - OpenSCAD enclosure design

**Enclosure Features:**
- Three printable parts: enclosure, lid, shelf
- Front-mounted encoder and OLED display
- Internal shelf for Pico W and relay
- Wire routing notches at lid seam
- Engraved branding on front face
- M3 self-tapping screw assembly

**Building STLs:**

```bash
openscad -o enclosure.stl -D 'part="enclosure"' housing.scad
openscad -o lid.stl -D 'part="lid"' housing.scad
openscad -o shelf.stl -D 'part="shelf"' housing.scad
```

## License

MIT License - See LICENSE file for details.
