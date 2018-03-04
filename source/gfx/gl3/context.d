module gfx.gl3.context;

import gfx.core.rc : AtomicRefCounted;
import gfx.graal.format : Format;

enum GlProfile
{
    core,
    compatibility
}

struct GlAttribs
{
    enum profile = GlProfile.core;
    enum doublebuffer = true;

    uint majorVersion = 3;
    uint minorVersion = 0;

    uint samples;

    @property Format colorFormat() const {
        return _colorFormat;
    }
    @property Format depthStencilFormat() const {
        return _depthStencilFormat;
    }

    private Format _colorFormat = Format.rgba8_uNorm;
    private Format _depthStencilFormat = Format.d24s8_uNorm;

    @property int decimalVersion() const
    {
        return majorVersion * 10 + minorVersion;
    }
}

interface GlContext : AtomicRefCounted
{
    @property GlAttribs attribs() const;

    bool makeCurrent(size_t nativeHandle);

    void doneCurrent();

    @property bool current() const;

    @property int swapInterval()
    in { assert(current); }

    @property void swapInterval(int interval)
    in { assert(current); }

    void swapBuffers(size_t nativeHandle)
    in { assert(current); }
}