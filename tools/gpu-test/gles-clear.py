#!/usr/bin/env python3
"""
Smallest possible "does the GPU work through Mesa" test for the OnePlus 2
(Adreno 430 on the msm DRM render node), with no test tools installed: EGL
on GBM on /dev/dri/renderD128, an OpenGL ES 2 context without a surface, a
64x64 framebuffer object cleared by the GPU to a known colour, read back.
(tools/gpu-steps drives the GPU with hand-made command streams instead.)

  python3 gles-clear.py [/dev/dri/renderD128]

Prints the GL renderer and the pixel read back; "GPU OK" when it is the
colour asked for (51, 102, 153, 255).
"""
import ctypes as C
import os
import sys

node = sys.argv[1] if len(sys.argv) > 1 else "/dev/dri/renderD128"
egl = C.CDLL("libEGL.so.1")
gles = C.CDLL("libGLESv2.so.2")
gbm = C.CDLL("libgbm.so.1")

gbm.gbm_create_device.restype = C.c_void_p
gbm.gbm_create_device.argtypes = [C.c_int]
egl.eglGetPlatformDisplay.restype = C.c_void_p
egl.eglGetPlatformDisplay.argtypes = [C.c_uint, C.c_void_p, C.c_void_p]
egl.eglInitialize.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int)]
egl.eglChooseConfig.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_void_p),
                                C.c_int, C.POINTER(C.c_int)]
egl.eglCreateContext.restype = C.c_void_p
egl.eglCreateContext.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)]
egl.eglMakeCurrent.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
egl.eglQueryString.restype = C.c_char_p
egl.eglQueryString.argtypes = [C.c_void_p, C.c_int]
gles.glGetString.restype = C.c_char_p

EGL_PLATFORM_GBM_KHR = 0x31D7
EGL_NONE = 0x3038
EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT = 0x3040, 0x4
EGL_SURFACE_TYPE = 0x3033
EGL_CONTEXT_CLIENT_VERSION = 0x3098
EGL_OPENGL_ES_API = 0x30A0
EGL_VENDOR, EGL_EXTENSIONS = 0x3053, 0x3055
GL_VENDOR, GL_RENDERER, GL_VERSION = 0x1F00, 0x1F01, 0x1F02
GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 = 0x8D40, 0x8CE0
GL_TEXTURE_2D, GL_RGBA, GL_UNSIGNED_BYTE = 0x0DE1, 0x1908, 0x1401
GL_COLOR_BUFFER_BIT, GL_FRAMEBUFFER_COMPLETE = 0x4000, 0x8CD5


def die(msg):
    print("FAIL:", msg)
    sys.exit(1)


fd = os.open(node, os.O_RDWR)
dev = gbm.gbm_create_device(fd)
if not dev:
    die("gbm_create_device")
dpy = egl.eglGetPlatformDisplay(EGL_PLATFORM_GBM_KHR, C.c_void_p(dev), None)
major, minor = C.c_int(), C.c_int()
if not dpy or not egl.eglInitialize(dpy, C.byref(major), C.byref(minor)):
    die("eglInitialize (error %#x)" % egl.eglGetError())
print("EGL", major.value, minor.value, egl.eglQueryString(dpy, EGL_VENDOR).decode())
if b"EGL_KHR_surfaceless_context" not in egl.eglQueryString(dpy, EGL_EXTENSIONS):
    die("no EGL_KHR_surfaceless_context")
egl.eglBindAPI(EGL_OPENGL_ES_API)
attrs = (C.c_int * 5)(EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_SURFACE_TYPE, 0, EGL_NONE)
cfg, n = C.c_void_p(), C.c_int()
if not egl.eglChooseConfig(dpy, attrs, C.byref(cfg), 1, C.byref(n)) or n.value < 1:
    die("eglChooseConfig")
cattrs = (C.c_int * 3)(EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE)
ctx = egl.eglCreateContext(dpy, cfg, None, cattrs)
if not ctx:
    die("eglCreateContext (error %#x)" % egl.eglGetError())
if not egl.eglMakeCurrent(dpy, None, None, C.c_void_p(ctx)):
    die("eglMakeCurrent (error %#x)" % egl.eglGetError())
print("GL_VENDOR  ", gles.glGetString(GL_VENDOR).decode())
print("GL_RENDERER", gles.glGetString(GL_RENDERER).decode())
print("GL_VERSION ", gles.glGetString(GL_VERSION).decode())
sys.stdout.flush()

# a 64x64 RGBA texture as the colour buffer of a framebuffer object
tex, fbo = C.c_uint(), C.c_uint()
gles.glGenTextures(1, C.byref(tex))
gles.glBindTexture(GL_TEXTURE_2D, tex)
gles.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, None)
gles.glGenFramebuffers(1, C.byref(fbo))
gles.glBindFramebuffer(GL_FRAMEBUFFER, fbo)
gles.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0)
st = gles.glCheckFramebufferStatus(GL_FRAMEBUFFER)
if st != GL_FRAMEBUFFER_COMPLETE:
    die("framebuffer incomplete %#x" % st)
gles.glViewport(0, 0, 64, 64)
gles.glClearColor(C.c_float(0.2), C.c_float(0.4), C.c_float(0.6), C.c_float(1.0))
gles.glClear(GL_COLOR_BUFFER_BIT)
gles.glFinish()
px = (C.c_ubyte * 4)()
gles.glReadPixels(32, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px)
got = tuple(px)
print("pixel", got, "glGetError %#x" % gles.glGetError())
print("GPU OK" if got == (51, 102, 153, 255) else "GPU WRONG (expected (51, 102, 153, 255))")
