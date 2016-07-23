module triangle;

import gfx.core : Primitive;
import gfx.core.rc : Rc, rc, makeRc;
import gfx.core.typecons : Option, none, some;
import gfx.core.format : Rgba8, Depth32F;
import gfx.core.buffer : createVertexBuffer;
import gfx.core.program : ShaderSet, Program;
import gfx.core.pso.meta;
import gfx.core.pso : PipelineDescriptor, PipelineState, VertexBufferSet;
import gfx.core.state : Rasterizer;
import gfx.core.command : clearColor, Instance;

import gfx.window.glfw : gfxGlfwWindow;

import std.stdio : writeln;


struct Vertex {
    @GfxName("a_Pos")   float[2] pos;
    @GfxName("a_Color") float[3] color;
}

struct PipeMeta {
                        VertexBuffer!Vertex input;
    @GfxName("o_Color") RenderTarget!Rgba8 output;
}

alias PipeState = PipelineState!PipeMeta;

static assert(isMetaStruct!PipeMeta);

alias PipeInit = PipelineInit!PipeMeta;
alias PipeData = PipelineData!PipeMeta;



immutable triangle = [
    Vertex([-0.5, -0.5], [1.0, 0.0, 0.0]),
    Vertex([ 0.5, -0.5], [0.0, 1.0, 0.0]),
    Vertex([ 0.0,  0.5], [0.0, 0.0, 1.0]),
];

immutable float[4] backColor = [0.1, 0.2, 0.3, 1.0];



int main()
{
    auto window = gfxGlfwWindow!(Rgba8, Depth32F)("gfx-d - Triangle", 640, 480);
    {
        auto vbuf = rc(createVertexBuffer!Vertex(triangle));
        auto prog = makeRc!Program(ShaderSet.vertexPixel(
            import("130-triangle.v.glsl"),
            import("130-triangle.f.glsl"),
        ));
        auto pipe = makeRc!PipeState(prog.obj, Primitive.Triangles, Rasterizer.newFill());

        auto data = PipeState.Data.init;
        data.input = vbuf;
        auto dataSet = pipe.makeDataSet(data);


        auto cmdBuf = rc(window.device.factory.makeCommandBuffer());

        import std.datetime : StopWatch;

        size_t frameCount;
        StopWatch sw;
        sw.start();

        /* Loop until the user closes the window */
        while (!window.shouldClose) {

            cmdBuf.clearColor(null, clearColor(backColor));
            cmdBuf.bindPipelineState(pipe.obj);
            cmdBuf.bindVertexBuffers(dataSet.vertexBuffers);
            cmdBuf.callDraw(0, cast(uint)vbuf.count, none!Instance);

            window.device.submit(cmdBuf);

            /* Swap front and back buffers */
            window.swapBuffers();

            /* Poll for and process events */
            window.pollEvents();
            frameCount += 1;


            version(Windows) {
                // vsync is not always enabled with glfw on windows
                // adding a sleep to limit frame rate to < 100 FPS
                import core.thread : Thread;
                import core.time : dur;
                Thread.sleep( dur!"msecs"(10) );
            }
        }

        auto ms = sw.peek().msecs();
        writeln("FPS: ", 1000.0f*frameCount / ms);
    }

    return 0;
}
