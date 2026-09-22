# Weather FX 8.1.85 Final Qualification

Built directly from exact Weather FX 8.1.84.

## Player-visible addition
**CLOUD BANK STYLE** provides VOLUMETRIC and BLOCKY 3D cloud banks. VOLUMETRIC remains the default. BLOCKY is flat, rectangular, world-space and slightly translucent while retaining the existing cloud simulation and weather relationships.

## Source qualification
- dedicated cloud-bank-style regression: **20/20 PASS**;
- exact 8.1.84 negative control: expected failure (**2 PASS / 17 FAIL**);
- settings runtime: **735/735 PASS**;
- complete descriptions/menu: **1,884/1,884 PASS**;
- runtime consumer audit: **269/269 PASS**;
- maximum-settings profile: **10/10 PASS**;
- full 8.1.85 developer sweep: **85/85 programs PASS**.

Exact-package replay, runtime compilation, source/package comparison, archive integrity and Library verification are recorded in release-side logs after the archive is frozen.
