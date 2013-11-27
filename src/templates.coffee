


### TAINT experimental — do not use yet ###



############################################################################################################
TRM                       = require 'coffeenode-trm'
rpr                       = TRM.rpr.bind TRM
log                       = TRM.log.bind TRM
echo                      = TRM.echo.bind TRM
LANGUAGE                  = require './LANGUAGE'
#...........................................................................................................
### https://github.com/goodeggs/teacup ###
teacup                    = require 'teacup'

#===========================================================================================================
# TEACUP NAMESPACE ACQUISITION
#-----------------------------------------------------------------------------------------------------------
for name_ of teacup
  eval "#{name_.toUpperCase()} = teacup[ #{rpr name_} ]"


#===========================================================================================================
# TEMPLATES
#-----------------------------------------------------------------------------------------------------------
@login_get = RENDERABLE ( O ) ->
  FORM '#cnd-userdb-login-form', method: 'post', =>
    DIV =>
      INPUT name: 'uid', type: 'text'
      INPUT name: 'pwd', type: 'password'
      INPUT type: 'submit'

#-----------------------------------------------------------------------------------------------------------
@login_post = RENDERABLE ( O ) ->


