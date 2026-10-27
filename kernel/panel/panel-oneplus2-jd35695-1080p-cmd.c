// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 FIXME
// Generated with linux-mdss-dsi-panel-driver-generator from vendor device tree:
//   Copyright (c) 2013, The Linux Foundation. All rights reserved. (FIXME)

#include <linux/delay.h>
#include <linux/device-id/of.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>

#include <video/mipi_display.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_probe_helper.h>

struct jd35695 {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct gpio_desc *reset_gpio;
};

static inline struct jd35695 *to_jd35695(struct drm_panel *panel)
{
	return container_of_const(panel, struct jd35695, panel);
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
	mipi_dsi_dcs_set_display_brightness_multi(&dsi_ctx, 0x00ff);
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

	jd35695_reset(ctx);

	ret = jd35695_on(ctx);
	if (ret < 0) {
		dev_err(dev, "Failed to initialize panel: %d\n", ret);
		gpiod_set_value_cansleep(ctx->reset_gpio, 1);
		return ret;
	}

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

	gpiod_set_value_cansleep(ctx->reset_gpio, 1);

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

static int jd35695_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct jd35695 *ctx;
	int ret;

	ctx = devm_drm_panel_alloc(dev, struct jd35695, panel,
				   &jd35695_panel_funcs,
				   DRM_MODE_CONNECTOR_DSI);
	if (IS_ERR(ctx))
		return PTR_ERR(ctx);

	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "Failed to get reset-gpios\n");

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	dsi->lanes = 4;
	dsi->format = MIPI_DSI_FMT_RGB888;
	dsi->mode_flags = MIPI_DSI_MODE_VIDEO_BURST | MIPI_DSI_MODE_VIDEO_HSE |
			  MIPI_DSI_MODE_NO_EOT_PACKET |
			  MIPI_DSI_CLOCK_NON_CONTINUOUS;

	ctx->panel.prepare_prev_first = true;

	ret = drm_panel_of_backlight(&ctx->panel);
	if (ret)
		return dev_err_probe(dev, ret, "Failed to get backlight\n");

	ret = devm_drm_panel_add(dev, &ctx->panel);
	if (ret)
		return ret;

	return devm_mipi_dsi_attach(dev, dsi);
}

static const struct of_device_id jd35695_of_match[] = {
	{ .compatible = "mdss,jd35695" }, // FIXME
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
MODULE_DESCRIPTION("DRM driver for jd35695 1080p cmd mode dsi panel");
MODULE_LICENSE("GPL");
