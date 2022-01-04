layer_height = 0.2;
extrusion_width = 0.45;
extrusion_overlap = layer_height * (1 - PI/4);
extrusion_spacing = extrusion_width - extrusion_overlap;

// convert between path counts and spacing, qspace to quantize
function xspace(n=1) = n*extrusion_spacing;
function nspace(x=xspace()) = x/extrusion_spacing;
function qspace(x=xspace()) = xspace(round(nspace(x)));
function cspace(x=xspace()) = xspace(ceil(nspace(x)));
function fspace(x=xspace()) = xspace(floor(nspace(x)));

// convert between path counts and width, qwall to quantize
function xwall(n=1) = xspace(n) + (0<n ? extrusion_overlap : 0);
function nwall(x=xwall()) =  // first path gets full extrusion width
    x < 0 ? nspace(x) :
    x < extrusion_overlap ? 0 :
    nspace(x - extrusion_overlap);
function qwall(x=xwall()) = xwall(round(nwall(x)));
function cwall(x=xwall()) = xwall(ceil(nwall(x)));
function fwall(x=xwall()) = xwall(floor(nwall(x)));

// quantize thin walls only (less than n paths wide, default for 2 perimeters)
function qthin(x=xwall(), n=4.5) = x < xwall(n) ? qwall(x) : x;
function cthin(x=xwall(), n=4.5) = x < xwall(n) ? cwall(x) : x;
function fthin(x=xwall(), n=4.5) = x < xwall(n) ? fwall(x) : x;

// convert between layer counts and height, qlayer to quantize
function zlayer(n=1) = n*layer_height;
function nlayer(z=zlayer()) = z/layer_height;
// quantize heights
function qlayer(z=zlayer()) = zlayer(round(nlayer(z)));
function clayer(z=zlayer()) = zlayer(ceil(nlayer(z)));
function flayer(z=zlayer()) = zlayer(floor(nlayer(z)));

// unit vector for 0=x, 1=y, 2=z
function unit_axis(n) = [for (i=[0:1:2]) i==n ? 1 : 0];

// basic constants
tolerance = 0.001;
wall0 = xwall(4);
floor0 = qlayer(wall0);
gap0 = 0.1;

module raise(z=floor0) {
    translate([0, 0, z]) children();
}

$fa = 15;
$fs = min(layer_height/2, xspace(1)/2);

inch = 25.4;

// box metrics
interior = [231, 231, 67.5];  // box interior
module interior(a=0, center=false) {
    origin = [0, 0, center ? 0 : interior[2]/2];
    translate(origin) rotate(a) cube(interior, center=true);
}

// component metrics
Nplayers = 4;  // number of players, mats, design goal sets
Ntiles = 6;  // number of tiles per set
Vmat = [228, 184, 4.9];  // dual-layer mat dimensions (approx. 9in x 7.25in)
Hmats = Nplayers * Vmat[2];  // height of stacked mats
Hboard = 2.6;  // tile & token thickness
Hmanual = 0.9;  // approximate
Hroom = interior[2] - Hmats - Hmanual;
Rhex = 3/4 * 25.4;  // hex major radius (center to vertex)
Rbighex = 41;  // button key & master quilter hex

// hex container metrics
Hcap = clayer(4);  // total height of lid + plug
Hlid = floor0;  // height of cap lid
Hplug = Hcap - Hlid;  // depth of lid below cap
Rspace = 1;  // space between contents and box (sides + lid)
Rlid = Rspace+wall0;  // offset radius from contents to outer lid/box edge
Rplug = Rspace-gap0;  // offset radius from contents to lid plug
Alid = 30;  // angle of lid chamfer
Hseam = wall0/2 * tan(Alid) - zlayer(1/2);  // space between lid cap and box
Hchamfer = (Rlid-Rplug) * tan(Alid);

// block container metrics
Vblock = [92.5, (interior[1]-1) / 4, floor(Hroom / 2)];
Hrecess = clayer(Hboard+gap0);  // depth of tile recess
Hshelf = Vblock[2] - Hrecess;

Ghex = [[1, 0], [0.5, 1], [-0.5, 1], [-1, 0], [-0.5, -1], [0.5, -1]];
function hex_grid(x, y, r=Rhex) = [r*x, sin(60)*r*y];
function hex_points(grid=Ghex, r=Rhex) = [for (i=grid) hex_grid(i[0],i[1],r)];
function hex_min(grid=Ghex, r=Rhex) =
    hex_grid(min([for (i=grid) i[0]]), min([for (i=grid) i[1]]), r);

module hex_poly(grid=Ghex, r=Rhex, center=false) {
    origin = center ? [0, 0] : -hex_min(grid, r);
    translate(origin) polygon(hex_points(grid, r));
}
module hex_tile(n=1, grid=Ghex, r=Rhex, center=false) {
    linear_extrude(Hboard*n, center=center)
        hex_poly(grid=grid, r=r, center=center);
}
module hex_lid(grid=Ghex, r=Rhex, center=false) {
    xy_min = hex_min(grid, r);
    origin = center ? [0, 0, 0] : [Rlid - xy_min[0], Rlid - xy_min[1], 0];
    translate(origin) {
        minkowski() {
            linear_extrude(Hlid, center=false)
                hex_poly(grid=grid, r=r, center=true);
            mirror([0, 0, 1]) {
                cylinder(h=Hplug, r=Rplug);
                cylinder(h=Hchamfer, r1=Rlid, r2=Rplug);
            }
        }
    }
}

