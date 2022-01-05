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
module box(size, wall=1, frame=false, a=0, center=false) {
    vint = is_list(size) ? size : [size, size, size];
    vext = [vint[0] + 2*wall, vint[1] + 2*wall, vint[2] + wall];
    vcut = [vint[0], vint[1], vint[2] - wall];
    origin = center ? [0, 0, vext[2]/2 - wall] : vext/2;
    translate(origin) rotate(a) {
        difference() {
            cube(vext, center=true);  // exterior
            raise(wall/2) cube(vint, center=true);  // interior
            raise(2*wall) cube(vcut, center=true);  // top cut
            if (frame) {
                for (n=[0:2]) for (i=[-1,+1])
                    translate(2*i*unit_axis(n)*wall) cube(vcut, center=true);
            }
        }
    }
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
Hgroove = flayer(floor0/2);  // depth of tier alignment grooves

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
            // exterior
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
    origin = center ? [0, 0, 0] : [sin(60)*Rbighex, Rbighex, Hboard/2];
    translate(origin) hex_tile(r=Rbighex, center=true);
}
module button_tile_tray(color=undef, center=false) {
    rint = 2*gap0;  // single gap is too snug
    rext = rint + wall0;
    origin = center ? [0, 0, 0] : [Rbighex + rext, sin(60)*Rbighex + rext, 0];
    translate(origin) {
        %raise(floor0+Hboard/2) button_tile(center=true);
        color(color) {
            difference() {
                // exterior
                linear_extrude(Hrecess + floor0)
                    offset(r=rext) hex_poly(r=Rbighex, center=true);
                // interior
                raise(floor0) linear_extrude(Hrecess + floor0)
                    offset(r=rint) hex_poly(r=Rbighex, center=true);
                // center cut-out
                linear_extrude(Vblock[2], center=true)
                    offset(r=rext) hex_poly(r=2/3*Rbighex, center=true);
                // grooves
                for (a=[0:60:120]) rotate(a)
                    cube([3*Rbighex, wall0+2*gap0, 2*Hgroove], center=true);
            }
        }
    }
}

module button_box(color=undef, center=false) {
    foot = [Vblock[0], 2*Vblock[1]];
    rext = 2.7;  // match cat tile boxes
    rint = rext - wall0;
    well = [foot[0]-2*wall0, foot[1]-2*wall0];

    // token well dimensions
    rmid = Rhex - wall0/2;  // align outside of wall to hex tile
    yside = 0;
    xside = well[0]/2 + wall0/2;
    yend = well[1]/2 + wall0/2;
    xend = yend * tan(30);
    ymid = rmid * sin(60);
    xmid = rmid * cos(60);
    pside = [
        [rmid, 0], [xside, yside], [xside, yend], [xend, yend], [xmid, ymid]
    ];
    pend = [[xmid, ymid], [xend, yend], [-xend, yend], [-xmid, ymid]];

    module well_poly(scale=[1,1]) {
        linear_extrude(Vblock[2])
            offset(r=rint) offset(r=-wall0/2-rint) scale(scale) children();
    }

    origin = center ? [0, 0] : foot/2;
    translate(origin) {
        *raise(Hshelf+Hboard/2) button_tile(center=true);
        color(color) {
            difference() {
                // shell
                linear_extrude(Vblock[2]) rounded_square(rext, foot);
                // scoring tile recess
                raise(Hshelf-floor0+Hgroove)
                    linear_extrude(Vblock[2]) rounded_square(rext, well);
                // token wells
                raise() {
                    well_poly() hex_poly(r=rmid, center=true);
                    well_poly([+1, +1]) polygon(pside);
                    well_poly([-1, +1]) polygon(pside);
                    well_poly([+1, -1]) polygon(pside);
                    well_poly([-1, -1]) polygon(pside);
                    well_poly([+1, +1]) polygon(pend);
                    well_poly([+1, -1]) polygon(pend);
                }
            }
            // center well bump
            rbump = rmid - wall0/2 - 2*Hboard;  // 2 tiles thick from wall
            rbump0 = rbump + floor0;  // 45 degrees through floor
            rbump1 = rbump - Hboard;  // 45 degrees above floor
            linear_extrude(floor0+Hboard, scale=rbump1/rbump0)
                hex_poly(r=rbump0, center=true);
        }
    }
}

// complete organizer
module organizer() {
    %color("gold", 0.5) box(interior, frame=true, center=true);
    %translate([0, (Vmat[1]-interior[1])/2, 0]) {
        raise(0.5*Vmat[2]) color("#ffffc0", 0.5) cube(Vmat, center=true);
        raise(1.5*Vmat[2]) color("#c0ffc0", 0.5) cube(Vmat, center=true);
        raise(2.5*Vmat[2]) color("#d0e0ff", 0.5) cube(Vmat, center=true);
        raise(3.5*Vmat[2]) color("#e0c0ff", 0.5) cube(Vmat, center=true);
    }

    translate([interior[0]/4, Vmat[1]/2, 0]) {
        color("mediumpurple") hex_box_tray(center=true);
        // stack of hex boxes
        raise(floor0+xstack[2]/2) rotate([0, 90, 0]) raise(-xstack[0]/2) {
            colors = ["#6000c0", "blue", "green", "yellow", "#202020"];
            for (i=[0:Nplayers]) {
                raise_lid(i) color(colors[i]) tile_hex_box(center=true);
            }
            color("#202020") raise_lid(Nplayers+1) tile_hex_lid(center=true);
        }
    }
    rotate(90) translate([(Vblock[0]-interior[0])/2, 0, Hmats]) {
        translate([0, -Vblock[1]*3/2]) {
            cat_tile_box(color="orange", center=true);
            raise(Vblock[2])
                cat_tile_box(color="orange", center=true);
        }
        translate([0, -Vblock[1]*1/2])
            cat_tile_box(color="ivory", center=true);
        translate([0, +Vblock[1]*1/2])
            cat_tile_box(color="ivory", center=true);
        translate([0, +Vblock[1]*3/2]) {
            cat_tile_box(color="#202020", center=true);
            raise(Vblock[2])
                cat_tile_box(color="#202020", center=true);
        }
        raise(Vblock[2]) {
            button_box("mediumpurple", center=true);
            raise(Hshelf-floor0)
                button_tile_tray("mediumpurple", center=true);
        }
    }
}

// single objects
*raise_lid(0, 0) tile_hex_lid(center=true);
*raise_lid(0, 0) tile_hex_box(center=true);
*hex_box_tray(center=true);
*cat_tile_box(center=true);
*button_box(center=true);
*button_tile_tray(center=true);

organizer();

// prototypes
*intersection() {
    button_box(center=true);
    linear_extrude(Vblock[2]) offset(r=2.7-wall0) offset(r=wall0-2.7)
        hex_poly(center=true);
}
