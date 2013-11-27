

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
badge                     = 'USERDB/users'
log                       = TRM.get_logger 'plain', badge
info                      = TRM.get_logger 'info',  badge
whisper                   = TRM.get_logger 'whisper',  badge
alert                     = TRM.get_logger 'alert', badge
debug                     = TRM.get_logger 'debug', badge
warn                      = TRM.get_logger 'warn',  badge
help                      = TRM.get_logger 'help',  badge
echo                      = TRM.echo.bind TRM
#...........................................................................................................
# USERDB                    = require './main'


#-----------------------------------------------------------------------------------------------------------
@create_user = ( me, entry, handler ) ->
  password = entry[ 'password' ]
  return handler new Error "expected a user entry with password, found none" unless password?
  #.........................................................................................................
  @encrypt_password me, password, ( error, password_encrypted ) =>
    return handler error if error?
    #.......................................................................................................
    ### validates that ID is present: ###
    ignored             = @_id_from_entry me, entry
    entry[ '~isa' ]     = 'user'
    entry[ 'password' ] = password_encrypted
    #.......................................................................................................
    handler null
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@add_user = ( me, entry, handler ) ->
  #.........................................................................................................
  @user_exists me, entry[ 'uid' ], ( error, user_exists ) =>
    return handler error if error?
    if user_exists
      id_name = @_id_name_from_entry me, entry
      id      = entry[ id_name ]
      return handler new Error "user with ID #{id_name}: #{rpr id} already registered"
    #.......................................................................................................
    @upsert me, entry, handler
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@user_exists = ( me, uid, handler ) ->
  @get_user me, uid, null, ( error, entry ) =>
    return handler error if error?
    handler null, if entry is null then false else true
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@get_user = ( me, uid, fallback, handler ) ->
  switch arity = arguments.length
    when 3 then [ handler, fallback, ] = [ fallback, undefined, ]
    when 4 then null
    else throw new Error "expected three or four arguments, got #{arity}"
  #.........................................................................................................
  return @_get me, 'uid', uid, fallback, handler

