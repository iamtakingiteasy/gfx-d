module gfx.window.xcb.context;

import gfx.bindings.core : SharedLib;
import gfx.gl3.context : GlContext, GlAttribs;

class XcbGlContext : GlContext
{
    import gfx.bindings.core : SharedSym;
    import gfx.bindings.opengl.gl : Gl;
    import gfx.bindings.opengl.glx : Glx, GLXContext, GLXFBConfig;
    import gfx.core.rc : atomicRcCode, Disposable;
    import X11.Xlib : XDisplay = Display;

    mixin(atomicRcCode);

    private XDisplay* _dpy;
    private int _mainScreenNum;
    private GlAttribs _attribs;
    private Glx _glx;
    private Gl _gl;
    private string[] _glxAvailExts;
    private string[] _glAvailExts;
    private GLXContext _ctx;
    private bool ARB_create_context;
    private bool MESA_query_renderer;
    private bool MESA_swap_control;
    private bool EXT_swap_control;

    this (XDisplay* dpy, in int mainScreenNum, in GlAttribs attribs)
    {
        import gfx.bindings.core : openSharedLib, loadSharedSym, SharedLib;
        import gfx.bindings.opengl : splitExtString;
        import gfx.bindings.opengl.gl : GL_EXTENSIONS;
        import gfx.bindings.opengl.glx : PFN_glXGetProcAddressARB;
        import gfx.gl3.context : extensionsToLoad, glAvailableExtensions, glExtensionsToLoad;
        import std.algorithm : canFind;
        import std.exception : enforce;
        import std.experimental.logger : trace, tracef;
        import X11.Xlib : XSync;

        _dpy = dpy;
        _mainScreenNum = mainScreenNum;
        _attribs = attribs;

        auto lib = loadGlLib();
        auto getProcAddress = cast(PFN_glXGetProcAddressARB)enforce(loadSharedSym(lib, "glXGetProcAddressARB"));
        SharedSym loadSymbol(in string symbol) {
            import std.string : toStringz;
            return cast(SharedSym)getProcAddress(cast(const(ubyte)*)toStringz(symbol));
        }

        _glx = new Glx(&loadSymbol);

        const glxExts = splitExtString(_glx.QueryExtensionsString(_dpy, _mainScreenNum));
        ARB_create_context = glxExts.canFind("GLX_ARB_create_context");
        MESA_query_renderer = glxExts.canFind("GLX_MESA_query_renderer");
        MESA_swap_control = glxExts.canFind("GLX_MESA_swap_control");
        EXT_swap_control = glxExts.canFind("GLX_EXT_swap_control");

        enforce( ARB_create_context && ( MESA_swap_control || EXT_swap_control ));

        auto fbc = getGlxFBConfig(_attribs);
        const ctxAttribs = getCtxAttribs(_attribs);
        tracef("creating OpenGL %s.%s context", _attribs.majorVersion, _attribs.minorVersion);
        _ctx = enforce(
            _glx.CreateContextAttribsARB(_dpy, fbc, null, 1, &ctxAttribs[0])
        );
        XSync(_dpy, 0);

        _gl = new Gl(&loadSymbol);

        trace("done loading GL/GLX");
    }

    override void dispose() {
        import gfx.bindings.core : closeSharedLib;
        import std.experimental.logger : trace;

        _glx.DestroyContext(_dpy, _ctx);
        trace("destroyed GL/GLX context");
    }


    override @property Gl gl() {
        return _gl;
    }

    override @property GlAttribs attribs() {
        return _attribs;
    }

    override bool makeCurrent(size_t nativeHandle)
    {
        import gfx.bindings.opengl.glx : GLXDrawable;
        return _glx.MakeCurrent(_dpy, cast(GLXDrawable)nativeHandle, _ctx) != 0;
    }

    override void doneCurrent()
    {
        _glx.MakeCurrent(_dpy, 0, null);
    }

    override @property bool current() const
    {
        return _glx.GetCurrentContext() is _ctx;
    }

    override @property int swapInterval()
    {
        import gfx.bindings.opengl.glx : GLXDrawable;
        if (MESA_swap_control) {
            return _glx.GetSwapIntervalMESA();
        }
        else if (EXT_swap_control) {
            GLXDrawable drawable = _glx.GetCurrentDrawable();
            uint swap;

            if (drawable) {
                import gfx.bindings.opengl.glx : GLX_SWAP_INTERVAL_EXT;
                _glx.QueryDrawable(_dpy, drawable, GLX_SWAP_INTERVAL_EXT, &swap);
                return swap;
            }
            else {
                import std.experimental.logger : warningf;
                warningf("could not get glx drawable to get swap interval");
                return -1;
            }

        }
        return -1;
    }

    override @property void swapInterval(int interval)
    {
        import gfx.bindings.opengl.glx : GLXDrawable;

        if (MESA_swap_control) {
            _glx.SwapIntervalMESA(interval);
        }
        else if (EXT_swap_control) {
            GLXDrawable drawable = _glx.GetCurrentDrawable();

            if (drawable) {
                _glx.SwapIntervalEXT(_dpy, drawable, interval);
            }
            else {
                import std.experimental.logger : warningf;
                warningf("could not get glx drawable to set swap interval");
            }
        }
    }

