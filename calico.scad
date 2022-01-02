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
module interior(a=45, center=false) {
    origin = [0, 0, center ? 0 : interior[2]/2];
    translate(origin) rotate(a) cube(interior, center=true);
}

// component metrics
Nplayers = 4;  // number of players, mats, design goal sets
mat = [228, 184, 4.9];  // dual-layer mat dimensions (approx. 9in x 7.25in)
Hmats = Nplayers * mat[2];  // height of stacked mats
Hboard = 2.6;  // tile & token thickness
Rhex = 3/4 * 25.4;  // hex major radius (center to vertex)


// container metrics
Hlid = 3.2;  // total height of lid + plug
Rlid = 1+wall0;  // offset radius from contents to outer lid/box edge
Rplug = 1-gap0;  // offset radius from contents to lid plug
Alid = 30;  // angle of lid chamfer
Hplug = Hlid - floor0;  // depth of lid below cap
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
            linear_extrude(floor0, center=false)
                hex_poly(grid=grid, center=true);
            mirror([0, 0, 1]) {
                cylinder(h=Hplug, r=Rplug);
                cylinder(h=Hchamfer, r1=Rlid, r2=Rplug);
            }
        }
    }
}
module hex_box(n=1, lid=false, grid=Ghex, center=false) {
    h0 = Hboard * n + floor0;
    h = clayer(h0 + Hplug);
    // TODO: center z-axis
    origin = center ? [0, 0] : -hex_min(grid) + [1, 1] * Rlid;
    translate(origin) {
        difference() {
            // exterior
            linear_extrude(h, center=false)
                offset(r=Rlid) hex_poly(grid=grid, center=true);
            // interior
            raise() linear_extrude(h, center=false)
                offset(r=Rlid-wall0) hex_poly(grid=grid, center=true);
            // lid chamfer
            raise(h+Hseam) hex_lid(grid=grid, center=true);
        }
        // create lid bottom
        if (lid) hex_lid(grid=grid, center=true);
        // ghost tiles
        %raise(floor0 + Hboard * n/2)
            hex_tile(n=n, grid=grid, center=true);
    }
}

module tile_hex_box(n=1, lid=false, center=false) {
    hex_box(n=n, lid=lid, grid=Ghex, center=center);
}
module tile_hex_lid(center=false) {
    hex_lid(grid=Ghex, center=center);
}

module raise_lid(n=1, k=1, lid=false) {
    raise(k*(Hlid+Hseam) + n*Hboard + (lid?Hplug:0)) children();
}

union() {
    %interior();
    ntiles = 6;
    k = Nplayers+1;
    for (i=[0:k-1]) {
        raise_lid(n=i*ntiles, k=i, lid=true) tile_hex_box(ntiles, lid=true);
    }
    raise_lid(n=k*ntiles, k=k, lid=true) tile_hex_lid();
}