function hex_box_height(n=1, plug=false) =
    clayer(floor0 + n*Hboard + Rspace + Hplug) + (plug ? Hplug : 0);
function stack_height(k=1, n=Ntiles, plug=true, lid=true) =
    k*hex_box_height(n) +
    (k-1)*clayer(Hseam) +
    (plug ? Hplug : 0) +
    (lid ? clayer(Hseam) + Hlid : 0);

module hex_box(n=1, plug=false, grid=Ghex, r=Rhex, center=false) {
    h = hex_box_height(n=n, plug=false);
    origin = center ? [0, 0] : -hex_min(grid, r) + [1, 1] * Rlid;
    translate(origin) {
        difference() {
            // exterior
            union() {
                linear_extrude(h, center=false)
                    offset(r=Rlid) hex_poly(grid=grid, r=r, center=true);
                if (plug) hex_lid(grid=grid, r=r, center=true);
            }
            // interior
            raise() linear_extrude(h, center=false)
                offset(r=Rlid-wall0) hex_poly(grid=grid, r=r, center=true);
            // lid chamfer
            raise(h+Hseam) hex_lid(grid=grid, center=true);
        }
        // ghost tiles
        %raise(floor0 + Hboard * n/2)
            hex_tile(n=n, grid=grid, r=r, center=true);
    }
}
module raise_lid(k=1, n=Ntiles, plug=true) {
    h = k * (hex_box_height(n) + clayer(Hseam)) + (plug ? Hplug : 0);
    raise(stack_height(k=k, n=n, plug=plug, lid=true) - Hlid) children();
}

module tile_hex_box(n=Ntiles, plug=true, center=false) {
    hex_box(n=n, plug=plug, grid=Ghex, center=center);
}
module tile_hex_lid(center=false) {
    hex_lid(grid=Ghex, center=center);
}

xstack = [stack_height(Nplayers+1), 2*(sin(60)*Rhex+Rlid), 2*(Rhex+Rlid)];

module hex_box_tray(center=false) {
    margin = 1;
    wall = margin + wall0;
    function align(x) = ceil(x+2*wall0+1) - 2*wall;
    tray = [align(xstack[0]), align(xstack[1])];
    rise = floor(xstack[2] * 3/4);
    cut = (tray[0]+2*wall) / 4;
    difference() {
        linear_extrude(rise) offset(r=margin+wall0)
            square(tray, center=center);
        raise() linear_extrude(rise) offset(r=margin)
            square(tray, center=center);
        raise(floor0+xstack[2]/2) {
            raise(rise/2) cube([2*xstack[0], cut, rise], center=true);
            rotate([0, 90, 0]) cylinder(d=cut, h=2*xstack[0], center=true);
        }
        for (x=[-1.25, 0, 1.25]) translate([x*cut, 0])
            cylinder(d=cut, h=3*floor0, center=true);
    }
}

ctile = [90.1, 56.2];  // cat tile footprint
ctile_radius = 1.6;  // corner radius
ctile_banner = 9;  // width of nameplate banner
ctile_pattern = [18.5, 47];  // distance from top center to pattern notch

module rounded_square(r, size, center=true) {
    offset(r=r) offset(r=-r) square(size, center);
}

module cat_tile_outline(delta=0, tray=false, center=false) {
    origin = center ? [0, 0] : ctile/2;
    translate(origin) offset(delta=delta) {
        if (tray) {  // tray cutout shape
            xstrip = (ctile[0] - ctile_banner) / 2;
            ystrip = (ctile[1] - ctile_banner) / 2;
            translate([0, ystrip])
                rounded_square(ctile_radius, [ctile[0], ctile_banner]);
            for (i=[-1,+1]) translate([i*xstrip, -ctile_banner/4])
                square([ctile_banner, ctile[1]-ctile_banner/2], center=true);
        } else {
            xhex = ctile_pattern[0];
            yhex = Rhex - ctile[1]/2 + ctile_pattern[1];
            difference() {
                rounded_square(ctile_radius, ctile);
                for (i=[-1,+1]) translate([i*xhex, -yhex]) rotate(90)
                    hex_poly(center=true);
            }
        }
    }
}
module cat_tile(tray=false, center=false) {
    linear_extrude(Hboard) cat_tile_outline(tray=tray, center=center);
}
module cat_tile_box(color=undef, center=false) {
    lip = xwall(2);
    gap = (Vblock[1] - lip - ctile[1]) / 2;
    border = lip + gap;
    foot = [ctile[0] + 2*border, Vblock[1]];
    well = [(foot[0] - 3*wall0) / 2, (foot[1] - 2*wall0)];
    rext = border + ctile_radius;  // exterior corner radius
    rint = rext - wall0 + 3.6;  // interior corner radius
    origin = center ? [0, 0] : foot/2;
    translate(origin) {
        *translate([0, -lip/2, Hshelf]) cat_tile(tray=true, center=true);
        %translate([0, -lip/2, Hshelf]) cat_tile(center=true);
        color(color) difference() {
            // shell
            linear_extrude(Vblock[2]) rounded_square(rext, foot);
            // interior
            for (i=[-1,+1]) translate([i*(well[0]+wall0)/2, 0, floor0])
                linear_extrude(Vblock[2]) rounded_square(rint, well);
            // lip
            translate([0, -lip/2, Hshelf]) linear_extrude(2*Hrecess)
                cat_tile_outline(gap, tray=true, center=true);
            // lip bevel
            for (i=[-1,+1])
                translate([i*(foot[0]-wall0)/2, -foot[1]/2, Hshelf])
                rotate([0, -90, 0]) linear_extrude(2*wall0, center=true)
                polygon([[0, 0], [0, wall0],
                        [2*Hrecess, wall0+2*Hrecess], [2*Hrecess, 0]]);
            // tile notches
            translate([0, -lip/2-gap, Hshelf]) linear_extrude(2*Hrecess)
                cat_tile_outline(0.01, center=true);
        }
    }
}

