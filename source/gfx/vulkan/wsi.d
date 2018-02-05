/// Vulkan Window System Integration module
module gfx.vulkan.wsi;

import core.time : Duration;

import gfx.bindings.vulkan;

import gfx.core.rc;
import gfx.graal;
import gfx.graal.format;
import gfx.graal.image;
import gfx.graal.sync;
import gfx.vulkan;
import gfx.vulkan.image;
import gfx.vulkan.error;
import gfx.vulkan.sync;

import std.exception : enforce;

// instance level extensions

enum surfaceExtension = "VK_KHR_surface";

version(Windows) {
    enum win32SurfaceExtension = "VK_KHR_win32_surface";
}
version(linux) {
    enum waylandSurfaceExtension = "VK_KHR_wayland_surface";
    enum xcbSurfaceExtension = "VK_KHR_xcb_surface";
}

// device level extensions

enum swapChainExtension = "VK_KHR_swapchain";

version(linux) {
    import wayland.client;

    // TODO: fall back from wayland to XCB
    enum surfaceInstanceExtensions = [
        surfaceExtension, waylandSurfaceExtension, xcbSurfaceExtension
    ];

    Surface createVulkanWaylandSurface(Instance graalInst, WlDisplay wlDpy, WlSurface wlSurf)
    {
        auto inst = enforce(
            cast(VulkanInstance)graalInst,
            "createVulkanWaylandSurface called with non-vulkan instance"
        );

        VkWaylandSurfaceCreateInfoKHR sci;
        sci.sType = VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR;
        sci.display = wlDpy.native;
        sci.surface = wlSurf.proxy;

        VkSurfaceKHR vkSurf;
        vulkanEnforce(
            inst.cmds.createWaylandSurfaceKHR(inst.vk, &sci, null, &vkSurf),
            "Could not create Vulkan Wayland Surface"
        );

        return new VulkanSurface(vkSurf, inst);
    }
}

version(GfxVulkanWin32) {
    enum surfaceInstanceExtensions = [
        surfaceExtension, win32SurfaceExtension
    ];
}
version(GfxOffscreen) {
    enum surfaceInstanceExtensions = [];
}


package:

class VulkanSurface : VulkanInstObj!(VkSurfaceKHR), Surface
{
    mixin(atomicRcCode);

    this(VkSurfaceKHR vk, VulkanInstance inst)
    {
        super(vk, inst);
    }

    override void dispose() {
        inst.cmds.destroySurfaceKHR(vkInst, vk, null);
        super.dispose();
    }
}

class VulkanSwapchain : VulkanDevObj!(VkSwapchainKHR, "destroySwapchainKHR"), Swapchain
{
    mixin(atomicRcCode);

    this(VkSwapchainKHR vk, VulkanDevice dev, uint[2] size, Format format)
    {
        super(vk, dev);
        _size = size;
        _format = format;
    }

    override @property Format format() {
        return _format;
    }

    // not releasing images on purpose, the lifetime is owned by implementation

    override @property ImageBase[] images() {

        if (!_images.length) {
            uint count;
            vulkanEnforce(
                cmds.getSwapchainImagesKHR(vkDev, vk, &count, null),
                "Could not get vulkan swap chain images"
            );
            auto vkImgs = new VkImage[count];
            vulkanEnforce(
                cmds.getSwapchainImagesKHR(vkDev, vk, &count, &vkImgs[0]),
                "Could not get vulkan swap chain images"
            );

            import std.algorithm : map;
            import std.array : array;
            _images = vkImgs
                    .map!((VkImage vkImg) {
                        const dims = ImageDims.d2(_size[0], _size[1]);
                        auto img = new VulkanImageBase(vkImg, dev, ImageType.d2, dims, _format);
                        return cast(ImageBase)img;
                    })
                    .array;
        }

        return _images;
    }

    override uint acquireNextImage(Duration timeout, Semaphore graalSemaphore, out bool suboptimal)
    {
        auto sem = enforce(
            cast(VulkanSemaphore)graalSemaphore,
            "a non vulkan semaphore was passed"
        );

        ulong vkTimeout = timeout.total!"nsecs";
        import core.time : dur;
        if (timeout < dur!"nsecs"(0)) {
            vkTimeout = ulong.max;
        }

        uint img;
        const res = cmds.acquireNextImageKHR(vkDev, vk, vkTimeout, sem.vk, VK_NULL_ND_HANDLE, &img);

        if (res == VK_SUBOPTIMAL_KHR) {
            suboptimal = true;
        }
        else {
            enforce(res == VK_SUCCESS, "Could not acquire next vulkan image");
        }

        return img;
    }

    private ImageBase[] _images;
    private uint[2] _size;
    private Format _format;
}
