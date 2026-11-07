#!/usr/bin/env python3
"""
Step-by-step GPU probe for the OnePlus 2 on 7.3 (msm render node, no display):
which kind of work comes out black? Each step prints PASS/FAIL right away
(flushed), so a hang still tells how far it got.

  FD_MESA_DEBUG=sysmem python3 gles-probe.py [/dev/dri/renderD128]

Steps: clear 64x64, clear 1080x1920, draw a solid quad into 1080x1920,
texture 64x64 sampled into 64x64, texture 1080x1920 sampled into 1080x1920.
"""
import ctypes as C
import os
import sys

node = sys.argv[1] if len(sys.argv) > 1 else "/dev/dri/renderD128"
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
gles.glGetString.restype = C.c_char_p
gles.glCreateShader.restype = C.c_uint
gles.glCreateProgram.restype = C.c_uint
gles.glGetAttribLocation.restype = C.c_int
gles.glGetUniformLocation.restype = C.c_int

GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D = 0x8D40, 0x8CE0, 0x0DE1
GL_RGBA, GL_UNSIGNED_BYTE, GL_FLOAT = 0x1908, 0x1401, 0x1406
GL_COLOR_BUFFER_BIT, GL_TRIANGLE_STRIP = 0x4000, 5
GL_NEAREST, GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER = 0x2600, 0x2801, 0x2800
GL_VERTEX_SHADER, GL_FRAGMENT_SHADER = 0x8B31, 0x8B30


def say(msg):
    print(msg)
    sys.stdout.flush()


fd = os.open(node, os.O_RDWR)
dev = gbm.gbm_create_device(fd)
dpy = egl.eglGetPlatformDisplay(0x31D7, C.c_void_p(dev), None)
major, minor = C.c_int(), C.c_int()
egl.eglInitialize(dpy, C.byref(major), C.byref(minor))
egl.eglBindAPI(0x30A0)
cfg, n = C.c_void_p(), C.c_int()
egl.eglChooseConfig(dpy, (C.c_int * 5)(0x3040, 4, 0x3033, 0, 0x3038), C.byref(cfg), 1, C.byref(n))
ctx = egl.eglCreateContext(dpy, cfg, None, (C.c_int * 3)(0x3098, 2, 0x3038))
egl.eglMakeCurrent(dpy, None, None, C.c_void_p(ctx))
say("GL_RENDERER " + gles.glGetString(0x1F01).decode())


def fbo(w, h):
    tex, f = C.c_uint(), C.c_uint()
    gles.glGenTextures(1, C.byref(tex))
    gles.glBindTexture(GL_TEXTURE_2D, tex)
    gles.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, None)
    gles.glGenFramebuffers(1, C.byref(f))
    gles.glBindFramebuffer(GL_FRAMEBUFFER, f)
    gles.glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0)
    gles.glViewport(0, 0, w, h)
    return tex


def px(w, h, x, y):
    buf = (C.c_ubyte * 4)()
    gles.glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, buf)
    return tuple(buf)


def prog(vs, fs):
    p = gles.glCreateProgram()
    for kind, src in ((GL_VERTEX_SHADER, vs), (GL_FRAGMENT_SHADER, fs)):
        s = gles.glCreateShader(kind)
        a = C.c_char_p(src.encode())
        gles.glShaderSource(s, 1, C.byref(a), None)
        gles.glCompileShader(s)
        gles.glAttachShader(p, s)
    gles.glLinkProgram(p)
    gles.glUseProgram(p)
    return p


QUAD = (C.c_float * 8)(-1, -1, 1, -1, -1, 1, 1, 1)
VS = "attribute vec2 p; varying vec2 uv; void main(){ uv = p*0.5+0.5; gl_Position = vec4(p,0.,1.); }"
FS_SOLID = "precision mediump float; varying vec2 uv; void main(){ gl_FragColor = vec4(0.2,0.4,0.6,1.0); }"
FS_TEX = "precision mediump float; varying vec2 uv; uniform sampler2D t; void main(){ gl_FragColor = texture2D(t, uv); }"


def draw(p):
    loc = gles.glGetAttribLocation(C.c_uint(p), b"p")
    gles.glEnableVertexAttribArray(loc)
    gles.glVertexAttribPointer(loc, 2, GL_FLOAT, 0, 0, QUAD)
    gles.glDrawArrays(GL_TRIANGLE_STRIP, 0, 4)


def check(name, got, want, tol=3):
    ok = all(abs(a - b) <= tol for a, b in zip(got, want))
    say("%s %s: got %s want %s" % ("PASS" if ok else "FAIL", name, got, want))


for w, h in ((64, 64), (1080, 1920)):
    fbo(w, h)
    gles.glClearColor(C.c_float(0.2), C.c_float(0.4), C.c_float(0.6), C.c_float(1.0))
    gles.glClear(GL_COLOR_BUFFER_BIT)
    check("clear %dx%d" % (w, h), px(w, h, w // 2, h // 2), (51, 102, 153, 255))

fbo(1080, 1920)
p = prog(VS, FS_SOLID)
draw(p)
check("solid quad 1080x1920 (centre)", px(1080, 1920, 540, 960), (51, 102, 153, 255))
check("solid quad 1080x1920 (corner)", px(1080, 1920, 5, 5), (51, 102, 153, 255))
check("solid quad 1080x1920 (top)", px(1080, 1920, 1070, 1910), (51, 102, 153, 255))

for w, h in ((64, 64), (1080, 1920)):
    pix = (C.c_ubyte * (w * h * 4))()
    for i in range(w * h):
        pix[i * 4:i * 4 + 4] = (i % 251, (i // 7) % 253, 200, 255)
    src = C.c_uint()
    gles.glGenTextures(1, C.byref(src))
    gles.glBindTexture(GL_TEXTURE_2D, src)
    gles.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
    gles.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
    gles.glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, pix)
    fbo(w, h)
    gles.glBindTexture(GL_TEXTURE_2D, src)
    p = prog(VS, FS_TEX)
    gles.glUniform1i(gles.glGetUniformLocation(C.c_uint(p), b"t"), 0)
    draw(p)
    for (x, y) in ((1, 1), (w // 2, h // 2), (w - 2, h - 2)):
        i = y * w + x
        check("texture %dx%d at (%d,%d)" % (w, h, x, y), px(w, h, x, y), (i % 251, (i // 7) % 253, 200, 255))
say("DONE")
