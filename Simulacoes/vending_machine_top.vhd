#!/bin/bash -f
xv_path="/opt/Xilinx/Vivado/2017.2"
ExecStep()
{
"$@"
RETVAL=$?
if [ $RETVAL -ne 0 ]
then
exit $RETVAL
fi
}
ExecStep $xv_path/bin/xelab -wto c14e09ed9cb84de5a11fe2926d9bcf63 -m64 --debug typical --relax --mt 8 -L xil_defaultlib -L secureip --snapshot tb_vending_machine_top_behav xil_defaultlib.tb_vending_machine_top -log elaborate.log
