// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 FIXME
// Generated with linux-mdss-dsi-panel-driver-generator from vendor device tree:
//   Copyright (c) 2013, The Linux Foundation. All rights reserved. (FIXME)

#include <linux/delay.h>
#if __has_include(<linux/device-id/of.h>)
#include <linux/device-id/of.h>	/* 7.x */
#else
#include <linux/mod_devicetable.h>	/* 6.12 */
#endif
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/version.h>

#include <video/mipi_display.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_probe_helper.h>

struct jd35695 {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct gpio_desc *reset_gpio;
	/* TPS65132 bias: +5 V enable (PMI8994 GPIO 7), -5 V enable (GPIO 3) */
	struct gpio_desc *vsp_gpio, *vsn_gpio;
	/* in-cell touch reset (GPIO 31): pulsed after the panel is on */
	struct gpio_desc *ts_reset_gpio;
};

/*
 * OnePlus power-down (vendor_lcd_power_on(0) + mdss_dsi_panel_reset(0)):
 * reset asserted, -5 V off, 5 ms, +5 V off.
 */
static void jd35695_power_off(struct jd35695 *ctx)
{
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	gpiod_set_value_cansleep(ctx->vsn_gpio, 0);
	usleep_range(5000, 6000);
	gpiod_set_value_cansleep(ctx->vsp_gpio, 0);
	usleep_range(5000, 6000);
}

/* OnePlus power-up: +5 V on, 2 ms, -5 V on (the reset sequence follows) */
static void jd35695_power_on(struct jd35695 *ctx)
{
	gpiod_set_value_cansleep(ctx->vsp_gpio, 1);
	usleep_range(2000, 3000);
	gpiod_set_value_cansleep(ctx->vsn_gpio, 1);
}

/* the in-cell touch controller must be reset once the panel is up */
static void jd35695_touch_reset(struct jd35695 *ctx)
{
	if (!ctx->ts_reset_gpio)
		return;
	gpiod_set_value_cansleep(ctx->ts_reset_gpio, 1);
	usleep_range(5000, 6000);
	gpiod_set_value_cansleep(ctx->ts_reset_gpio, 0);
}

static inline struct jd35695 *to_jd35695(struct drm_panel *panel)
{
	return container_of_const(panel, struct jd35695, panel);
}

/* bring-up: keep the panel exactly as the bootloader left it (no reset, no init) */
static bool keep;
module_param(keep, bool, 0444);
MODULE_PARM_DESC(keep, "Keep the bootloader's panel state (no reset, no init sequence)");

static void jd35695_report(struct jd35695 *ctx, const char *when)
{
	struct device *dev = &ctx->dsi->dev;
	u8 mode = 0, id[3] = { 0 };
	int r1, r2, r3, r4;

	ctx->dsi->mode_flags |= MIPI_DSI_MODE_LPM;
	r1 = mipi_dsi_dcs_get_power_mode(ctx->dsi, &mode);
	r2 = mipi_dsi_dcs_read(ctx->dsi, 0xda, &id[0], 1);
	r3 = mipi_dsi_dcs_read(ctx->dsi, 0xdb, &id[1], 1);
	r4 = mipi_dsi_dcs_read(ctx->dsi, 0xdc, &id[2], 1);
	ctx->dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;
	dev_info(dev, "%s: power mode 0x%02x (%d), id %02x %02x %02x (%d %d %d)\n",
		 when, mode, r1, id[0], id[1], id[2], r2, r3, r4);
}

static void jd35695_reset(struct jd35695 *ctx)
{
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(11000, 12000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 1);
	usleep_range(2000, 3000);
	gpiod_set_value_cansleep(ctx->reset_gpio, 0);
	usleep_range(12000, 13000);
}

static int jd35695_on(struct jd35695 *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	ctx->dsi->mode_flags |= MIPI_DSI_MODE_LPM;

	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	mipi_dsi_dcs_set_tear_on_multi(&dsi_ctx, MIPI_DSI_DCS_TEAR_MODE_VBLANK);
	mipi_dsi_dcs_set_column_address_multi(&dsi_ctx, 0x0000, 0x0437);
	mipi_dsi_dcs_set_page_address_multi(&dsi_ctx, 0x0000, 0x077f);
	mipi_dsi_generic_write_seq_multi(&dsi_ctx, 0x44, 0x05, 0x00);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0xe0);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xb5, 0x86);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xb6, 0x77);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xb8, 0xad);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_ADDRESS_MODE, 0x03);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x23);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x08, 0x03);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	/*
	 * One byte, as the OnePlus sequence sends it. The 16-bit helper
	 * (mipi_dsi_dcs_set_display_brightness) sends "ff 00" and this panel
	 * takes that as brightness 0: backlight on, picture black.
	 */
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_SET_DISPLAY_BRIGHTNESS, 0xff);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_CONTROL_DISPLAY,
				     0x2c);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_POWER_SAVE, 0x02);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x23);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xfb, 0x01);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x05, 0x24);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0x01, 0x84);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	mipi_dsi_dcs_exit_sleep_mode_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 100);
	mipi_dsi_dcs_set_display_on_multi(&dsi_ctx);
	mipi_dsi_usleep_range(&dsi_ctx, 17000, 18000);

	return dsi_ctx.accum_err;
}

static int jd35695_off(struct jd35695 *ctx)
{
	struct mipi_dsi_multi_context dsi_ctx = { .dsi = ctx->dsi };

	ctx->dsi->mode_flags &= ~MIPI_DSI_MODE_LPM;

	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, 0xff, 0x10);
	mipi_dsi_dcs_write_seq_multi(&dsi_ctx, MIPI_DCS_WRITE_CONTROL_DISPLAY,
				     0x00);
	mipi_dsi_dcs_set_display_off_multi(&dsi_ctx);
	mipi_dsi_usleep_range(&dsi_ctx, 17000, 18000);
	mipi_dsi_dcs_enter_sleep_mode_multi(&dsi_ctx);
	mipi_dsi_msleep(&dsi_ctx, 50);

	return dsi_ctx.accum_err;
}

