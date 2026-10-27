#!/usr/bin/env python3
"""Apply the 20nm-PHY 'keep the bootloader PLL' edits to a pristine 7.3 tree.
Usage: mkpatch-0003.py <kernel-src>"""
import sys
D = sys.argv[1].rstrip('/') + '/drivers/gpu/drm/msm/dsi/'
def ed(f, a, b):
    p = D + f; s = open(p).read()
    assert s.count(a) == 1, (f, a[:40]); open(p, 'w').write(s.replace(a, b))
ed('phy/dsi_phy.h', '\tbool pll_on;\n',
   '\tbool pll_on;\n\t/* bring-up: PHY + PLL left running by the bootloader, keep them */\n\tbool bootloader_kept;\n')
ed('phy/dsi_phy.c', 'void msm_dsi_phy_disable(struct msm_dsi_phy *phy)\n',
   'bool msm_dsi_phy_bootloader_kept(struct msm_dsi_phy *phy)\n{\n\treturn phy && phy->bootloader_kept;\n}\n\nvoid msm_dsi_phy_disable(struct msm_dsi_phy *phy)\n')
ed('dsi.h', 'void msm_dsi_phy_disable(struct msm_dsi_phy *phy);\n',
   'void msm_dsi_phy_disable(struct msm_dsi_phy *phy);\nbool msm_dsi_phy_bootloader_kept(struct msm_dsi_phy *phy);\n')
ed('dsi_manager.c', '''	} else {
		msm_dsi_host_reset_phy(msm_dsi->host);''', '''	} else {
		/* a reset would drop the bootloader's PLL, which has no driver */
		if (!msm_dsi_phy_bootloader_kept(msm_dsi->phy))
			msm_dsi_host_reset_phy(msm_dsi->host);''')
ed('phy/dsi_phy_20nm.c', '''		return -EINVAL;
	}

	dsi_20nm_phy_regulator_ctrl(phy, true);''', '''		return -EINVAL;
	}

	/*
	 * Keep the bootloader's PHY registers. The host still programs the
	 * clock lane pre/post times (CLKOUT_TIMING_CTRL) from this timing: use
	 * the bootloader's/panel's values (0x3e/0x20 on the OnePlus 2), not the
	 * computed ones, so they match the PHY setup that is kept.
	 */
	if (phy->bootloader_kept) {
		timing->shared_timings.clk_pre = 0x3e;
		timing->shared_timings.clk_post = 0x20;
		timing->shared_timings.clk_pre_inc_by_2 = false;
		return 0;
	}

	dsi_20nm_phy_regulator_ctrl(phy, true);''')
ed('phy/dsi_phy_20nm.c', '''static void dsi_20nm_phy_disable(struct msm_dsi_phy *phy)
{
''', '''static void dsi_20nm_phy_disable(struct msm_dsi_phy *phy)
{
	if (phy->bootloader_kept)
		return;
''')
ed('phy/dsi_phy_20nm.c', 'static const struct regulator_bulk_data dsi_phy_20nm_regulators[] = {', '''/*
 * There is no 20nm DSI PLL driver: the PLL is the bootloader's, powered
 * through this PHY's regulator. If the bootloader left the PHY enabled
 * (CTRL_0 = 0x7f), keep PHY and PLL exactly as they are.
 */
static int dsi_20nm_phy_check_bootloader(struct msm_dsi_phy *phy)
{
	if (readl(phy->base + REG_DSI_20nm_PHY_CTRL_0) == 0x7f) {
		phy->bootloader_kept = true;
		DRM_DEV_INFO(&phy->pdev->dev,
			     "keeping the bootloader's PHY and PLL setup\\n");
	}
	return 0;
}

static const struct regulator_bulk_data dsi_phy_20nm_regulators[] = {''')
ed('phy/dsi_phy_20nm.c', '''		.disable = dsi_20nm_phy_disable,
	},''', '''		.disable = dsi_20nm_phy_disable,
		.parse_dt_properties = dsi_20nm_phy_check_bootloader,
	},''')
