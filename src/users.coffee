

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
#...........................................................................................................
### TAINT these random seeds should probably not be hardcoded. Consider to replace them by something like
`new Date() / somenumber` in production. ###
create_rnd_id             = BAP.get_create_rnd_id 8327, 32


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
  password (or keep it from being encrypted twice) is to copy the original value and update the user entry
  in the DB when `create_user` has finished. ###
  #.........................................................................................................
  entry[ '~isa' ]     = type = 'user'
  [ pkn, skns, ]      = pkn_and_skns = @_key_names_from_type me, type
  ### TAINT should allow client to configure ID length ###
  ### TAINT using the default setup, IDs are replayable (but still depending on user inputs) ###
  entry[ pkn ]        = create_rnd_id [ entry[ 'email' ], entry[ 'name' ], ], 12
  ### TAINT we use constant field names here—not very abstract... ###
  entry[ 'added' ]    = new Date()
  password            = entry[ 'password' ]
  return handler new Error "expected a user entry with password, found none" unless password?
  #.........................................................................................................
  @encrypt_password me, password, ( error, password_encrypted ) =>
    return handler error if error?
    #.......................................................................................................
    entry[ 'password' ] = password_encrypted
    @_add_user me, entry, pkn_and_skns, handler
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@add_user = ( me, entry, handler ) ->
  type = TYPES.type_of entry
  throw new Error "expected entry to be of type user, got a #{type}" unless type is 'user'
  pkn_and_skns = @_key_names_from_type me, type
  #.........................................................................................................
  @_add_user me, entry, pkn_and_skns, ( error, entry ) =>
    return handler error if error?
    handler null, entry
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@_add_user = ( me, entry, pkn_and_skns, handler ) ->
  ### Add a user as specified by `entry` to the DB. This method does not modify `entry`, The password is
  not going to be touched—you could use this method to store an unencrypted password, so don't do that.
  Instead, use `create_user`, which is the canonical user to populate the DB with user records. ###
  #.........................................................................................................
  ### TAINT reduce to a single request ###
  ### TAINT introduce transactions ###
  return @_build_indexes me, entry, pkn_and_skns, handler

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
  #.........................................................................................................
  @get_user me, uid_hint, null, ( error, entry ) =>
    return handler error if error?
    return handler null, false if entry is null
    return handler null, true
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@test_user_integrity = ( me, uid_hint, handler ) ->
  ### TAINT we're wrongly assuming that `uid_hint` is a UID, which is wrong, as it could also be a secondary
  key ###
  return @test_integrity me, [ 'user', uid_hint, ], handler

#-----------------------------------------------------------------------------------------------------------
@get_user = ( me, uid_hint, fallback, handler ) ->
  [ handler, fallback, ]  = [ fallback, undefined, ] unless handler?
  ### TAINT we're wrongly assuming that `uid_hint` is a UID, which is wrong, as it could also be a secondary
  key ###
  prk                     = @_primary_record_key_from_hint me, [ 'user', uid_hint, ]
  return @entry_from_record_key me, prk,           handler if fallback is undefined
  return @entry_from_record_key me, prk, fallback, handler

#-----------------------------------------------------------------------------------------------------------
@authenticate_user = ( me, uid_hint, password, handler ) ->
  ### Given a user ID hint (for which see `USERDB._id_triplet_from_hint`) and a (clear) password, call
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














