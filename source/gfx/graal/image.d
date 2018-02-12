/// ImageBase module
module gfx.graal.image;

import gfx.core.rc;
import gfx.core.typecons;
import gfx.graal.format;
import gfx.graal.memory;
import gfx.graal.pipeline : CompareOp;

import std.typecons : Flag;

enum ImageType {
    d1, d1Array,
    d2, d2Array,
    d3, cube, cubeArray
}

bool isCube(in ImageType it) {
    return it == ImageType.cube || it == ImageType.cubeArray;
}

bool isArray(in ImageType it) {
    return it == ImageType.d1Array || it == ImageType.d2Array || it == ImageType.cubeArray;
}

enum CubeFace {
    none,
    posX, negX,
    posY, negY,
    posZ, negZ,
}

/// an array of faces in the order that is expected during cube initialization
immutable cubeFaces = [
    CubeFace.posX, CubeFace.negX,
    CubeFace.posY, CubeFace.negY,
    CubeFace.posZ, CubeFace.negZ,
];

struct ImageDims
{
    uint width;
    uint height;
    uint depth;
    uint layers;

    static ImageDims d1 (in uint width) {
        return ImageDims(width, 1, 1, 1);
    }
    static ImageDims d2 (in uint width, in uint height) {
        return ImageDims(width, height, 1, 1);
    }
    static ImageDims d3 (in uint width, in uint height, in uint depth) {
        return ImageDims(width, height, depth, 1);
    }
    static ImageDims cube (in uint width, in uint height) {
        return ImageDims(width, height, 6, 1);
    }
    static ImageDims d1Array (in uint width, in uint layers) {
        return ImageDims(width, 1, 1, layers);
    }
    static ImageDims d2Array (in uint width, uint height, in uint layers) {
        return ImageDims(width, height, 1, layers);
    }
    static ImageDims cubeArray (in uint width, in uint height, in uint layers) {
        return ImageDims(width, height, 6, layers);
    }
}

enum ImageUsage {
    none = 0,
    transferSrc             = 0x01,
    transferDst             = 0x02,
    sampled                 = 0x04,
    storage                 = 0x08,
    colorAttachment         = 0x10,
    depthStencilAttachment  = 0x20,
    transientAttachment     = 0x40,
    inputAttachment         = 0x80,
}

enum ImageLayout {
	undefined                       = 0,
	general                         = 1,
	colorAttachmentOptimal          = 2,
	depthStencilAttachmentOptimal   = 3,
	depthStencilReadOnlyOptimal     = 4,
	shaderReadOnlyOptimal           = 5,
	transferSrcOptimal              = 6,
	transferDstOptimal              = 7,
	preinitialized                  = 8,
    presentSrc                      = 1000001002, // TODO impl actual mapping to vulkan
}

enum ImageTiling {
    optimal,
    linear,
}

enum ImageAspect {
    color           = 0x01,
    depth           = 0x02,
    stencil         = 0x04,
    depthStencil    = depth | stencil,
}


struct ImageSubresourceLayer
{
    ImageAspect aspect;
    uint mipLevel       = 0;
    uint firstLayer     = 0;
    uint layers         = 1;
}

struct ImageSubresourceRange
{
    ImageAspect aspect;
    size_t firstLevel   = 0;
    size_t levels       = 1;
    size_t firstLayer   = 0;
    size_t layers       = 1;
}

enum CompSwizzle : ubyte
{
    identity,
    zero, one,
    r, g, b, a,
}

struct Swizzle {
    private CompSwizzle[4] rep;

    this(in CompSwizzle r, in CompSwizzle g, in CompSwizzle b, in CompSwizzle a)
    {
        rep = [r, g, b, a];
    }

    static @property Swizzle identity() {
        return Swizzle(
            CompSwizzle.identity, CompSwizzle.identity,
            CompSwizzle.identity, CompSwizzle.identity
        );
    }

    static @property Swizzle one() {
        return Swizzle(
            CompSwizzle.one, CompSwizzle.one,
            CompSwizzle.one, CompSwizzle.one
        );
    }

    static @property Swizzle zero() {
        return Swizzle(
            CompSwizzle.zero, CompSwizzle.zero,
            CompSwizzle.zero, CompSwizzle.zero
        );
    }

