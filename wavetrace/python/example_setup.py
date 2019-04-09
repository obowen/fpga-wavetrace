# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
import wt_libero
from wt_setup import WTSetup

wt = WTSetup(clock_freq=80.0)

wt.add_sources("../libero/starter_wavetrace2/component/work/raygun");
wt.add_sources("../../src/raygun/hdl/lfsr");

wt.top("raygun");

wt.clk("DATA_CLK_2")
wt.rst("rst_sync_0_rst_1")

wt.net("lfsr_source_0.tx_count[11:0]");
wt.net("lfsr_sink_0.rx_count[11:0]");
wt.net("lfsr_sink_0.err_count[7:0]");

wt.generate()

syn_prj_file = "../libero/starter_wavetrace2/synthesis/raygun_syn.prj"
wt_libero.modify_synplify_prj_file(wt.get_change_list(), syn_prj_file)

