AoM:EE HAT vs PBRify model comparison
======================================

Input set:
  Exact same 80-texture set used in the previous visual model benchmark.

Selection:
  40 Icon
  25 UI
  10 Portrait/Artwork
   5 Effect/Misc

Input folder:
  original\

Models:
  HAT
    Real_HAT_GAN_sharper.pth

  PBRify_V4
    4x-PBRify_UpscalerV4.pth

  PBRify_RPLKSRd_V3
    4x-PBRify_RPLKSRd_V3.pth

Recommended processing pipeline for each model:
  RGB -> AI x4
  Alpha -> nearest-neighbour x4
  Merge RGBA
  Save lossless TGA/PNG for comparison

Do not modify the clean source/game tree.
Do not send alpha through the AI model.

The purpose of this folder is controlled side-by-side model comparison.
