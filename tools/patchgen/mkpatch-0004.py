#!/usr/bin/env python3
"""msm: identity IOVA (IOVA == physical address) for every GEM object, behind
msm.identity_iova=1. Bring-up hack for MSM8994, whose MDP/DSI traffic bypasses
the TZ-owned SMMU. Usage: mkpatch-0004.py <kernel-src>"""
import sys
D = sys.argv[1].rstrip('/') + '/drivers/gpu/drm/msm/'
def ed(f, a, b):
    p = D + f; s = open(p).read()
    assert s.count(a) == 1, (f, a[:50]); open(p, 'w').write(s.replace(a, b))

ed('msm_gem.h', '''struct msm_gem_object {
	struct drm_gem_object base;

	uint32_t flags;
''', '''struct msm_gem_object {
	struct drm_gem_object base;

	uint32_t flags;

	/* msm.identity_iova: physically contiguous backing (CMA), IOVA == PA */
	struct page *contig;
''')

ed('msm_gem.c', '#include "msm_kms.h"\n', '''#include "msm_kms.h"

/*
 * Bring-up (MSM8994): the MDP and the DSI command DMA bypass the SMMU, which
 * TrustZone owns, and use IOVAs as physical addresses. With identity_iova every
 * GEM object is physically contiguous (CMA) and mapped at IOVA == PA, so the
 * hardware reads the right memory either way.
 */
static bool identity_iova;
module_param(identity_iova, bool, 0444);
MODULE_PARM_DESC(identity_iova, "Contiguous buffers mapped at IOVA == physical address");
''')

ed('msm_gem.c', '''		size_t npages = obj->size >> PAGE_SHIFT;

		p = drm_gem_get_pages(obj);
''', '''		size_t npages = obj->size >> PAGE_SHIFT;

		if (identity_iova) {
			struct page *pg = dma_alloc_contiguous(dev->dev, obj->size, GFP_KERNEL);
			size_t i;

			/* CMA declines single pages: the buddy allocator then */
			if (!pg)
				pg = alloc_pages(GFP_KERNEL | __GFP_ZERO, get_order(obj->size));
			if (!pg)
				return ERR_PTR(-ENOMEM);
			p = kvmalloc_array(npages, sizeof(*p), GFP_KERNEL);
			if (!p) {
				dma_free_contiguous(dev->dev, pg, obj->size);
				return ERR_PTR(-ENOMEM);
			}
			for (i = 0; i < npages; i++)
				p[i] = pg + i;
			msm_obj->contig = pg;
		} else
			p = drm_gem_get_pages(obj);
''')

ed('msm_gem.c', '''		drm_gem_put_pages(obj, msm_obj->pages, true, false);
''', '''		if (msm_obj->contig) {
			dma_free_contiguous(obj->dev->dev, msm_obj->contig, obj->size);
			msm_obj->contig = NULL;
			kvfree(msm_obj->pages);
		} else
			drm_gem_put_pages(obj, msm_obj->pages, true, false);
''')

ed('msm_gem.c', '''	if (to_msm_bo(obj)->flags & MSM_BO_NO_SHARE)
		return -EINVAL;

	vma = get_vma_locked(obj, vm, range_start, range_end);''', '''	if (to_msm_bo(obj)->flags & MSM_BO_NO_SHARE)
		return -EINVAL;

	if (identity_iova) {
		struct page **pages = get_pages(obj);

		if (IS_ERR(pages))
			return PTR_ERR(pages);
		if (to_msm_bo(obj)->contig) {
			range_start = page_to_phys(to_msm_bo(obj)->contig);
			range_end = range_start + obj->size;
		}
	}

	vma = get_vma_locked(obj, vm, range_start, range_end);''')
