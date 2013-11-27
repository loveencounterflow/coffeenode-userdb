

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
log                       = TRM.get_logger 'plain', badge
info                      = TRM.get_logger 'info',  badge
whisper                   = TRM.get_logger 'whisper',  badge
alert                     = TRM.get_logger 'alert', badge
debug                     = TRM.get_logger 'debug', badge
warn                      = TRM.get_logger 'warn',  badge
help                      = TRM.get_logger 'help',  badge
echo                      = TRM.echo.bind TRM
#...........................................................................................................
mik_request               = require 'request' # https://github.com/mikeal/request
default_options           = require '../options'
#...........................................................................................................
@_esverb_by_verb =
  'search':         '_search'
  'define':         '_mapping'
  'new-collection': '' # new collection uses `put` and type mapping object
  'upsert':         '' # upserts are identified by HTTP `put` method
  'remove':         '' # removals are identified by HTTP `delete` method
#...........................................................................................................
@_http_method_by_verb =
  'search':         'post'
  'define':         'post'
  'new-collection': 'put'
  'upsert':         'put'
  'remove':         'delete'


#===========================================================================================================
# DB CREATION
#-----------------------------------------------------------------------------------------------------------
@new_db = ->
  R                 = '~isa': 'USERDB/db'
  R[ name ]         = value for name, value of default_options
  collection_name   = R[ 'collection-name' ]
  R[ 'base-route' ] = R[ 'base-route' ].replace /// ^ /* ( .*? ) /* $ ///g, '$1'
  #.........................................................................................................
  return R


#===========================================================================================================
# ENTRY TYPE DEFINITION
#-----------------------------------------------------------------------------------------------------------
### TAINT code duplication ###
@new_collection = ( me, description, handler ) ->
  #.........................................................................................................
  [ url, http_method ] = @_get_url_and_method me, null, 'new-collection'
  #.........................................................................................................
  request_options =
    method:   http_method
    url:      url
    json:     true
    body:     description
  #.........................................................................................................
  mik_request request_options, ( error, response ) =>
    return handler error if error?
    #.......................................................................................................
    result = response[ 'body' ]
    warn result
    return handler new Error     result if     ( TYPES.type_of result ) is 'text'
    return handler new Error rpr result unless result[ 'ok' ]
    handler null, result
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@remove_collection = ( me, handler ) ->
  #.........................................................................................................
  [ url, http_method ] = @_get_url_and_method me, null, 'remove'
  #.........................................................................................................
  request_options =
    method:   http_method
    url:      url
    json:     true
    body:     ''
  #.........................................................................................................
  mik_request request_options, ( error, response ) =>
    return handler error if error?
    #.......................................................................................................
    result = response[ 'body' ]
    warn result
    return handler new Error     result if     ( TYPES.type_of result ) is 'text'
    return handler new Error rpr result unless result[ 'ok' ]
    handler null, result
  #.........................................................................................................
  return null


#===========================================================================================================
# INSERTION
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