    static @property Swizzle opDispatch(string name)() {
        bool isSwizzleIdent() {
            foreach (char c; name) {
                switch (c) {
                case 'r': break;
                case 'g': break;
                case 'b': break;
                case 'a': break;
                case 'i': break;
                case 'o': break;
                case 'z': break;
                default: return false;
                }
            }
            return true;
        }
        CompSwizzle getComp(char c) {
            switch (c) {
            case 'r': return CompSwizzle.r;
            case 'g': return CompSwizzle.g;
            case 'b': return CompSwizzle.b;
            case 'a': return CompSwizzle.a;
            case 'i': return CompSwizzle.identity;
            case 'o': return CompSwizzle.one;
            case 'z': return CompSwizzle.zero;
            default: assert(false);
            }
        }

        static assert(name.length == 4, "Error: Swizzle."~name~". Swizzle identifier must have four components.");
        static assert(isSwizzleIdent(), "Wrong swizzle identifier: Swizzle."~name);
        return Swizzle(
            getComp(name[0]), getComp(name[1]), getComp(name[2]), getComp(name[3])
        );
    }

    size_t opDollar() const { return 4; }
    CompSwizzle opIndex(size_t ind) const { return rep[ind]; }
    const(CompSwizzle)[] opIndex() const { return rep[]; }
    size_t[2] opSlice(size_t dim)(size_t start, size_t end) const {
        return [start, end];
    }
    const(CompSwizzle)[] opIndex(size_t[2] slice) const {
        return rep[slice[0] .. slice[1]];
    }
}

///
unittest {
    assert(!__traits(compiles, Swizzle.rrr));
    assert(!__traits(compiles, Swizzle.qwer));

    assert(Swizzle.rgba == Swizzle(CompSwizzle.r, CompSwizzle.g, CompSwizzle.b, CompSwizzle.a));
    assert(Swizzle.rrbb == Swizzle(CompSwizzle.r, CompSwizzle.r, CompSwizzle.b, CompSwizzle.b));
    assert(Swizzle.aaag == Swizzle(CompSwizzle.a, CompSwizzle.a, CompSwizzle.a, CompSwizzle.g));
    assert(Swizzle.iiii == Swizzle.identity);
    assert(Swizzle.oooo == Swizzle.one);
    assert(Swizzle.zzzz == Swizzle.zero);
}

interface ImageBase
{
    @property ImageType type();
    @property Format format();
    @property ImageDims dims();
    @property uint levels();

    // TODO: deduce view type from subrange and image type
    ImageView createView(ImageType viewtype, ImageSubresourceRange isr, Swizzle swizzle);
}

interface Image : ImageBase, AtomicRefCounted
{
    @property MemoryRequirements memoryRequirements();
    /// The image keeps a reference of the device memory
    void bindMemory(DeviceMemory mem, in size_t offset);
}

interface ImageView : AtomicRefCounted
{
    @property ImageBase image();
    @property ImageSubresourceRange subresourceRange();
    @property Swizzle swizzle();
}


enum Filter {
    nearest,
    linear,
}


/// Specifies how texture coordinates outside the range `[0, 1]` are handled.
enum WrapMode {
    /// Repeat the texture. That is, sample the coordinate modulo `1.0`.
    repeat,
    /// Mirror the texture. Like tile, but uses abs(coord) before the modulo.
    mirrorRepeat,
    /// Clamp the texture to the value at `0.0` or `1.0` respectively.
    clamp,
    /// Use border color.
    border,
}

enum BorderColor
{
    floatTransparent,
    intTransparent,
    floatBlack,
    intBlack,
    floatWhite,
    intWhite,
}

///
struct SamplerInfo {
    Filter minFilter;
    Filter magFilter;
    Filter mipmapFilter;
    WrapMode[3] wrapMode;
    Option!float anisotropy;
    float lodBias;
    float[2] lodRange;
    Option!CompareOp compare;
    BorderColor borderColor;
    Flag!"unnormalizeCoords" unnormalizeCoords;

    static @property SamplerInfo bilinear() {
        SamplerInfo si;
        si.minFilter = Filter.linear;
        si.magFilter = Filter.linear;
        return si;
    }

    static @property SamplerInfo trilinear() {
        SamplerInfo si;
        si.minFilter = Filter.linear;
        si.magFilter = Filter.linear;
        si.mipmapFilter = Filter.linear;
        return si;
    }
}

interface Sampler : AtomicRefCounted
{}
