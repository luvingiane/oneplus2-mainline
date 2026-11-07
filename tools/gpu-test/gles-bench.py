#!/usr/bin/env python3
"""
Is it the GPU, the texture upload or the CPU? Offscreen timings on the phone
(msm render node, FD_MESA_DEBUG=sysmem), nothing is shown on screen:

  FD_MESA_DEBUG=sysmem python3 gles-bench.py [/dev/dri/renderD128]

  1. CPU: a pure-python loop and a 64 MiB memcpy (where the uploads start)
  2. upload: glTexImage2D of a 1080x1920 RGBA texture (8 MiB), repeated
  3. draw: full-screen textured quads (1080x1920) per second, GPU only (glFinish)
  4. both: upload + draw each frame (what a page turn costs)
"""
import ctypes as C
import os
import sys
import time

node = sys.argv[1] if len(sys.argv) > 1 else "/dev/dri/renderD128"

# 1. CPU
t = time.time()
s = 0
for i in range(3_000_000):
    s += i
cpu = time.time() - t
a = bytearray(64 << 20)
t = time.time()
b = bytes(a)
mc = time.time() - t
print("CPU loop 3M: %.2f s   memcpy 64 MiB: %.3f s = %.0f MiB/s" % (cpu, mc, 64 / mc), flush=True)

egl, gles, gbm = C.CDLL("libEGL.so.1"), C.CDLL("libGLESv2.so.2"), C.CDLL("libgbm.so.1")
gbm.gbm_create_device.restype = C.c_void_p
gbm.gbm_create_device.argtypes = [C.c_int]
egl.eglGetPlatformDisplay.restype = C.c_void_p
egl.eglGetPlatformDisplay.argtypes = [C.c_uint, C.c_void_p, C.c_void_p]
egl.eglInitialize.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int)]
egl.eglChooseConfig.argtypes = [C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_void_p), C.c_int, C.POINTER(C.c_int)]
egl.eglCreateContext.restype = C.c_void_p
egl.eglCreateContext.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.POINTER(C.c_int)]
egl.eglMakeCurrent.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
gles.glCreateShader.restype = C.c_uint
gles.glCreateProgram.restype = C.c_uint
gles.glGetAttribLocation.restype = C.c_int
gles.glGetUniformLocation.restype = C.c_int

fd = os.open(node, os.O_RDWR)
dev = gbm.gbm_create_device(fd)
dpy = egl.eglGetPlatformDisplay(0x31D7, C.c_void_p(dev), None)
egl.eglInitialize(dpy, C.byref(C.c_int()), C.byref(C.c_int()))
egl.eglBindAPI(0x30A0)
cfg, n = C.c_void_p(), C.c_int()
egl.eglChooseConfig(dpy, (C.c_int * 5)(0x3040, 4, 0x3033, 0, 0x3038), C.byref(cfg), 1, C.byref(n))
ctx = egl.eglCreateContext(dpy, cfg, None, (C.c_int * 3)(0x3098, 2, 0x3038))
egl.eglMakeCurrent(dpy, None, None, C.c_void_p(ctx))
W, H = 1080, 1920
GL_TEXTURE_2D, GL_RGBA, GL_UNSIGNED_BYTE = 0x0DE1, 0x1908, 0x1401

ft, fb = C.c_uint(), C.c_uint()
gles.glGenTextures(1, C.byref(ft))
gles.glBindTexture(GL_TEXTURE_2D, ft)
gles.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, None)
gles.glGenFramebuffers(1, C.byref(fb))
gles.glBindFramebuffer(0x8D40, fb)
gles.glFramebufferTexture2D(0x8D40, 0x8CE0, GL_TEXTURE_2D, ft, 0)
gles.glViewport(0, 0, W, H)

p = gles.glCreateProgram()
for kind, src in ((0x8B31, "attribute vec2 p; varying vec2 uv; void main(){ uv = p*0.5+0.5; gl_Position = vec4(p,0.,1.); }"),
                  (0x8B30, "precision mediump float; varying vec2 uv; uniform sampler2D t; void main(){ gl_FragColor = texture2D(t, uv); }")):
    sh = gles.glCreateShader(kind)
    s_ = C.c_char_p(src.encode())
    gles.glShaderSource(sh, 1, C.byref(s_), None)
    gles.glCompileShader(sh)
    gles.glAttachShader(p, sh)
gles.glLinkProgram(p)
gles.glUseProgram(p)
QUAD = (C.c_float * 8)(-1, -1, 1, -1, -1, 1, 1, 1)
loc = gles.glGetAttribLocation(C.c_uint(p), b"p")
gles.glEnableVertexAttribArray(loc)
gles.glVertexAttribPointer(loc, 2, 0x1406, 0, 0, QUAD)

src = C.c_uint()
gles.glGenTextures(1, C.byref(src))
gles.glBindTexture(GL_TEXTURE_2D, src)
gles.glTexParameteri(GL_TEXTURE_2D, 0x2801, 0x2600)
gles.glTexParameteri(GL_TEXTURE_2D, 0x2800, 0x2600)
pix = (C.c_ubyte * (W * H * 4))()


def upload(n):
    t0 = time.time()
    for _ in range(n):
        gles.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, pix)
    gles.glFinish()
    return (time.time() - t0) / n


def draw(n):
    t0 = time.time()
    for _ in range(n):
        gles.glDrawArrays(5, 0, 4)
    gles.glFinish()
    return (time.time() - t0) / n


upload(1)
u = upload(10)
print("upload 1080x1920 RGBA (8 MiB): %.1f ms each = %.0f MiB/s" % (u * 1000, 8 / u), flush=True)
d = draw(100)
print("draw full-screen textured quad: %.2f ms each = %.0f quads/s" % (d * 1000, 1 / d), flush=True)
t0 = time.time()
for _ in range(10):
    gles.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, pix)
    gles.glDrawArrays(5, 0, 4)
gles.glFinish()
print("upload + draw per frame: %.1f ms" % ((time.time() - t0) * 100), flush=True)
print("DONE")
