/*
 * gpu-steps: exercise the GPU through Mesa one step at a time, to find
 * which step resets the phone. EGL on the surfaceless platform (no display,
 * no compositor), GLES2, rendering into a texture FBO.
 *   gpu-steps <1..5>   runs steps 1..N, printing (and syncing) each one
 * 1 eglGetPlatformDisplay + eglInitialize   2 context + make current
 * 3 FBO + glClear + glFinish                4 glReadPixels
 * 5 one triangle with a trivial shader + glFinish
 * Build on the phone: cc -O2 -o gpu-steps gpu-steps.c -lEGL -lGLESv2
 */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void step(int n, const char *what)
{
	printf("step %d: %s\n", n, what);
	fflush(stdout);
	sync();
	usleep(300000);
}

int main(int argc, char **argv)
{
	int last = argc > 1 ? atoi(argv[1]) : 5;
	PFNEGLGETPLATFORMDISPLAYEXTPROC gpd =
		(void *)eglGetProcAddress("eglGetPlatformDisplayEXT");

	step(1, "eglInitialize (surfaceless)");
	EGLDisplay dpy = gpd(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
	EGLint maj, min;
	if (!eglInitialize(dpy, &maj, &min)) { printf("eglInitialize failed\n"); return 1; }
	printf("  EGL %d.%d %s\n", maj, min, eglQueryString(dpy, EGL_VENDOR));
	if (last < 2) return 0;

	step(2, "context");
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint ca[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ca);
	if (!ctx || !eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
		printf("context failed 0x%x\n", eglGetError()); return 1;
	}
	printf("  GL_RENDERER %s\n  GL_VERSION %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
	if (last < 3) return 0;

	step(3, "FBO 256x256 + glClear + glFinish");
	GLuint tex, fbo;
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
	printf("  fbo status 0x%x\n", glCheckFramebufferStatus(GL_FRAMEBUFFER));
	glClearColor(1, 0, 0, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	glFinish();
	printf("  clear done, glGetError 0x%x\n", glGetError());
	if (last < 4) return 0;

	step(4, "glReadPixels");
	unsigned char px[4] = { 0 };
	glReadPixels(10, 10, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	printf("  pixel %02x %02x %02x %02x (expect ff 00 00 ff)\n", px[0], px[1], px[2], px[3]);
	if (last < 5) return 0;

	step(5, "triangle");
	const char *vs = "attribute vec2 p; void main(){gl_Position=vec4(p,0.0,1.0);}";
	const char *fs = "precision mediump float; void main(){gl_FragColor=vec4(0.0,1.0,0.0,1.0);}";
	GLuint v = glCreateShader(GL_VERTEX_SHADER), f = glCreateShader(GL_FRAGMENT_SHADER), pr = glCreateProgram();
	glShaderSource(v, 1, &vs, NULL); glCompileShader(v);
	glShaderSource(f, 1, &fs, NULL); glCompileShader(f);
	glAttachShader(pr, v); glAttachShader(pr, f);
	glBindAttribLocation(pr, 0, "p");
	glLinkProgram(pr);
	glUseProgram(pr);
	static const float tri[] = { -1, -1, 1, -1, 0, 1 };
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, tri);
	glEnableVertexAttribArray(0);
	glViewport(0, 0, 256, 256);
	glDrawArrays(GL_TRIANGLES, 0, 3);
	glFinish();
	glReadPixels(128, 100, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
	printf("  pixel %02x %02x %02x %02x (expect 00 ff 00 ff)\n", px[0], px[1], px[2], px[3]);
	printf("all steps done\n");
	return 0;
}
