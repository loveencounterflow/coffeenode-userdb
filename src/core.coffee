

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
@_primary_and_secondary_keys_from_entry = ( me, entry ) ->
  indexes     = me[ 'indexes' ]
  type        = entry[ '~isa' ]
  throw new Error "unable to find indexes in db:\n#{rpr db}"  unless indexes?
  throw new Error "entry has no `~isa` member:\n#{rpr entry}" unless type?
  dt_indexes  = indexes[ type ]
  throw new Error "no index description for type #{rpr type}:\n#{rpr indexes}" unless dt_indexes?
  pk          = dt_indexes[ 'primary-key' ]
  throw new Error "no primary key in index description for type #{rpr type}:\n#{rpr dt_indexes}" unless pk?
  sks         = dt_indexes[ 'secondary-keys' ] ? []
  #.........................................................................................................
  return [ pk, sks, ]

#-----------------------------------------------------------------------------------------------------------
@_schema_from_entry = ( me, entry ) ->
  schemas     = me[ 'schema' ]
  type        = entry[ '~isa' ]
  throw new Error "unable to find schema in db:\n#{rpr db}"   unless schemas?
  throw new Error "entry has no `~isa` member:\n#{rpr entry}" unless type?
  R           = schemas[ type ]
  throw new Error "unable to find schema for ty<pe #{rpr type} in db:\n#{rpr db}" unless R?
  return R

#-----------------------------------------------------------------------------------------------------------
@_cast_to_db = ( me, entry ) ->
  ### Given an entry, return a new POD with all values cast to DB strings as specified in that type's
  description. ###
  R       = {}
  schema  = @_schema_from_entry me, entry
  #.........................................................................................................
  for field_name, value of entry
    R[ field_name ] = ( @codecs[ schema[ field_name ] ? 'identity' ]?[ 'write' ] ) value
  #.........................................................................................................
  return R

#-----------------------------------------------------------------------------------------------------------
@_cast_from_db = ( me, entry ) ->
  ### Given an entry coming from the DB with all values as strings, apply the decoders as specified in that
  types's description and return the entry. ###
  schema = @_schema_from_entry me, entry
  #.........................................................................................................
  for field_name, text of entry
    R[ field_name ] = ( @codecs[ schema[ field_name ] ? 'identity' ]?[ 'read' ] ) text
  #.........................................................................................................
  return entry