module button_tile(center=false) {
    origin = center ? [0, 0] : [sin(60)*Rbighex, Rbighex];
    translate(origin) rotate(90) hex_tile(r=Rbighex, center=true);
}

module button_box(color=undef, center=false) {
    foot = [Vblock[0], 2*Vblock[1]];
    rext = 2.7;  // match cat tile boxes
    rint = rext - wall0;
    well = [foot[0]-wall0, foot[1]-wall0];

    // token well dimensions
    length = (well[0] - wall0) / 2;
    width = (well[1] - length - 2*wall0) / 2;
    mid = (well[0] - 2*width - 2*wall0);
    echo(length, width, mid);

    vend = [length, width];
    vside = [width, length];
    vmid = [mid, length];
    echo(vend, vside, vmid);

    origin = center ? [0, 0] : foot/2;
    translate(origin) {
        %raise(Hshelf+Hboard/2) button_tile(center=true);
        color(color) difference() {
            // shell
            linear_extrude(Vblock[2]) rounded_square(rext, foot);
            // tile shelf
            raise(Hshelf) linear_extrude(Vblock[2])
                rounded_square(rint, well);
            raise() {
                // center well
                linear_extrude(Vblock[2]) rounded_square(rint, vmid);
                // edge wells
                for (i=[-1,+1]) translate([i*(well[0]-vside[0]), 0]/2)
                    linear_extrude(Vblock[2]) rounded_square(rint, vside);
                // corner wells
                for (j=[-1,+1]) for (i=[-1,+1])
                    translate([i*(well[0]-vend[0]), j*(well[1]-vend[1])]/2)
                    linear_extrude(Vblock[2]) rounded_square(rint, vend);
            }
        }
    }
}

// complete organizer
union() {
    %color("gray", 0.1) interior();
    translate([0, (Vmat[1]-interior[1])/2, 0]) {
        raise(0.5*Vmat[2]) color("#ffffc0") cube(Vmat, center=true);
        raise(1.5*Vmat[2]) color("#c0ffc0") cube(Vmat, center=true);
        raise(2.5*Vmat[2]) color("#d0e0ff") cube(Vmat, center=true);
        raise(3.5*Vmat[2]) color("#e0c0ff") cube(Vmat, center=true);
    }

    translate([interior[0]/4, Vmat[1]/2, 0]) {
        color("purple") hex_box_tray(center=true);
        // stack of hex boxes
        raise(floor0+xstack[2]/2) rotate([0, 90, 0]) raise(-xstack[0]/2) {
            colors = ["darkviolet", "blue", "green", "yellow", "#202020"];
            for (i=[0:Nplayers]) {
                raise_lid(i) color(colors[i]) tile_hex_box(center=true);
            }
            color("#202020") raise_lid(Nplayers+1) tile_hex_lid(center=true);
        }
    }
    rotate(90) translate([(Vblock[0]-interior[0])/2, 0, Hmats]) {
        translate([0, -Vblock[1]*3/2]) {
            cat_tile_box(color="#202020", center=true);
            raise(Vblock[2])
                cat_tile_box(color="#202020", center=true);
        }
        translate([0, -Vblock[1]*1/2])
            cat_tile_box(color="ivory", center=true);
        translate([0, +Vblock[1]*1/2])
            cat_tile_box(color="ivory", center=true);
        translate([0, +Vblock[1]*3/2]) {
            cat_tile_box(color="orange", center=true);
            raise(Vblock[2])
                cat_tile_box(color="orange", center=true);
        }
        raise(Vblock[2]) button_box("purple", center=true);
    }
}

// single objects
*raise_lid(0, 0) tile_hex_lid(center=true);
*raise_lid(0, 0) tile_hex_box(center=true);
*hex_box_tray(center=true);
*cat_tile_box(center=true);
*button_box(center=true);
