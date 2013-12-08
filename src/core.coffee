

############################################################################################################
njs_util                  = require 'util'
njs_path                  = require 'path'
njs_fs                    = require 'fs'
njs_url                   = require 'url'
#...........................................................................................................
TYPES                     = require 'coffeenode-types'
TRM                       = require 'coffeenode-trm'
rpr                       = TRM.rpr.bind TRM
badge                     = 'USERDB/core'
log                       = TRM.get_logger 'plain',     badge
info                      = TRM.get_logger 'info',      badge
whisper                   = TRM.get_logger 'whisper',   badge
alert                     = TRM.get_logger 'alert',     badge
debug                     = TRM.get_logger 'debug',     badge
warn                      = TRM.get_logger 'warn',      badge
help                      = TRM.get_logger 'help',      badge
echo                      = TRM.echo.bind TRM
#...........................................................................................................
### https://github.com/mranney/node_redis ###
redis                     = require 'redis'
#...........................................................................................................
### https://github.com/caolan/async ###
async                     = require 'async'
#...........................................................................................................
default_options           = require '../options'


#===========================================================================================================
# DB CREATION
#-----------------------------------------------------------------------------------------------------------
@new_db = ->
  R                 = '~isa': 'USERDB/db'
  R[ name ]         = value for name, value of default_options
  collection_idx    = R[ 'collection-idx' ] ? 0
  # debug '©23a', 'caveat substratum'
  R[ '%self' ]      = substrate = redis.createClient R[ 'port' ], R[ 'host' ]
  #.........................................................................................................
  ### TAINT may not this result in collection not already selected when function returns?
  It did seem to work in the tests, though. ###
  substrate.select collection_idx, ( error, response ) =>
    throw error if error?
  #.........................................................................................................
  return R

#-----------------------------------------------------------------------------------------------------------
@close = ( me ) ->
  me[ '%self' ].quit()


#===========================================================================================================
# TYPE DESCRIPTIONS
#-----------------------------------------------------------------------------------------------------------
_identity   = ( x     ) -> x
_read_json  = ( text  ) -> JSON.parse text
_write_json = ( value ) -> JSON.stringify value

#-----------------------------------------------------------------------------------------------------------
@codecs =
  ### In this iteration of the UserDB / Redis interface, we do not support clientside type descriptions—only
  the types described here are legal values in entry type schemas. ###
  #.........................................................................................................
  date:
    read:     ( text  ) -> new Date text
    write:    ( value ) -> value.toISOString()
  #.........................................................................................................
  number:
    read:     ( text  ) -> parseFloat text, 10
    write:    ( value ) -> value.toString()
  # pod:        'json'
  #.........................................................................................................
  json:
    read:     _read_json
    write:    _write_json
  #.........................................................................................................
  boolean:
    read:     _read_json
    write:    _write_json
  #.........................................................................................................
  null:
    read:     _read_json
    write:    _write_json
  #.........................................................................................................
  text:
    read:     _identity
    write:    _identity
  #.........................................................................................................
  identity:
    read:     _identity
    write:    _identity

#-----------------------------------------------------------------------------------------------------------
@_schema_from_entry = ( me, entry ) ->
  schemas     = me[ 'schema' ]
  type        = entry[ '~isa' ]
  throw new Error "unable to find schema in db:\n#{rpr me}"   unless schemas?
  throw new Error "entry has no `~isa` member:\n#{rpr entry}" unless type?
  R           = schemas[ type ]
  throw new Error "unable to find schema for type #{rpr type}" unless R?
  return R


