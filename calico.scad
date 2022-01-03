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
mat = [228, 184, 4.9];  // dual-layer mat dimensions (approx. 9in x 7.25in)
Hmats = Nplayers * mat[2];  // height of stacked mats
Hboard = 2.6;  // tile & token thickness
Hmanual = 0.9;  // approximate
Hroom = interior[2] - Hmats - Hmanual;
Hlayer = floor(Hroom / 2);
Rhex = 3/4 * 25.4;  // hex major radius (center to vertex)


// container metrics
Hcap = clayer(4);  // total height of lid + plug
Hlid = floor0;  // height of cap lid
Hplug = Hcap - Hlid;  // depth of lid below cap
Rspace = 1;  // space between contents and box (sides + lid)
Rlid = Rspace+wall0;  // offset radius from contents to outer lid/box edge
Rplug = Rspace-gap0;  // offset radius from contents to lid plug
Alid = 30;  // angle of lid chamfer
Hseam = wall0/2 * tan(Alid) - zlayer(1/2);  // space between lid cap and box
Hchamfer = (Rlid-Rplug) * tan(Alid);

Ghex = [[1, 0], [0.5, 1], [-0.5, 1], [-1, 0], [-0.5, -1], [0.5, -1]];
function hex_grid(x, y) = [Rhex*x, sin(60)*Rhex*y];
function hex_points(grid=Ghex) = [for (i=grid) hex_grid(i[0], i[1])];
function hex_min(grid=Ghex) =
    hex_grid(min([for (i=grid) i[0]]), min([for (i=grid) i[1]]));

module hex_poly(grid=Ghex, center=false) {
    origin = center ? [0, 0] : -hex_min(grid);
    translate(origin) polygon(hex_points(grid));
}
module hex_tile(n=1, grid=Ghex, center=false) {
    linear_extrude(Hboard*n, center=center) hex_poly(grid=grid, center=center);
}
module hex_lid(grid=Ghex, center=false) {
    xy_min = hex_min(grid);
    origin = center ? [0, 0, 0] : [Rlid - xy_min[0], Rlid - xy_min[1], 0];
    translate(origin) {
        minkowski() {
            linear_extrude(Hlid, center=false)
                hex_poly(grid=grid, center=true);
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

module hex_box(n=1, plug=false, grid=Ghex, center=false) {
    h = hex_box_height(n=n, plug=false);
    origin = center ? [0, 0] : -hex_min(grid) + [1, 1] * Rlid;
    translate(origin) {
        difference() {
            // exterior
            union() {
                linear_extrude(h, center=false)
                    offset(r=Rlid) hex_poly(grid=grid, center=true);
                if (plug) hex_lid(grid=grid, center=true);
            }
            // interior
            raise() linear_extrude(h, center=false)
                offset(r=Rlid-wall0) hex_poly(grid=grid, center=true);
            // lid chamfer
            raise(h+Hseam) hex_lid(grid=grid, center=true);
        }
        // ghost tiles
        %raise(floor0 + Hboard * n/2)
            hex_tile(n=n, grid=grid, center=true);
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

ctile = [90.1, 56.2];
ctile_radius = 1.6;
ctile_pattern = [18, 47];  // distance from top center to pattern notch

module cat_tile_outline(center=false) {
    origin = center ? [0, 0] : ctile/2;
    translate(origin) {
        inset = ctile - [2*ctile_radius, 2*ctile_radius];
        xhex = ctile_pattern[0];
        yhex = Rhex - ctile[1]/2 + ctile_pattern[1];
        difference() {
            offset(r=ctile_radius) square(inset, center=true);
            for (i=[-1,1])
                translate([i*xhex, -yhex]) rotate(90) hex_poly(center=true);
        }
    }
}
module cat_tile(center=false) {
    linear_extrude(Hboard) cat_tile_outline(center=center);
}
module cat_tile_box(center=false) {
    hrecess = clayer(Hboard+gap0);  // depth of cat tile recess
    hshelf = Hlayer-hrecess;
    wshelf = 3.2;
    width = floor((interior[1]-1) / 4);
    gap = (width - ctile[1]) / 2 + gap0;
    wall = gap + wall0;
    foot = [ctile[0] + 2*wall, width];
    *translate([0, 0, hshelf]) cat_tile(center=center);
    radius = wall + ctile_radius;
    inset = foot - [2*radius, 2*radius];
    echo(radius, inset, foot);
    origin = center ? [0, 0] : foot/2;
    module shelf(length, width=wshelf) {
        poly = [[0, 0], [-width, 0], [-width, -floor0], [0, -floor0-width]];
        rotate([90, 0, 0]) linear_extrude(length, center=true) polygon(poly);
    }
    translate(origin) {
        // box
        difference() {
            linear_extrude(hshelf) offset(r=radius)
                square(inset, center=true);
            raise() linear_extrude(hshelf) offset(r=radius-wall0)
                square(inset, center=true);
        }
        // divider
        raise(hshelf/2) cube([wall0, foot[1], hshelf], center=true);
        // shelf & rails
        intersection() {
            linear_extrude(Hlayer) offset(r=radius)
                square(inset, center=true);
            raise(hshelf) {
                // shelf
                translate([0, foot[1]/2]) rotate(90) shelf(foot[0]);
                translate([0, -foot[1]/2]) rotate(-90) shelf(foot[0]);
                translate([foot[0]/2, 0]) rotate(0) shelf(foot[0]);
                translate([-foot[0]/2, 0]) rotate(180) shelf(foot[0]);
                // rails
                translate([foot[0]-wall0, 0]/2)
                    cube([wall0, foot[1], 2*hrecess], center=true);
                translate([wall0-foot[0], 0]/2)
                    cube([wall0, foot[1], 2*hrecess], center=true);
            }
        }
        // pattern notches
        hrail = hrecess+floor0;
        difference() {
            raise(Hlayer - hrail/2) {
                translate([0, wshelf-foot[1]]/2)
                    cube([foot[0]-2*radius, wshelf, hrail], center=true);
            }
            linear_extrude(3*Hlayer, center=true)
                offset(r=gap) cat_tile_outline(center=true);
        }
    }
}

cat_tile_box(center=true);

// complete organizer
*union() {
    %interior();
    translate([0, mat[1]-interior[1], Hmats]/2)
        cube([mat[0], mat[1], Hmats], center=true);

    translate([interior[0]/4, mat[1]/2, 0]) {
        color("purple") hex_box_tray(center=true);
        // stack of hex boxes
        raise(floor0+xstack[2]/2) rotate([0, 90, 0]) raise(-xstack[0]/2) {
            colors = ["darkviolet", "blue", "green", "yellow", "black"];
            for (i=[0:Nplayers]) {
                raise_lid(i) color(colors[i]) tile_hex_box(center=true);
            }
            color("black") raise_lid(Nplayers+1) tile_hex_lid(center=true);
        }
    }
}

// single objects
*raise_lid(0, 0) tile_hex_lid(center=true);
*raise_lid(0, 0) tile_hex_box(center=true);
*hex_box_tray(center=true);
