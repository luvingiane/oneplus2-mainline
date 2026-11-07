#!/usr/bin/env python3
"""
Show the Adreno's own work on the OnePlus 2 screen (6.12, msm headless +
VRAM carveout, FD_MESA_DEBUG=sysmem): the GPU draws an animated Mandelbrot
set into an off-screen framebuffer the size of the screen; each frame is read
back and copied into the bootloader framebuffer (/dev/fb0), which the panel
shows while op2-kick keeps the command-mode panel refreshing.

  FD_MESA_DEBUG=sysmem python3 gles-demo.py [seconds]
"""
import ctypes as C
import os
import struct
import sys
import time

secs = float(sys.argv[1]) if len(sys.argv) > 1 else 20
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
gles.glGetUniformLocation.restype = C.c_int


def die(m):
    print("FAIL:", m)
    sys.exit(1)


# screen framebuffer
w, h = (int(x) for x in open("/sys/class/graphics/fb0/virtual_size").read().split(","))
bpp = int(open("/sys/class/graphics/fb0/bits_per_pixel").read())
stride = int(open("/sys/class/graphics/fb0/stride").read())
print(f"fb0 {w}x{h} {bpp} bpp stride {stride}")

fd = os.open("/dev/dri/renderD128", os.O_RDWR)
dpy = egl.eglGetPlatformDisplay(0x31D7, C.c_void_p(gbm.gbm_create_device(fd)), None)
if not dpy or not egl.eglInitialize(dpy, None, None):
    die("egl")
egl.eglBindAPI(0x30A0)
cfg, n = C.c_void_p(), C.c_int()
egl.eglChooseConfig(dpy, (C.c_int * 5)(0x3040, 4, 0x3033, 0, 0x3038), C.byref(cfg), 1, C.byref(n))
ctx = egl.eglCreateContext(dpy, cfg, None, (C.c_int * 3)(0x3098, 2, 0x3038))
if not ctx or not egl.eglMakeCurrent(dpy, None, None, C.c_void_p(ctx)):
    die("context")
ren = gles.glGetString(0x1F01).decode()
print("GL_RENDERER", ren)

VS = b"attribute vec2 p; varying vec2 uv; void main(){ uv = p; gl_Position = vec4(p, 0.0, 1.0); }"
FS = b"""precision highp float; varying vec2 uv; uniform float t; uniform vec2 asp;
void main(){
  float z = 1.6 * exp(-0.18 * t);
  vec2 c = vec2(-0.743643887, 0.131825904) + uv * asp * z;
  vec2 q = vec2(0.0); float i = 0.0;
  for (int k = 0; k < 160; k++) { q = vec2(q.x*q.x - q.y*q.y, 2.0*q.x*q.y) + c; if (dot(q,q) > 16.0) break; i += 1.0; }
  float s = i / 160.0;
  vec3 col = 0.5 + 0.5 * cos(6.2831 * (s * 3.0 + vec3(0.0, 0.33, 0.67) + 0.05 * t));
  if (i >= 159.0) col = vec3(0.0);
  gl_FragColor = vec4(col, 1.0);
}"""


def shader(kind, src):
    s = gles.glCreateShader(kind)
    gles.glShaderSource(s, 1, C.byref(C.c_char_p(src)), None)
    gles.glCompileShader(s)
    ok = C.c_int()
    gles.glGetShaderiv(s, 0x8B81, C.byref(ok))
    if not ok.value:
        log = C.create_string_buffer(2000)
        gles.glGetShaderInfoLog(s, 2000, None, log)
        die("shader: " + log.value.decode())
    return s


prog = gles.glCreateProgram()
gles.glAttachShader(prog, shader(0x8B31, VS))
gles.glAttachShader(prog, shader(0x8B30, FS))
gles.glBindAttribLocation(prog, 0, b"p")
gles.glLinkProgram(prog)
gles.glUseProgram(prog)
quad = (C.c_float * 8)(-1, -1, 1, -1, -1, 1, 1, 1)
gles.glVertexAttribPointer(0, 2, 0x1406, 0, 0, quad)
gles.glEnableVertexAttribArray(0)
ut, ua = gles.glGetUniformLocation(prog, b"t"), gles.glGetUniformLocation(prog, b"asp")
gles.glUniform2f(ua, C.c_float(w / h), C.c_float(1.0))

tex, fbo = C.c_uint(), C.c_uint()
gles.glGenTextures(1, C.byref(tex))
gles.glBindTexture(0x0DE1, tex)
gles.glTexImage2D(0x0DE1, 0, 0x1908, w, h, 0, 0x1908, 0x1401, None)
gles.glGenFramebuffers(1, C.byref(fbo))
gles.glBindFramebuffer(0x8D40, fbo)
gles.glFramebufferTexture2D(0x8D40, 0x8CE0, 0x0DE1, tex, 0)
if gles.glCheckFramebufferStatus(0x8D40) != 0x8CD5:
    die("fbo")
gles.glViewport(0, 0, w, h)

px = (C.c_ubyte * (w * h * 4))()
fb = open("/dev/fb0", "r+b", buffering=0)
start, frames, gpu_t = time.time(), 0, 0.0
while time.time() - start < secs:
    t0 = time.time()
    gles.glUniform1f(ut, C.c_float(time.time() - start))
    gles.glDrawArrays(5, 0, 4)
    gles.glFinish()
    gpu_t += time.time() - t0
    gles.glReadPixels(0, 0, w, h, 0x1908, 0x1401, px)
    rgba = bytes(px)
    out = bytearray(stride * h)
    if bpp == 24:
        row = bytearray(w * 3)
        for y in range(h):	# GL rows go bottom-up; fb is B,G,R in memory
            src = rgba[(h - 1 - y) * w * 4:(h - y) * w * 4]
            row[0::3], row[1::3], row[2::3] = src[2::4], src[1::4], src[0::4]
            out[y * stride:y * stride + w * 3] = row
    else:
        for y in range(h):
            src = bytearray(rgba[(h - 1 - y) * w * 4:(h - y) * w * 4])
            src[0::4], src[2::4] = src[2::4], src[0::4]
            out[y * stride:y * stride + w * 4] = src
    fb.seek(0)
    fb.write(out)
    frames += 1
    print(f"frame {frames}: GPU {1000 * (time.time() - t0):.0f} ms total", flush=True)
print(f"{frames} frames in {time.time() - start:.1f} s, GPU time {1000 * gpu_t / max(frames, 1):.0f} ms/frame on {ren}")