#===========================================================================================================
# INSERTION
#-----------------------------------------------------------------------------------------------------------
@_build_indexes = ( me, entry, pk_and_sks, handler ) ->
  ### This method performs the lowlevel gruntwork necessary to represent an entry in the Redis DB. In
  particular, it issues a HMSET user/uid:$uid k0 v0 k1 v1 ...` command to save the the entry as a Redis
  hash; then, it issues commands like `SET user/email:$email/uid $uid` and others (as configured in the data
  type description) to make the entry retrievable using secondary unique keys (such as email address). ###
  [ pk_name
    sk_names ]  = pk_and_sks
  entry         = @_cast_to_db me, entry
  type          = entry[ '~isa' ]
  description   = me[ 'description' ]
  pk_value      = entry[ pk_name ]
  throw new Error "unable to find a primary key (#{rpr pk_name}) in entry #{rpr entry}" unless pk_value?
  #.........................................................................................................
  me[ '%self' ].hmset "#{type}/#{pk_name}:#{pk_value}", entry, ( error, response ) =>
    return handler error if error?
    #.......................................................................................................
    if sk_names.length is 0
      handler null, null if handler?
      return null
    #.......................................................................................................
    tasks = []
    for sk_name in sk_names
      sk_value  = entry[ sk_name ]
      continue unless sk_value?
      do ( type, sk_name, sk_value, pk_name, pk_value ) =>
        tasks.push ( done ) =>
          me[ '%self' ].set "#{type}/#{sk_name}:#{sk_value}/#{pk_name}", pk_value, done
    #.......................................................................................................
    async.parallel tasks, ( error, results ) =>
      if error?
        return handler errors if handler?
        throw error
      handler null, results if handler?
      return null
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@upsert = ( me, entry, handler ) ->
  unless ( entry_type = entry[ '~isa' ] )?
    throw new Error "unable to update / insert entry without `~isa` attribute"
  #.........................................................................................................
  id                    = @_id_from_entry me, entry
  [ url, http_method ]  = @_get_url_and_method me, entry_type, 'upsert', id
  #.........................................................................................................
  request_options =
    method:   http_method
    url:      url
    json:     true
    body:     entry
  #.........................................................................................................
  mik_request request_options, ( error, response ) =>
    return handler error if error?
    #.......................................................................................................
    result = response[ 'body' ]
    return handler new Error     result if     ( TYPES.type_of result ) is 'text'
    return handler new Error rpr result unless result[ 'ok' ]
    handler null, result
  #.........................................................................................................
  return null


#===========================================================================================================
# RETRIEVAL
#-----------------------------------------------------------------------------------------------------------
@search = ( me, entry_type, elastic_query, handler ) ->
  if ( arity = arguments.length ) is 3
    [ entry_type, elastic_query, handler, ] = [ null, entry_type, elastic_query, ]
  else unless 3 <= arity <= 4
    throw new Error "expected three or four arguments, got #{arity}"
  #.........................................................................................................
  return @_search me, entry_type, elastic_query, handler

#-----------------------------------------------------------------------------------------------------------
@search_entries = ( me, entry_type, elastic_query, handler ) ->
  ### Works exactly like `USERDB.search`, except that only the entries themselves are returned. ###
  if ( arity = arguments.length ) is 3
    [ entry_type, elastic_query, handler, ] = [ null, entry_type, elastic_query, ]
  else unless 3 <= arity <= 4
    throw new Error "expected three or four arguments, got #{arity}"
  #.........................................................................................................
  @_search me, entry_type, elastic_query, ( error, results ) ->
    return handler error if error?
    handler null, results[ 'entries' ]
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@_search = ( me, entry_type, elastic_query, handler ) ->
  #.........................................................................................................
  [ url, http_method, ] = @_get_url_and_method me, null, 'search'
  #.........................................................................................................
  request_options =
    method:   http_method
    url:      url
    json:     true
    body:     elastic_query
  #.........................................................................................................
  mik_request request_options, ( error, response ) =>
    return handler error if error?
    #.......................................................................................................
    results = @_results_from_response me, response
    return handler results[ 'error' ] if results[ 'error' ]?
    handler null, results
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@get = ( me, id_name, id_value, fallback, handler ) ->
  ### Given a name and a value for a (hopefully) field with unique values, find the one record matching
  those criteria. In case no entry was found, either call back with an error, or, if `fallback` was defined,
  call back with that value. Criteria that happen to match more than one entry will cause a callback with
  an error.
  ###
  switch arity = arguments.length
    when 4
      [ handler, fallback, ] = [ fallback, undefined, ]
    when 5
      null
    else
      throw new Error "expected four or five arguments, got #{arity}"
  #.........................................................................................................
  return @_get me, id_name, id_value, fallback, handler

#-----------------------------------------------------------------------------------------------------------
@_get = ( me, id_name, id_value, fallback, handler ) ->
  query = @filter_query_from_id_facet me, id_name, id_value
  #.........................................................................................................
  @search me, query, ( error, results ) =>
    return handler error if error?
    #.......................................................................................................
    entries = results[ 'entries' ]
    return handler new Error "search on non-unique field #{rpr id_name}" if entries.length > 1
    if entries.length is 0
      return handler null, fallback if fallback isnt undefined
      return handler new Error "unable to find entry with #{id_name}: #{rpr id_value}"
    handler null, entries[ 0 ]
  #.........................................................................................................
  return null


#===========================================================================================================
#
#-----------------------------------------------------------------------------------------------------------
@validate_is_running = ( me ) ->
  @get me, 'uid', '0', 'OK', ( error, response ) ->
    if error?
      if /connect ECONNREFUSED/.test error[ 'message' ]
        alert """
          you either forgot to start your CoffeeNode UserDB instance or it does not match the configuration:
          #{rpr me}
          """
        help """
          execute `elasticsearch -f -D es.config=/usr/local/opt/elasticsearch/config/elasticsearch.yml`
          or demonize ElasticSearch"""
      throw error
    info "ElasticSearch response: #{rpr response}"


#===========================================================================================================
# URL BUILDING & QUERY FORMULATION
#-----------------------------------------------------------------------------------------------------------
@filter_query_from_id_facet = ( me, id_name, id_value ) ->
  filter            = {}
  filter[ id_name ] = id_value
  #.........................................................................................................
  R =
    query:
      filtered:
        query:
          match_all: {}
        filter:
          term: filter
  #.........................................................................................................
  return R

#-----------------------------------------------------------------------------------------------------------
@_get_url_and_method = ( me, entry_type, verb, id ) ->
  ### Given a DB instance, an optional entry type, and one of the verbs specified as value in
  `USERDB._esverb_by_verb`, return a URL and a HTTP method name to run a request against. Examples:

      USERDB._get_url db, 'user', 'search'
      USERDB._get_url db, null, 'search'
      USERDB._get_url db, '', 'search'

  will result in, respectively,

      [ 'post', http://localhost:9200/users/user/_search ]
      [ 'post', http://localhost:9200/users/_search      ]
      [ 'post', http://localhost:9200/users/_search      ]

  ###
  entry_type ?= ''
  id         ?= ''
  esverb      = @_esverb_by_verb[ verb ]
  throw new Error "unknown verb #{rpr verb}" unless esverb?
  pathname    = njs_path.join me[ 'base-route' ], me[ 'collection-name' ], entry_type, esverb, id
  #.........................................................................................................
  url = njs_url.format
    protocol:       me[ 'protocol' ]
    hostname:       me[ 'hostname' ]
    port:           me[ 'port' ]
    pathname:       pathname
  #.........................................................................................................
  http_method = @_http_method_by_verb[ verb ]
  throw new Error "unknown verb #{rpr verb}" unless http_method?
  #.........................................................................................................
  return [ url, http_method, ]

#-----------------------------------------------------------------------------------------------------------
@_get_id_name = ( me ) ->
  R = me[ 'description' ]?[ 'mappings' ]?[ 'user' ]?[ 'properties' ]?[ '_id' ]?[ 'path' ]
  #.........................................................................................................
  unless R?
    throw new Error """
      expected to find a field name in options/description/mappings/user/properties/_id/path;
      found nothing instead. Check `options.json` for errors."""
  #.........................................................................................................
  return R

#-----------------------------------------------------------------------------------------------------------
@_id_from_entry = ( me, entry ) ->
  return @__id_from_entry me, entry, @_get_id_name me

#-----------------------------------------------------------------------------------------------------------
@__id_from_entry = ( me, entry, id_name ) ->
  #.........................................................................................................
  R = entry[ id_name ]
  unless R?
    throw new Error """
      expected to find an ID in field #{rpr id_name} of entry #{rpr entry};
      found nothing instead"""
  #.........................................................................................................
  return R

#-----------------------------------------------------------------------------------------------------------
@_id_facet_from_entry = ( me, entry ) ->
  id_name = @_get_id_name me
  return [ id_name, @__id_from_entry me, entry, id_name ]

#-----------------------------------------------------------------------------------------------------------
@_id_facet_from_hint = ( me, id_hint ) ->
  ### Given a hint for a unique entry identifier, return a list `[ id_name, id_value, ]` that spells out
  the field name and value to match. An `id_hint` may be **(1)** a list, in which case it must have two
  elements (that form a name / value pair), and the first value must be a non-empty text; **(2)** an object
  (a POD) of type `user`, in which case the result of `USERDB._id_facet_from_entry` will be returned;
  **(3)** an object (a POD) of the format `{ $id_name: $id_value }` with a single name and value; **(4)**
  a value of any other type such as a text or a number; in this case, the ID mapping configured in the
  UserDB options will be used to determine the ID field name. ###
  switch type_of_hint = TYPES.type_of id_hint
    #.......................................................................................................
    when 'list'
      #.....................................................................................................
      unless ( length = id_hint.length ) is 2
        throw new Error "expected a list with two elements, got one with #{length} elements"
      #.....................................................................................................
      R = [ id_name, id_value, ] = id_hint
      #.....................................................................................................
      unless ( type_of_name = TYPES.type_of id_name ) is 'text'
        throw new Error "expected ID name to be a text, got a #{type_of_name}"
      #.....................................................................................................
      unless id_name.length > 0
        throw new Error "expected ID name to be a non-empty text, got an empty text"
      #.....................................................................................................
      return R
    #.......................................................................................................
    when 'user'
      return @_id_facet_from_entry me, id_hint
    #.......................................................................................................
    when 'pod'
      #.....................................................................................................
      facets = ( [ name, value, ] for name, value of id_hint )
      #.....................................................................................................
      unless ( length = facets.length ) is 1
        throw new Error "expected a POD with a single facet, got one with #{length} facets"
      #.....................................................................................................
      R = [ id_name, id_value, ] = facets[ 0 ]
      #.....................................................................................................
      unless id_name.length > 0
        throw new Error "expected ID name to be a non-empty text, got an empty text"
      #.....................................................................................................
      return R
    #.......................................................................................................
    when 'text', 'number', 'boolean'
      return [ ( @_get_id_name me ), id_hint, ]
  #.........................................................................................................
  throw new Error "unable to get ID facet from value of type #{type_of_hint}"


#===========================================================================================================
# RESPONSE TRANSFORMATION
#-----------------------------------------------------------------------------------------------------------
@_results_from_response = ( me, response ) ->
  request       = response[  'request'  ]
  body          = response[  'body'     ]
  request_url   = request[   'href'     ]
  error         = body[      'error'    ] ? null
  headers       = response[  'headers'  ]
  status        = body[      'status'   ]
  dt            = body[      'took'     ]
  scores        = []
  entries       = []
  ids           = []
  count         = 0
  #.........................................................................................................
  if ( hits = body[ 'hits' ]?[ 'hits' ] )?
    count = body[ 'hits' ][ 'total' ]
    for hit in hits
      scores.push   hit[ '_score'  ]
      entries.push  hit[ '_source' ]
      ids.push      hit[ '_id'     ]
  #.........................................................................................................
  R =
    '~isa':         'USERDB/response'
    'url':          request_url
    'status':       status
    'error':        error
    'scores':       scores
    'ids':          ids
    'entries':      entries
    'count':        count
    'first-idx':    0
    'dt':           dt
  #.........................................................................................................
  return R

############################################################################################################
############################################################################################################
############################################################################################################
############################################################################################################
############################################################################################################
############################################################################################################
############################################################################################################


# new redis code below



# ############################################################################################################
# # ERROR                     = require 'coffeenode-stacktrace'
# njs_util                  = require 'util'
# # njs_path                  = require 'path'
# njs_fs                    = require 'fs'
# #...........................................................................................................
# # TEXT                      = require 'coffeenode-text'
# TYPES                     = require 'coffeenode-types'
# TRM                       = require 'coffeenode-trm'
# rpr                       = TRM.rpr.bind TRM
# badge                     = 'scratch'
# log                       = TRM.get_logger 'plain',     badge
# info                      = TRM.get_logger 'info',      badge
# whisper                   = TRM.get_logger 'whisper',   badge
# alert                     = TRM.get_logger 'alert',     badge
# debug                     = TRM.get_logger 'debug',     badge
# warn                      = TRM.get_logger 'warn',      badge
# help                      = TRM.get_logger 'help',      badge
# echo                      = TRM.echo.bind TRM
# rainbow                   = TRM.rainbow.bind TRM
# suspend                   = require 'coffeenode-suspend'
# step                      = suspend.step
# after                     = suspend.after
# eventually                = suspend.eventually
# immediately               = suspend.immediately
# every                     = suspend.every
# USERDB                    = require 'coffeenode-userdb'



# redis = require 'redis'

# identity = ( x ) -> x


# #-----------------------------------------------------------------------------------------------------------
# user_description =
#   types:
#     date:
#       validate: null
#       read:     ( text  ) -> new Date text
#       # write:    ( value ) -> value.toGMTString()
#       write:    ( value ) -> value.toISOString()
#     json:
#       read:     ( text  ) -> JSON.parse text
#       write:    ( value ) -> JSON.stringify value
#     number:
#       read:     ( text  ) -> parseFloat text, 10
#       write:    ( value ) -> value.toString()
#     pod:        'json' # reference to named format
#     text:
#       read:     identity
#       write:    identity
#   schema:
#     user:
#       age:      'number'
#       rating:   'json'
#       added:    'date'
#       name:     'text'
#   # 'Index' here means 'a named text value that can be used to uniquely identify an entry'.
#   #
#   # There must be exactly one field whose value is set to `true`; its name will be used together with
#   # `value = entry[ name ]` to build a unique key for each entry; here we will use `user/uid:$uid`; this
#   # is the 'primary key'.
#   #
#   # 'Secondary keys' allow to retrieve a primary key by using another unique field of an entry. For example,
#   # a user DB might enforce all of user ID, nickname and email address to be unique over all users and
#   # use the user ID as primary key (this design will allow us to change primary email addresses and user
#   # display names without touching the 'identity' of the user). The configuration for a secondary key is
#   # by setting the name of the primary key to `true`. For example, to retrieve user IDs by email addresses,
#   # configure `{ indexes: { user: { email: uid: true } } }`; this will result in a
#   # `SET user/email:$email/uid $uid` (e.g. `SET user/email:tim@example.com/uid 'user/uid:3df843ac12'`, which
#   # indicates that the user with the email adress `tim@example.com` is on record with the key
#   # `user/uid:3df843ac12`). Note that the unqueness of secondary keys will be enforced—as long as there is
#   # a key `user/email:tim@example.com/uid` in the DB, no other user can be registered with that email
#   # address, which is probably what you want.
#   #
#   # ### TAINT tertiary keys to be implemented later ###
#   #
#   # # 'Tertiary keys' allow to retrieve facts about an entry without retrieving the entry itself. These keys
#   # # are configured like secondary keys, but using field names other than the primary key; no uniqueness
#   # # constraint will be enforced for these.
#   # # Any other fields listed here must name one or more other existing fields; for each
#   # # referenced field, an index  uniqueness of `SET user/$fromname:$fromvalue/$toname $tovalue` will be enforced
#   indexes:
#     user:
#       uid:      true  # user entries will be saved as `HMSET user/uid:$uid k0 v0 k1 v1 ...`
#       email:
#         uid:    true # results in a `SET  user/email:$email/uid   $uid'  for each user added
#       name:
#         uid:    true # results in a `SET  user/name:$name/uid   $uid'   for each user added
#         # email:  true # results in a `SADD user/name:$name/email $email` for each user added

