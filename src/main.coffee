

############################################################################################################
# ERROR                     = require 'coffeenode-stacktrace'
njs_util                  = require 'util'
njs_path                  = require 'path'
njs_fs                    = require 'fs'
njs_url                   = require 'url'
#...........................................................................................................
TYPES                     = require 'coffeenode-types'
TRM                       = require 'coffeenode-trm'
rpr                       = TRM.rpr.bind TRM
badge                     = 'USERDB/main'
log                       = TRM.get_logger 'plain',   badge
info                      = TRM.get_logger 'info',    badge
whisper                   = TRM.get_logger 'whisper', badge
alert                     = TRM.get_logger 'alert',   badge
debug                     = TRM.get_logger 'debug',   badge
warn                      = TRM.get_logger 'warn',    badge
help                      = TRM.get_logger 'help',    badge
echo                      = TRM.echo.bind TRM
#...........................................................................................................
mixins = [
  require './core'
  require './users'
  require './passwords'
  require './dump'
  # require './web'
  require './integrity' ]
#...........................................................................................................
USERDB                    = @

#-----------------------------------------------------------------------------------------------------------
# Mix-in
do ->
  for mixin in mixins
    for name, value of mixin
      throw new Error "name clash: #{rpr name}" if USERDB[ name ]?
      USERDB[ name ] = value


