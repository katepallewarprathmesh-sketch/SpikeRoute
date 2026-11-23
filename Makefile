PROJECT := SpikeRoute
.PHONY: test smoke router-test mesh-test lint formal cdg results clean

test: smoke formal
smoke: router-test mesh-test cdg

router-test:
	$(MAKE) -C tb_cocotb clean
	$(MAKE) -C tb_cocotb TOPLEVEL=router MODULE=test_router

mesh-test:
	$(MAKE) -C tb_cocotb clean
	$(MAKE) -C tb_cocotb TOPLEVEL=mesh_2x2 MODULE=test_mesh

lint:
	verilator --lint-only -Wall --top-module mesh_2x2 rtl/router.sv rtl/mesh_2x2.sv

formal:
	cd formal && sby -f router.sby
	cp formal/router/engine_0/logfile_basecase.txt results/formal_basecase.log
	cp formal/router/engine_0/logfile_induction.txt results/formal_induction.log
	printf 'PASS: reduced single-router FIFO/credit bounds and atomic grant consistency; k-induction, depth 6. Not a proof of exact packet conservation, RR fairness, or mesh deadlock freedom.\n' > results/formal_summary.txt

cdg:
	python3 scripts/cdg_check.py

results: mesh-test
	python3 scripts/run_results.py

clean:
	$(MAKE) -C tb_cocotb clean
	rm -rf formal/router formal/router_bmc
	rm -f tb_cocotb/results.xml