#===========================================================================================================
# INSERTION
#-----------------------------------------------------------------------------------------------------------
@_build_indexes = ( me, entry, pkn_and_skns, handler ) ->
  ### This method performs the lowlevel gruntwork necessary to represent an entry in the Redis DB. In
  particular, it issues a HMSET user/uid:$uid k0 v0 k1 v1 ...` command to save the entry as a Redis
  hash; then, it issues commands like `SET user/email:$email/uid $uid` and others (as configured in the data
  type description) to make the entry retrievable using secondary unique keys (such as email address). ###
  [ pkn, skns, ]  = pkn_and_skns
  [ prk, srks, ]  = @_get_primary_and_secondary_record_keys me, entry, pkn_and_skns
  entry[ '~prk' ] = prk
  record          = @_cast_to_db me, prk, entry
  type            = record[ '~isa' ]
  #.........................................................................................................
  add = ( srk_and_prk, done ) ->
    [ srk, prk, ] = srk_and_prk
    me[ '%self' ].set srk, prk, done
  #.........................................................................................................
  me[ '%self' ].hmset prk, record, ( error, response ) =>
    return handler error if error?
    return handler null, record unless srks.length > 0
    #.......................................................................................................
    srks_and_prks = ( [ srk, prk ] for srk in srks when srk? )
    #.......................................................................................................
    async.each srks_and_prks, add, ( error ) =>
      return handler error if error?
      handler null, record
  #.........................................................................................................
  return null


#===========================================================================================================
# REMOVAL
#-----------------------------------------------------------------------------------------------------------
@remove = ( me, pattern, handler ) ->
  ### Remove all records whose key matches `pattern` (whose semantics are the same as in `get_keys`). ###
  #.........................................................................................................
  ### TAINT should use `multi` to prevent race conditions ###
  ### TAINT consider to batch keys for less requests ###
  #.........................................................................................................
  Z = 0
  #.........................................................................................................
  remove = ( key, done ) =>
    me[ '%self' ].del key, ( error, count ) =>
      return done error if error?
      Z += count
      done null, Z
  #.........................................................................................................
  @get_keys me, pattern, ( error, keys ) =>
    return handler error if error?
    #.......................................................................................................
    async.each keys, remove, ( error, results ) =>
      return handler error if error?
      handler null, Z
  #.........................................................................................................
  return null


#===========================================================================================================
# RETRIEVAL
#-----------------------------------------------------------------------------------------------------------
@walk_keys = ( me, pattern, handler ) ->
  ### Given a `pattern`, yield matching keys in the DB one by one; after the last key, a `null` is yielded
  to indicate the end of the listing. Glob-style patterns are supported; as per the Redis documentation:

  *  `h?llo` matches `hello`, `hallo` and `hxllo`
  *  `h*llo` matches `hllo` and `heeeello`
  *  `h[ae]llo` matches `hello` and `hallo`, but not `hillo`
  *  Use `\` to escape special characters if you want to match them verbatim. ###
  #.........................................................................................................
  ### TAINT we're using the Redis < 2.8 `keys` command here, as the better Redis >= 2.8 `scan` command
  family is not yet available. Be aware that a Redis instance with lots of keys may become temporarily
  unavailable for other clients whenever `USERDB.walk_keys` or `get_keys` are used in their present
  implementation. ###
  me[ '%self' ].keys pattern, ( error, response ) =>
    return handler error if error?
    handler null, key for key in response
    handler null, null

#-----------------------------------------------------------------------------------------------------------
@get_keys = ( me, pattern, handler ) ->
  ### Given a `pattern`, yield the matching keys in the DB. Glob-style patterns are supported; as per the
  Redis documentation:

  *  `h?llo` matches `hello`, `hallo` and `hxllo`
  *  `h*llo` matches `hllo` and `heeeello`
  *  `h[ae]llo` matches `hello` and `hallo`, but not `hillo`
  *  Use `\` to escape special characters if you want to match them verbatim. ###
  #.........................................................................................................
  ### TAINT we're using the Redis < 2.8 `keys` command here, as the better Redis >= 2.8 `scan` command
  family is not yet available. Be aware that a Redis instance with lots of keys may become temporarily
  unavailable for other clients whenever `USERDB.walk_keys` or `get_keys` are used in their present
  implementation. ###
  me[ '%self' ].keys pattern, handler

#-----------------------------------------------------------------------------------------------------------
@entry_from_record_key = ( me, prk, fallback, handler ) ->
  ### TAINT implement type casting for all Redis types ###
  [ fallback, handler, ] = [ undefined, fallback, ] unless handler?
  #.........................................................................................................
  @record_from_prk me, prk, ( error, value ) =>
    if error?
      return handler error if fallback is undefined
      if /^nothing found for primary record key /.test error[ 'message' ]
        return handler null, fallback
      return handler error
    if TYPES.isa_pod value
      try
        return handler null, @_cast_from_db me, value[ '~prk' ], value
      catch error
        return handler error
    return handler null, value
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@record_from_prk = ( me, prk, fallback, handler ) ->
  [ fallback, handler, ] = [ undefined, fallback, ] unless handler?
  #.........................................................................................................
  me[ '%self' ].type prk,  ( error, type ) =>
    return handler error if error?
    #.......................................................................................................
    switch type
      #.....................................................................................................
      when 'none'
        return handler null, fallback unless fallback is undefined
        return handler new Error "nothing found for primary record key #{rpr prk}"
      #.....................................................................................................
      when 'string'
        me[ '%self' ].get prk, ( error, text ) =>
          throw error if error?
          return handler null, text
      #.....................................................................................................
      when 'hash'
        me[ '%self' ].hgetall prk, ( error, hash ) =>
          return handler null, hash
      #.....................................................................................................
      when 'list'
        me[ '%self' ].llen prk, ( error, length ) =>
          throw error if error?
          me[ '%self' ].lrange prk, 0, length - 1, ( error, values ) =>
            return handler null, values
      #.....................................................................................................
      when 'set'
        return handler new Error "type #{rpr type} not implemented"
      #.....................................................................................................
      when 'zset'
        return handler new Error "type #{rpr type} not implemented"
      #.....................................................................................................
      else
        return handler new Error "type #{rpr type} not implemented"
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@_primary_record_key_from_hint = ( me, id_hint ) ->
  return @_primary_record_key_from_id_triplet me, @_id_triplet_from_hint me, id_hint

#-----------------------------------------------------------------------------------------------------------
@_primary_record_key_from_id_triplet = ( me, P... ) ->
  ### TAINT shares code with `_secondary_record_key_from_id_triplet` ###
  switch arity = P.length + 1
    when 2 then P = P[ 0 ]
    when 4 then null
    else throw new Error "expected two or four arguments, got #{arity}"
  throw new Error "expected list with three elements, got one with #{P.length}" unless P.length is 3
  #.........................................................................................................
  [ type, pkn, pkv, ] = P
  pkvx                = @escape_key_value_crumb me, pkv
  #.........................................................................................................
  return "#{type}/#{pkn}:#{pkvx}"

#-----------------------------------------------------------------------------------------------------------
@_secondary_record_key_from_id_triplet = ( me, P... ) ->
  ### TAINT shares code with `_primary_record_key_from_id_triplet` ###
  switch arity = P.length + 1
    when 2 then P = P[ 0 ]
    when 4 then null
    else throw new Error "expected two or four arguments, got #{arity}"
  throw new Error "expected list with three elements, got one with #{P.length}" unless P.length is 3
  #.........................................................................................................
  [ type, skn, skv, ] = P
  skvx                = @escape_key_value_crumb me, skv
  #.........................................................................................................
  return "#{type}/#{skn}:#{skvx}/~prk"

#-----------------------------------------------------------------------------------------------------------
@_id_triplet_from_hint = ( me, id_hint ) ->

  ###


  * using an existing entry

  * using the PRK or an SRK:

    * `'user/uid:17c07627d35e'`
    * `'user/email:alice@hotmail.com/~prk'`
    * `'user/name:Alice/~prk'`

  * using triplets spelling out type, field name, and field value:

    * `[ 'user', 'uid',   '17c07627d35e',      ]`
    * `[ 'user', 'email', 'alice@hotmail.com', ]`
    * `[ 'user', 'name',  'Alice',             ]`

  * using a type / PKV pair:

    * `[ 'user', '17c07627d35e', ]`


  ###


  switch type_of_hint = TYPES.type_of id_hint
    #.......................................................................................................
    when 'list'
      #.....................................................................................................
      switch ( length = id_hint.length )
        when 2
          [ type, pkv,  ] = id_hint
          [ pkn,  skns, ] = @_key_names_from_type me, type
          return [ type, pkn, pkv, ]
        when 3
          [ type, pskn, pskv ] = id_hint
          [ pkn,  skns, ] = @_key_names_from_type me, type
          return [ type, pskn, pskv, ] if pskn is pkn
          return [ type, pskn, pskv, ] if skns.indexOf pskn > -1
          throw new Error "hint has PKN or SKN #{rpr pskn}, but schema has #{type}: #{[ pkn, skns ]}"
        else
          throw new Error "expected a list with two or three elements, got one with #{length} elements"
      #.....................................................................................................
      pkn           = @_primary_key_name_from_type me, type
      return [ type, pkn, id, ]
    #.......................................................................................................
    when 'text'
      ### When the hint is a text, it is understood as a Primary or Secondary Record Key: ###
      return R if ( R = @split_record_key me, id_hint, null )?
      throw new Error "unable to get ID facet from #{rpr id_hint}"
  #.........................................................................................................
  throw new Error "unable to get ID facet from value of type #{type_of_hint}"


#-----------------------------------------------------------------------------------------------------------
@_key_names_from_type = ( me, type ) ->
  index_description = @_index_description_from_type me, type
  pkn               = index_description[ 'primary-key' ]
  throw new Error "no primary key in index description for type #{rpr type}" unless pkn?
  skns              = index_description[ 'secondary-keys' ] ? []
  #.........................................................................................................
  return [ pkn, skns, ]

#-----------------------------------------------------------------------------------------------------------
@_secondary_key_names_from_type = ( me, type ) ->
  R = ( @_index_description_from_type me, type )[ 'secondary-keys' ] ? []
  return R

#-----------------------------------------------------------------------------------------------------------
@_primary_key_name_from_type = ( me, type ) ->
  R = ( @_index_description_from_type me, type )[ 'primary-key' ]
  throw new Error "type #{rpr type} has no primary key in index description" unless R?
  return R

#-----------------------------------------------------------------------------------------------------------
@_index_description_from_type = ( me, type ) ->
  indexes     = me[ 'indexes' ]
  throw new Error "unable to find indexes in db:\n#{rpr db}"  unless indexes?
  R           = indexes[ type ]
  throw new Error "type #{rpr type} has no index description in\n#{rpr indexes}" unless R?
  return R

#-----------------------------------------------------------------------------------------------------------
@_get_primary_and_secondary_record_keys = ( me, entry, pkn_and_skns ) ->
  [ pkn
    skns ]  = pkn_and_skns
  srks      = []
  #.........................................................................................................
  type      = entry[ '~isa' ]
  pkv       = entry[ pkn ]
  throw new Error "unable to find a primary key (#{rpr pk_name}) in entry #{rpr entry}" unless pkv?
  prk       = @_primary_record_key_from_id_triplet me, type, pkn, pkv
  R         = [ prk, srks, ]
  #.........................................................................................................
  for skn in skns
    if ( skv = entry[ skn ] )?
      srk = @_secondary_record_key_from_id_triplet me, type, skn, skv
      srks.push srk
    else
      srks.push undefined
  #.........................................................................................................
  return R



#===========================================================================================================
# KEY PARSING
#-----------------------------------------------------------------------------------------------------------
crumb = '([^/:\\s]+)'
@_prk_matcher = /// ^ #{crumb} / #{crumb} : #{crumb}        $ ///
@_srk_matcher = /// ^ #{crumb} / #{crumb} : #{crumb} / ~prk $ ///

#-----------------------------------------------------------------------------------------------------------
@split_record_key = ( me, rk, fallback ) ->
  R = @split_primary_record_key   me, rk, null
  R = @split_secondary_record_key me, rk, null unless R?
  unless R?
    return fallback unless fallback is undefined
    throw new Error "illegal PRK / SRK: #{rpr rk}"
  return R

#-----------------------------------------------------------------------------------------------------------
@split_primary_record_key = ( me, prk, fallback ) ->
  match = prk.match @_prk_matcher
  unless match?
    return fallback unless fallback is undefined
    throw new Error "illegal PRK: #{rpr prk}"
  return match[ 1 .. 3 ]

#-----------------------------------------------------------------------------------------------------------
@split_secondary_record_key = ( me, srk, fallback ) ->
  match = srk.match @_srk_matcher
  unless match?
    return fallback unless fallback is undefined
    throw new Error "illegal SRK: #{rpr srk}"
  return match[ 1 .. 3 ]


#===========================================================================================================
# KEY ESCAPING
#-----------------------------------------------------------------------------------------------------------
@escape_key_value_crumb = ( me, text ) ->
  ### Given a text that is intended to be used inside a Redis structured (URL-like) key, return it escaped
  so that the systematic characters—space, slash, and colon—are replaced by `+_`, `+,`, and `+.`,
  respectively; plus signs will be encoded as `++`. Examples:

  * key without escaping:   `user/name:Just A. User/~prk`
  * value crumb:            `Just A. User`
  * value crumb escaped:    `Just+_A.+_User`
  * key with escaping:      `user/name:Just+_A.+_User/~prk`

  * key without escaping:   `user/url:http://example.com/foo/bar//~prk`
  * value crumb:            `http://example.com/foo/bar/`
  * value crumb escaped:    `http+.+,+,example.com+,foo+,bar+,`
  * key with escaping:      `user/url:http+.+,+,example.com+,foo+,bar+,/~prk`

  ###
  R = text
  R = R.replace /\+/g,    '++'
  R = R.replace /\x20/g,  '+_'
  R = R.replace /\//g,    '+,'
  R = R.replace /\:/g,    '+.'
  return R

