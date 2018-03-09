module gfx.gl3.device;

import gfx.graal.device : Device;

class GlDevice : Device
{
    import core.time :              Duration;
    import gfx.bindings.opengl.gl : GlCmds30;
    import gfx.core.rc :            atomicRcCode;
    import gfx.gl3.context :        GlContext;
    import gfx.graal.buffer :       Buffer, BufferUsage;
    import gfx.graal.cmd :          CommandPool;
    import gfx.graal.format :       Format;
    import gfx.graal.image :        Image, ImageDims, ImageTiling, ImageType,
                                    ImageView, ImageUsage, Sampler, SamplerInfo;
    import gfx.graal.memory :       DeviceMemory, MappedMemorySet;
    import gfx.graal.presentation : CompositeAlpha, PresentMode, Surface,
                                    Swapchain;
    import gfx.graal.queue :        Queue;
    import gfx.graal.renderpass :   AttachmentDescription, Framebuffer,
                                    RenderPass, SubpassDependency,
                                    SubpassDescription;
    import gfx.graal.pipeline :     CopyDescritporSet, DescriptorSet,
                                    DescriptorSetLayout, DescriptorPool,
                                    DescriptorPoolSize, Pipeline, PipelineInfo,
                                    PipelineLayout, PipelineLayoutBinding,
                                    PushConstantRange, ShaderModule,
                                    ShaderLanguage, WriteDescriptorSet;
    import gfx.graal.sync :         Fence, Semaphore;
    import std.typecons : Flag;

    mixin(atomicRcCode);

    private GlContext _ctx;
    private GlCmds30 gl;

    this (GlContext ctx) {
        _ctx = ctx;
        gl = ctx.cmds;
    }

    override void dispose() {}

    override void waitIdle() {}

    override Queue getQueue(uint queueFamilyIndex, uint queueIndex) {
        return null;
    }

    CommandPool createCommandPool(uint queueFamilyIndex) {
        return null;
    }

    DeviceMemory allocateMemory(uint memPropIndex, size_t size) {
        return null;
    }
    void flushMappedMemory(MappedMemorySet set) {}
    void invalidateMappedMemory(MappedMemorySet set) {}

    Buffer createBuffer(BufferUsage usage, size_t size) {
        return null;
    }

    Image createImage(ImageType type, ImageDims dims, Format format,
                      ImageUsage usage, ImageTiling tiling, uint samples,
                      uint levels=1) {
        return null;
    }

    Sampler createSampler(in SamplerInfo info) {
        return null;
    }

    Semaphore createSemaphore() {
        return null;
    }

    Fence createFence(Flag!"signaled" signaled) {
        return null;
    }

    void resetFences(Fence[] fences) {}
    void waitForFences(Fence[] fences, Flag!"waitAll" waitAll, Duration timeout) {}

    Swapchain createSwapchain(Surface surface, PresentMode pm, uint numImages,
                              Format format, uint[2] size, ImageUsage usage,
                              CompositeAlpha alpha, Swapchain former=null) {
        return null;
    }

    RenderPass createRenderPass(in AttachmentDescription[] attachments,
                                in SubpassDescription[] subpasses,
                                in SubpassDependency[] dependencies) {
        return null;
    }

    Framebuffer createFramebuffer(RenderPass rp, ImageView[] attachments,
                                  uint width, uint height, uint layers) {
        return null;
    }

    ShaderModule createShaderModule(ShaderLanguage language, string code, string entryPoint) {
        return null;
    }

    DescriptorSetLayout createDescriptorSetLayout(in PipelineLayoutBinding[] bindings) {
        return null;
    }

    PipelineLayout createPipelineLayout(DescriptorSetLayout[] layouts, PushConstantRange[] ranges) {
        return null;
    }

    DescriptorPool createDescriptorPool(in uint maxSets, in DescriptorPoolSize[] sizes) {
        return null;
    }

    void updateDescriptorSets(WriteDescriptorSet[] writeOps, CopyDescritporSet[] copyOps) {}

    Pipeline[] createPipelines(PipelineInfo[] infos) {
        return null;
    }
}
