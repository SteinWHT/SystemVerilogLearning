# .bashrc
# Source global definitions
if [ -f /etc/bashrc ]; then
. /etc/bashrc
fi

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
alias g="gvim"

### Synopsys Environment Variables
# License configuration
#export SNPSLMD_LICENSE_FILE=27000@localhost.localdomain
#export LM_LICENSE_FILE=/usr/Synopsys/scl/2021.03/admin/license/Synopsys.dat
export SYNOPSYS_LICENSE_FILE=/home/synopsys/scl/2024.06/admin/license/synopsys.lic
export LM_LICENSE_FILE=27000@127.0.0.1:$SYNOPSYS_LICENSE_FILE
export SNPSLMD_LICENSE_FILE=27000@127.0.0.1:$SYNOPSYS_LICENSE_FILE

#alias ins='/usr/Synopsys/installer/setup.sh'

# VCS
export VCS_HOME=/home/synopsys/vcs/W-2024.09-SP1
export PATH=$PATH:$VCS_HOME/bin

# Verdi
export VERDI_HOME=/home/synopsys/verdi/W-2024.09-SP1
export LD_LIBRARY_PATH=$VERDI_HOME/share/PLI/VCS/LINUX64
export PATH=$PATH:$VERDI_HOME/bin

# SCL
export SCL_HOME=/home/synopsys/scl/2024.06
export PATH=$PATH:$SCL_HOME/linux64/bin
export VCS_ARCH_OVERRIDE=linux

# Design Compiler (DC) / Syn
export DC_HOME=/home/synopsys/syn/V-2023.12-SP3
export PATH=$PATH:$DC_HOME/bin

## Below are parts of the software not currently installed or not updated
## Spyglass
# export SPYGLASS_HOME=/home/synopsys/spyglass/T-2022.06-1/SPYGLASS_HOME
# export PATH=$PATH:$SPYGLASS_HOME/bin
# export SPYGLASS_DC_PATH=$DC_HOME

# coretools
# export PATH="/home/synopsys/coretools/T-2022.06/bin":$PATH
# alias ct="coreConsultant"
# export DESIGNWARE_HOME=/home/autumn/Desktop/IP

# Formality (fm)
# export FM_HOME=/home/synopsys/fm/T-2022.03
# export PATH=$PATH:$FM_HOME/bin

# PrimeTime (pt)
# export PT_HOME=/home/synopsys/prime/T-2022.03
# export PATH=$PATH:$PT_HOME/bin

# ICC2
# export ICC2_HOME=/home/synopsys/icc2/T-2022.03
# export PATH=$PATH:$ICC2_HOME/bin

# ICC
# export ICC_HOME=/home/synopsys/icc/T-2022.03
# export PATH=$PATH:$ICC_HOME/bin

# DFT shell
# export TESTMAX_MAX=/home/synopsys/testmax/S-2021.06-SP5
# export PATH=$PATH:$TESTMAX_MAX/bin

# TXS
# export TXS_HOME=/home/synopsys/txs/R-2020.09-SP3
# export PATH=$PATH:$TXS_HOME/bin
# alias tmax='/home/synopsys/txs/R-2020.09-SP3/bin/tmax'

# StarRC
# export STARRC_HOME=/home/synopsys/starrc/T-2022.03-SP2
# export PATH=$PATH:$STARRC_HOME/bin

# Library Compiler (lc_shell) - required to compile .lib -> .db
export LC_HOME=/home/synopsys/lc/V-2023.12-SP3
export PATH=$PATH:$LC_HOME/bin

# embedit
# export EMBEDIT_HOME=/home/synopsys/embedit/U-2022.12
# export PATH=$PATH:$EMBEDIT_HOME/bin

# VC static
# export VC_STATIC_HOME=/home/synopsys/vc_static/T-2022.06-SP2
# export PATH=$PATH:$VC_STATIC_HOME/bin

# License manager alias
alias lmg="/home/synopsys/scl/2024.06/linux64/bin/lmgrd -c $SYNOPSYS_LICENSE_FILE -l /tmp/synopsys_lmgrd.log"
