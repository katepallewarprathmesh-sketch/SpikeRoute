# cocotb Makefile for SpikeRoute (Verilator backend)
SIM = verilator
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(PWD)/../rtl/router.sv $(PWD)/../rtl/mesh_2x2.sv
TOPLEVEL = router
MODULE = test_router
COMPILE_ARGS += -Wno-WIDTHEXPAND -Wno-UNOPTFLAT
include $(shell cocotb-config --makefiles)/Makefile.sim
