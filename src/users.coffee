

############################################################################################################
# ERROR                     = require 'coffeenode-stacktrace'
njs_util                  = require 'util'
njs_path                  = require 'path'
njs_fs                    = require 'fs'
njs_url                   = require 'url'
#...........................................................................................................
BAP                       = require 'coffeenode-bitsnpieces'
TYPES                     = require 'coffeenode-types'
TRM                       = require 'coffeenode-trm'
rpr                       = TRM.rpr.bind TRM
badge                     = 'USERDB/users'
log                       = TRM.get_logger 'plain',   badge
info                      = TRM.get_logger 'info',    badge
whisper                   = TRM.get_logger 'whisper', badge
alert                     = TRM.get_logger 'alert',   badge
debug                     = TRM.get_logger 'debug',   badge
warn                      = TRM.get_logger 'warn',    badge
help                      = TRM.get_logger 'help',    badge
echo                      = TRM.echo.bind TRM
#...........................................................................................................
eventually                = process.nextTick


#-----------------------------------------------------------------------------------------------------------
@create_user = ( me, entry, handler ) ->
  ### Given a 'scaffold' of a user entry with fields as outlined in the `options.json` (and possibly more),
  add a user in the DB, using an encrypted version of the value in the `entry[ 'password' ]` field. The
  original scaffold entry will be modified and possibly amended with missing properties; its `~isa` field
  will unconditionally be set to `user`. When `handler` gets called, either an error has occurred, or the
  user has been saved using `USERDB.add_user`; it will not be possible to create more than a single user
  with a given unique identifier.

  Note: We assume here that communications with the server are made using a trusted connection, be it over,
  say, HTTP in the local, or HTTPS in the public network. It makes little sense to do cryptography in the
  client's browser using some program code that has arrived over an untrusted connection; likewise, when
  and if communication security has been established by, say, having initiated an HTTPS conversation, it
  does not make too much sense to perform encryption on the client side (apart from the fact that user
  passwords will exist in server RAM for a limited amount of time). Therefore, we assume that
  `entry[ 'password' ]` holds an unencrypted password, which we want to get rid of as soon as possible, so
  we unconditionally encrypt it. Currently, the only (recommended) way to keep a clear password is to copy
  it from `entry` before calling `USERDB.create_user`, and the only (recommended) way to *not* encrypt a
  password (or keep it from bein encrypted twice) is to copy the original value and update the user entry
  in the DB when `create_user` has finished. ###
  #.........................................................................................................
  ### TAINT we do currently not have support for transactions—these will probably built on top of Redis,
  or we may even switch to Redis as the sole DB layer for the CND UserDB. ###
  #.........................................................................................................
  entry[ '~isa' ]     = 'user'
  [ pk, sks, ]        = pk_and_sks = @_primary_and_secondary_keys_from_entry me, entry
  ### TAINT should allow client to configure ID length ###
  entry[ pk ]         = BAP.create_random_id [ entry[ 'email' ], entry[ 'name' ], ], 12
  ### TAINT we use constant field names here—not very abstract... ###
  entry[ 'added' ]    = new Date()
  password            = entry[ 'password' ]
  return handler new Error "expected a user entry with password, found none" unless password?
  #.........................................................................................................
  @encrypt_password me, password, ( error, password_encrypted ) =>
    return handler error if error?
    #.......................................................................................................
    entry[ 'password' ] = password_encrypted
    @_add_user me, entry, pk_and_sks, handler
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@add_user = ( me, entry, handler ) ->
  pk_and_sks = @_primary_and_secondary_keys_from_entry me, entry
  return @_add_user me, entry, pk_and_sks, handler

#-----------------------------------------------------------------------------------------------------------
@_add_user = ( me, entry, pk_and_sks, handler ) ->
  ### Add a user as specified by `entry` to the DB. This method does not modify `entry`, The password is
  not going to be touched—you could use this method to store an unencrypted password, so don't do that.
  Instead, use `create_user`, which is the canonical user to populate the DB with user records. ###
  #.........................................................................................................
  ### TAINT reduce to a single request ###
  ### TAINT introduce transactions ###
  return @_build_indexes me, entry, pk_and_sks, handler

  # @user_exists me, entry[ 'uid' ], ( error, user_exists ) =>
  #   return handler error if error?
  #   if user_exists
  #     id_name = @_get_id_name me
  #     id      = entry[ id_name ]
  #     return handler new Error "user with ID #{id_name}: #{rpr id} already registered"
  #   #.......................................................................................................
  #   @user_exists me, [ 'name', entry[ 'name' ] ], ( error, user_exists ) =>
  #     return handler error if error?
  #     if user_exists
  #       return handler new Error "user with name #{rpr entry[ 'name' ]} already registered"
  #     #.....................................................................................................
  #     @user_exists me, [ 'email', entry[ 'email' ] ], ( error, user_exists ) =>
  #       return handler error if error?
  #       if user_exists
  #         return handler new Error "user with email #{rpr entry[ 'email' ]} already registered"
  #       #...................................................................................................
  #       @upsert me, entry, handler
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@user_exists = ( me, uid_hint, handler ) ->
  [ id_name, id_value, ] = @_id_facet_from_hint me, uid_hint
  #.........................................................................................................
  @_get me, id_name, id_value, null, ( error, entry ) =>
    return handler error if error?
    handler null, if entry is null then false else true
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@get_user = ( me, uid_hint, fallback, handler ) ->
  switch arity = arguments.length
    when 3 then [ handler, fallback, ] = [ fallback, undefined, ]
    when 4 then null
    else throw new Error "expected three or four arguments, got #{arity}"
  #.........................................................................................................
  [ id_name, id_value, ] = @_id_facet_from_hint me, uid_hint
  return @_get me, id_name, id_value, fallback, handler

#-----------------------------------------------------------------------------------------------------------
@authenticate_user = ( me, uid_hint, password, handler ) ->
  ### Given a user ID hint (for which see `USERDB._id_facet_from_hint`) and a (clear) password, call
  `handler` with the result of comparing the given and the stored password for the user in question. ###
  #.........................................................................................................
  @get_user me, uid_hint, null, ( error, entry ) =>
    return handler error if error?
    return handler null, false, false unless entry?
    password_encrypted = entry[ 'password' ]
    #.......................................................................................................
    @test_password me, password, password_encrypted, ( error, password_matches ) =>
      return handler error if error?
      handler null, true, password_matches
  #.........................................................................................................
  return null