# #-----------------------------------------------------------------------------------------------------------
# @compile_description = ( me, description ) ->
#   types   = {}
#   codecs  = {}
#   pks     = {}
#   sks     = {}
#   #.........................................................................................................
#   R       =
#     '%codecs':        codecs
#     'schema':         description[ 'schema' ]
#     'indexes':        description[ 'indexes' ]
#     'primary-keys':   pks
#     'secondary-keys': sks
#   #.........................................................................................................
#   for type, type_info of description[ 'types' ]
#     continue if ( info_type = TYPES.type_of type_info ) is 'text'
#     throw new Error "expected a text or a POD, got a #{info_type}" if info_type isnt 'pod'
#     types[ type ] = codec = {}
#     codec[ 'read'  ] = type_info[ 'read'  ] ? id
#     codec[ 'write' ] = type_info[ 'write' ] ? id
#   #.........................................................................................................
#   for type, type_info of description[ 'types' ]
#     continue unless ( info_type = TYPES.type_of type_info ) is 'text'
#     codec = types[ type_info ]
#     throw new Error "unknown USERDB data type: #{rpr type}" unless codec?
#     types[ type ] = codec
#   #.........................................................................................................
#   for entry_type, type_info of description[ 'schema' ]
#     for field_name, type_name of type_info
#       codec = types[ type_name ]
#       throw new Error "unknown USERDB data type: #{rpr type}" unless codec?
#       codecs[ field_name ] = codec
#   #.........................................................................................................
#   for type_name, type_info of description[ 'indexes' ]
#     pk = null
#     for field_name, index_info of type_info
#       if index_info isnt true
#         continue if ( index_info_type = TYPES.type_of index_info ) is 'pod'
#         throw new Error "unsupported index value #{rpr index_info}" if index_info is false
#         throw new Error "unsupported index value type #{rpr index_info_type}"
#       if pk?
#         throw new Error "illegal to specify both #{rpr pk} and #{rpr field_name} as primary keys"
#       pks[ type_name ] = pk = field_name
#   #.........................................................................................................
#   throw new Error "must configure one primary key, got none" unless pk?
#   #.........................................................................................................
#   for type_name, type_info of description[ 'indexes' ]
#     for field_name, index_info of type_info
#       continue if index_info is true
#       for pk_name, index_value of index_info
#         index_value_type = TYPES.type_of index_value
#         throw new Error "unsupported index value #{rpr index_value}" if index_value is false
#         throw new Error "unsupported index value type #{rpr index_value_type}" if index_value isnt true
#         throw new Error "illegal field name #{rpr field_name}" if pk_name isnt pk
#         ( sks[ type_name ]?= {} )[ field_name ] = true
#   #.........................................................................................................
#   return R