    override void swapBuffers(size_t nativeHandle)
    {
        import gfx.bindings.opengl.glx : GLXDrawable;
        _glx.SwapBuffers(_dpy, cast(GLXDrawable)nativeHandle);
    }

    private GLXFBConfig getGlxFBConfig(in GlAttribs attribs)
    {
        import X11.Xlib : XFree;

        const glxAttribs = getGlxAttribs(attribs);

        int numConfigs;
        auto fbConfigs = _glx.ChooseFBConfig(_dpy, _mainScreenNum, &glxAttribs[0], &numConfigs);

        if (!fbConfigs || !numConfigs)
        {
            import std.experimental.logger : critical;
            critical("GFX-GLX: could not get fb config");
            return null;
        }
        scope (exit) XFree(fbConfigs);

        return fbConfigs[0];
    }

    private static class DummyWindow : Disposable
    {
        import X11.Xlib : XWindow = Window, XColormap = Colormap;
        import X11.Xlib;

        XWindow win;
        XColormap cmap;
        XDisplay* dpy;

        this (XDisplay* dpy, Glx glx, GLXFBConfig fbc)
        {
            this.dpy = dpy;
            auto vi = glx.GetVisualFromFBConfig( dpy, fbc );
            scope(exit) {
                XFree(vi);
            }

            cmap = XCreateColormap(dpy, XRootWindow(dpy, XDefaultScreen(dpy)),
                                                vi.visual, AllocNone );

            XSetWindowAttributes swa;
            swa.colormap = cmap;
            swa.background_pixmap = None ;
            swa.border_pixel      = 0;
            swa.event_mask        = StructureNotifyMask;

            win = XCreateWindow(dpy, XRootWindow(dpy, vi.screen),
                    0, 0, 100, 100, 0, vi.depth, InputOutput, vi.visual,
                    CWBorderPixel|CWColormap|CWEventMask, &swa);
        }

        override void dispose()
        {
            XDestroyWindow(dpy, win);
            XFreeColormap(dpy, cmap);
        }
    }
}


private SharedLib loadGlLib()
{
    import gfx.bindings.core : openSharedLib;

    immutable glLibNames = ["libGL.so.1", "libGL.so"];

    foreach (ln; glLibNames) {
        auto lib = openSharedLib(ln);
        if (lib) {
            import std.experimental.logger : tracef;
            tracef("opening shared library %s", ln);
            return lib;
        }
    }

    import std.conv : to;
    throw new Exception("could not load any of these libraries: " ~ glLibNames.to!string);
}

private int[] getGlxAttribs(in GlAttribs attribs) pure
{
    import gfx.bindings.opengl.glx;
    import gfx.graal.format : formatDesc, redBits, greenBits, blueBits,
                              alphaBits, depthBits, stencilBits;

    int[] glxAttribs = [
        GLX_X_RENDERABLE,   1,
        GLX_DRAWABLE_TYPE,  GLX_WINDOW_BIT,
        GLX_RENDER_TYPE,    GLX_RGBA_BIT,
        GLX_X_VISUAL_TYPE,  GLX_TRUE_COLOR
    ];

    const colorDesc = formatDesc(attribs.colorFormat);
    const depthStencilDesc = formatDesc(attribs.depthStencilFormat);

    const r = redBits(colorDesc.surfaceType);
    const g = greenBits(colorDesc.surfaceType);
    const b = blueBits(colorDesc.surfaceType);
    const a = alphaBits(colorDesc.surfaceType);
    const d = depthBits(depthStencilDesc.surfaceType);
    const s = stencilBits(depthStencilDesc.surfaceType);

    if (r) glxAttribs ~= [GLX_RED_SIZE, r];
    if (g) glxAttribs ~= [GLX_GREEN_SIZE, g];
    if (b) glxAttribs ~= [GLX_BLUE_SIZE, b];
    if (a) glxAttribs ~= [GLX_ALPHA_SIZE, a];
    if (d) glxAttribs ~= [GLX_DEPTH_SIZE, d];
    if (s) glxAttribs ~= [GLX_STENCIL_SIZE, s];

    if (attribs.doublebuffer) glxAttribs ~= [GLX_DOUBLEBUFFER, 1];

    if (attribs.samples > 1)
        glxAttribs ~= [GLX_SAMPLE_BUFFERS, 1, GLX_SAMPLES, attribs.samples];

    return glxAttribs ~ 0;
}

private int[] getCtxAttribs(in GlAttribs attribs) pure
{
    import gfx.bindings.opengl.glx;
    import gfx.gl3.context : GlProfile;

    int[] ctxAttribs = [
        GLX_CONTEXT_MAJOR_VERSION_ARB, attribs.majorVersion,
        GLX_CONTEXT_MINOR_VERSION_ARB, attribs.minorVersion
    ];
    if (attribs.decimalVersion >= 32) {
        ctxAttribs ~= GLX_CONTEXT_PROFILE_MASK_ARB;
        if (attribs.profile == GlProfile.core) {
            ctxAttribs ~= GLX_CONTEXT_CORE_PROFILE_BIT_ARB;
        }
        else {
            ctxAttribs ~= GLX_CONTEXT_COMPATIBILITY_PROFILE_BIT_ARB;
        }
    }

    return ctxAttribs ~ 0;
}