static int jd35695_prepare(struct drm_panel *panel)
{
	struct jd35695 *ctx = to_jd35695(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	if (keep) {
		dev_info(dev, "keeping the bootloader's panel state\n");
		gpiod_set_value_cansleep(ctx->reset_gpio, 0);
		jd35695_report(ctx, "kept");
		return 0;
	}

	/*
	 * The bootloader left the panel on: take it down the OnePlus way
	 * first. A reset with the +-5 V bias still up leaves it dark.
	 */
	jd35695_off(ctx);
	jd35695_power_off(ctx);
	msleep(100);
	jd35695_power_on(ctx);
	jd35695_reset(ctx);
	/* in-cell touch: reset it together with the panel, before the init */
	jd35695_touch_reset(ctx);

	ret = jd35695_on(ctx);
	if (ret < 0) {
		dev_err(dev, "Failed to initialize panel: %d\n", ret);
		jd35695_power_off(ctx);
		return ret;
	}

	jd35695_report(ctx, "after init");
	return 0;
}

static int jd35695_unprepare(struct drm_panel *panel)
{
	struct jd35695 *ctx = to_jd35695(panel);
	struct device *dev = &ctx->dsi->dev;
	int ret;

	ret = jd35695_off(ctx);
	if (ret < 0)
		dev_err(dev, "Failed to un-initialize panel: %d\n", ret);

	jd35695_power_off(ctx);

	return 0;
}

static const struct drm_display_mode jd35695_mode = {
	.clock = (1080 + 100 + 8 + 82) * (1920 + 3 + 2 + 7) * 60 / 1000,
	.hdisplay = 1080,
	.hsync_start = 1080 + 100,
	.hsync_end = 1080 + 100 + 8,
	.htotal = 1080 + 100 + 8 + 82,
	.vdisplay = 1920,
	.vsync_start = 1920 + 3,
	.vsync_end = 1920 + 3 + 2,
	.vtotal = 1920 + 3 + 2 + 7,
	.width_mm = 70,
	.height_mm = 127,
	.type = DRM_MODE_TYPE_DRIVER,
};

static int jd35695_get_modes(struct drm_panel *panel,
			     struct drm_connector *connector)
{
	return drm_connector_helper_get_modes_fixed(connector, &jd35695_mode);
}

static const struct drm_panel_funcs jd35695_panel_funcs = {
	.prepare = jd35695_prepare,
	.unprepare = jd35695_unprepare,
	.get_modes = jd35695_get_modes,
};

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0)
static void jd35695_panel_remove(void *panel)
{
	drm_panel_remove(panel);
}
#endif

static int jd35695_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct jd35695 *ctx;
	int ret;

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
	ctx = devm_drm_panel_alloc(dev, struct jd35695, panel,
				   &jd35695_panel_funcs,
				   DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);
#else	/* 6.12 (GPU with a VRAM carveout) */
	ctx = devm_kzalloc(dev, sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;
	drm_panel_init(&ctx->panel, dev, &jd35695_panel_funcs, DRM_MODE_CONNECTOR_DSI);
#endif

	/* all requested in the state the bootloader leaves them: no glitch */
	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "Failed to get reset-gpios\n");

	ctx->vsp_gpio = devm_gpiod_get_optional(dev, "vsp", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->vsp_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->vsp_gpio), "Failed to get vsp-gpios\n");
	ctx->vsn_gpio = devm_gpiod_get_optional(dev, "vsn", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->vsn_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->vsn_gpio), "Failed to get vsn-gpios\n");
	ctx->ts_reset_gpio = devm_gpiod_get_optional(dev, "touch-reset", GPIOD_OUT_LOW);
	if (IS_ERR(ctx->ts_reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->ts_reset_gpio), "Failed to get touch-reset-gpios\n");

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	/* as the bootloader runs it: EOT packets on (EOT_PACKET_CTRL = 1) */
	dsi->mode_flags = MIPI_DSI_MODE_VIDEO_BURST | MIPI_DSI_MODE_VIDEO_HSE |
			  MIPI_DSI_CLOCK_NON_CONTINUOUS;

	ctx->panel.prepare_prev_first = true;

	ret = drm_panel_of_backlight(&ctx->panel);
	if (ret)
		return dev_err_probe(dev, ret, "Failed to get backlight\n");

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
	ret = devm_drm_panel_add(dev, &ctx->panel);
	if (ret)
		return ret;
#else
	drm_panel_add(&ctx->panel);
	ret = devm_add_action_or_reset(dev, jd35695_panel_remove, &ctx->panel);
	if (ret)
		return ret;
#endif

	return devm_mipi_dsi_attach(dev, dsi);
}

static const struct of_device_id jd35695_of_match[] = {
	{ .compatible = "oneplus,oneplus2-jd35695" }, // FIXME
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, jd35695_of_match);

static struct mipi_dsi_driver jd35695_driver = {
	.probe = jd35695_probe,
	.driver = {
		.name = "panel-jd35695",
		.of_match_table = jd35695_of_match,
	},
};
module_mipi_dsi_driver(jd35695_driver);

MODULE_AUTHOR("linux-mdss-dsi-panel-driver-generator <fix@me>"); // FIXME
MODULE_DESCRIPTION("OnePlus 2 JD35695 1080p command mode DSI panel");
MODULE_LICENSE("GPL");
