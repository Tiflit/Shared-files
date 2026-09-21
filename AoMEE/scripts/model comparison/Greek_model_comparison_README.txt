AoM:EE Greek model comparison

The first-round comparison is deliberately limited to the four established checkpoints:

  HAT:
    D:\AI_upscaling\AoMEE\models\HAT\Real_HAT_GAN_sharper.pth

  SwinIR-M classical SR:
    D:\AI_upscaling\AoMEE\models\SwinIR\001_classicalSR_DF2K_s64w8_SwinIR-M_x4.pth

  DRCT-L:
    D:\AI_upscaling\AoMEE\models\DRCT\DRCT-L_X4.pth

  DAT:
    D:\AI_upscaling\AoMEE\models\DAT\DAT_x4.pth

Use the existing AoMEE ChaiNNer 0.25.1 graph as the processing template.
For each model, change only:
  1. model checkpoint
  2. output directory
  3. output image format to lossless PNG for the initial comparison

Keep the alpha path identical:
  RGB -> AI x4
  Alpha -> nearest neighbour x4
  Merge RGBA

Run:
  prepare_greek_model_comparison.ps1

Then process the same 24 source files into:
  tests\greek_model_comparison\HAT
  tests\greek_model_comparison\SwinIR
  tests\greek_model_comparison\DRCT
  tests\greek_model_comparison\DAT

Finally run:
  verify_greek_model_comparison.ps1

The QA checks:
  - output exists
  - output is exactly 4x in both dimensions
  - output alpha is bit-for-bit identical to nearest-neighbour 4x of the source alpha

No DDT compilation is part of this first comparison.
