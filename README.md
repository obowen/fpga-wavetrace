# FPGA Wavetrace

*This is not an officially supported Google product*

Wavetrace is a platform independent real time FPGA debug tool. It acts as an
internal logic analyzer, allowing one to capture cycle-by-cycle data from
internal FPGA nets and registers and display these as a waveform.

This Git repository includes the following:

* Wavetrace Setup Tool: A Python tool that parses and modifies Verilog source
  code to connect the specified debug nets to the Wavetrace Debug Core.
* Wavetrace Capture Tool: A Python tool to configure the Wavetrace debug core,
  collect captured data, and display it in a waveform.
* Wavetrace Debug Core: A Verilog core that implements trigger logic and capture
  buffers to collect data from the debug nets.
* A basic library of Verilog building blocks that are leveraged by Wavetrace
  Debug Core

For additional details, please see wavetrace_user_manual.pdf