# #-----------------------------------------------------------------------------------------------------------
# @cast_to_db = ( me, pod ) ->
#   R = {}
#   codecs = me[ 'description' ][ '%codecs' ]
#   for name, value of pod
#     R[ name ] = ( codecs[ name ]?[ 'write' ] ? identity ) value
#   return R

# #-----------------------------------------------------------------------------------------------------------
# @cast_from_db = ( me, pod ) ->
#   codecs = me[ 'description' ][ '%codecs' ]
#   warn codecs
#   for name, text of pod
#     pod[ name ] = ( codecs[ name ]?[ 'read' ] ? identity ) text
#   return pod

# #-----------------------------------------------------------------------------------------------------------
# @_build_indexes = ( me, entry, handler ) ->
#   entry       = @cast_to_db me, entry
#   type        = entry[ '~isa' ]
#   description = me[ 'description' ]
#   pk_name     = description[ 'primary-keys' ]?[ type ]
#   throw new Error "unable to find a primary key for type #{rpr type} in DB" unless pk_name?
#   pk_value    = entry[ pk_name ]
#   throw new Error "unable to find a primary key in entry #{rpr entry}" unless pk_value?
#   me[ '%self' ].hmset "#{type}/#{pk_name}:#{pk_value}", entry, ( error, response ) =>
#     return handler error if error?
#     ### TAINT use async ###
#     sks         = description[ 'secondary-keys' ]?[ type ]
#     if sks?
#       for sk_name of sks
#         sk_value  = entry[ sk_name ]
#         continue unless sk_value?
#         me[ '%self' ].set "#{type}/#{sk_name}:#{sk_value}/#{pk_name}", pk_value, redis.print
#     handler null, null if handler?

