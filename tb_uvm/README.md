# Track A UVM porting notes (not executed)

The RTL exposes five input agents, five output monitors, table-load configuration and credit return. A commercial UVM port should add a packet sequence item `{key,payload}`, per-port sequencers/drivers, output scoreboard using the expected multicast mask, and covergroups for route type, fan-out, contention and credit stalls. No UVM package or VCS/Questa run is included here; all current executable verification is Track B cocotb/Verilator.