#-----------------------------------------------------------------------------------------------------------
@unescape_key_value_crumb = ( me, text ) ->
  ### Reverse the effect of applying `escape_key_value_crumb`. ###
  R = text
  R = R.replace /\+_/g,   ' '
  R = R.replace /\+,/g,   '/'
  R = R.replace /\+\./g,  ':'
  R = R.replace /\+\+/g,  '+'
  return R


#===========================================================================================================
# ENTRY CASTING
#-----------------------------------------------------------------------------------------------------------
@_cast_to_db = ( me, prk, entry ) ->
  ### Given an entry, return a new POD with all values cast to DB strings as specified in that type's
  description. ###
  ### TAINT implement casting for other entry types; needs prk for that ###
  R       = {}
  schema  = @_schema_from_entry me, entry
  #.........................................................................................................
  for field_name, value of entry
    R[ field_name ] = ( @codecs[ schema[ field_name ] ? 'identity' ]?[ 'write' ] ) value
  #.........................................................................................................
  return R

#-----------------------------------------------------------------------------------------------------------
@_cast_from_db = ( me, prk, record ) ->
  ### Given an record coming from the DB with all values as strings, apply the decoders as specified in that
  types's description and return the entry. ###
  ### TAINT implement casting for other entry types; needs prk for that ###
  schema = @_schema_from_entry me, record
  #.........................................................................................................
  for field_name, text of record
    record[ field_name ] = ( @codecs[ schema[ field_name ] ? 'identity' ]?[ 'read' ] ) text
  #.........................................................................................................
  return record