# #-----------------------------------------------------------------------------------------------------------
# ### TAINT should be using UID hint ###
# @get = ( me, uid, handler ) ->
#   ### TAINT should we demand type and ID? would work for entries of all types ###
#   type      = 'user'
#   pk_name   = 'uid'
#   pk_value  = uid
#   id        = "#{type}/#{pk_name}:#{pk_value}"
#   me[ '%self' ].hgetall id, ( error, entry ) =>
#     return handler error if error?
#     whisper '©42a', entry
#     handler null, @cast_from_db me, entry

# db = USERDB.new_db()
# db[ 'description' ] = @compile_description db, user_description

# user =
#   '~isa':   'user'
#   uid:      '3df843ac12'
#   name:     'just a user'
#   email:    'jauser@example.com'
#   password: 'secret'
#   age:      108
#   rating:   3.12
#   added:    new Date '2012-12-01T12:00:00Z'
#   asis:     42


# # warn @cast_to_db db, user
# # info @cast_from_db db, @cast_to_db db, user
# @_build_indexes db, user

# @get db, '3df843ac12', ( error, entry ) ->
#   throw error if error?
#   log TRM.lime entry

# redb = redis.createClient()
# redb.select 5, redis.print
# # TRM.dir redis
# redb = redb.multi()
# redb = redb.set 'a', 3, ( error, results ) -> if error then warn error else TRM.green results
# redb = redb.lpop 'a',   ( error, results ) -> if error then warn error else TRM.green results
# redb = redb.set 'a', 4, ( error, results ) -> if error then warn error else TRM.green results
# redb = redb.exec ( error, results ) ->
#   whisper error
#   throw error if error?
#   debug results


# # TRM.dir redb
# # redb.on "error", ( error ) ->
# #   warn "Error: #{rpr error}"

# # test = ( handler ) ->
# #   redb.set "string key", "string val", redis.print
# #   redb.hset "hash key", "hashtest 1", "some value", redis.print
# #   redb.hset [ 'uid:3425', 'foo', 42, ], redis.print
# #   redb.hset [ 'uid:3425', 'bar', 108, ], redis.print
# #   redb.hmset 'uid:3425', plotz: 'hotz', fizz: 'buzz', name: '𪜈', hazcheese: yes, cheese: null, redis.print
# #   redb.hmset [ 'uid:3425', 'patz', 'futz', ], redis.print
# #   redb.hgetall 'uid:3425', ( error, results ) ->
# #     return handler error if error?
# #     handler null, results
# #   redb.keys '*', ( error, results ) ->
# #     return handler error if error?
# #     handler null, results
# #     redb.quit()

# debug ( new Date ).toISOString()

# # test ( error, results ) ->
# #   throw error if error?
# #   info results






