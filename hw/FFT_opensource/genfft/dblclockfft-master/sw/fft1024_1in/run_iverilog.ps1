Set-Location $PSScriptRoot

python .\gen_fft_vectors.py --kind random --amplitude 1000 --seed 1 --outdir .

iverilog -g2012 -o tb_fftmain.vvp `
  tb_fftmain.v `
  fftmain.v fftstage.v qtrstage.v laststage.v bitreverse.v `
  butterfly.v hwbfly.v longbimpy.v bimpy.v convround.v

vvp tb_fftmain.vvp
