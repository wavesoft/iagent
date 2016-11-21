#
# Configuration parameters for CernVM Image Builder
#

# The directory where the recipe scripts reside
DIR_RECIPES="/usr/share/cernvm-builder/recipes"

# Where the common recipe scripts reside
DIR_SCRIPTS="/usr/share/cernvm-builder/scripts"

# The directory to use as fakeroot (Each build creates a sub-folder)
DIR_FAKEROOT="/fakeroot"

# Where to store the logfiles
DIR_LOGS="/var/log/ibuilder"

# Where is the working folder 
# (Where disk images are going to be placed)
DIR_TMP="/tmp"

# The name of the directories (in absolute path inside the fake root)
# that will be bind-mounted in order to expose the job and log folders
DIR_FAKEROOT_RECIPE="/tmp/build-recipe"
DIR_FAKEROOT_LOGS="/tmp/build-logs"

# *** FOR TEST - ONLY LOCAL ***
DIR_RECIPES="/Users/icharala/Develop/iAgentSVN/trunk/modules/cernvm-builder/package/usr/share/cernvm-builder/recipes"
DIR_SCRIPTS="/Users/icharala/Develop/iAgentSVN/trunk/modules/cernvm-builder/package/usr/share/cernvm-builder/scripts"
DIR_LOGS="/Users/icharala/Develop/iAgentSVN/trunk/modules/cernvm-builder/package/tmp/logs"
DIR_TMP="/Users/icharala/Develop/iAgentSVN/trunk/modules/cernvm-builder/package/tmp/tmp"
