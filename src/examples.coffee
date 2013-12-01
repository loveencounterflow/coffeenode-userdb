



############################################################################################################
# ERROR                     = require 'coffeenode-stacktrace'
njs_util                  = require 'util'
njs_path                  = require 'path'
njs_fs                    = require 'fs'
njs_url                   = require 'url'
#...........................................................................................................
TYPES                     = require 'coffeenode-types'
TEXT                      = require 'coffeenode-text'
TRM                       = require 'coffeenode-trm'
rpr                       = TRM.rpr.bind TRM
badge                     = 'USERDB/examples'
log                       = TRM.get_logger 'plain',   badge
info                      = TRM.get_logger 'info',    badge
whisper                   = TRM.get_logger 'whisper', badge
alert                     = TRM.get_logger 'alert',   badge
debug                     = TRM.get_logger 'debug',   badge
warn                      = TRM.get_logger 'warn',    badge
help                      = TRM.get_logger 'help',    badge
echo                      = TRM.echo.bind TRM
USERDB                    = require './main'


#-----------------------------------------------------------------------------------------------------------
@new_user_collection = ( me, handler ) ->
  description = me[ 'description' ]
  #.........................................................................................................
  USERDB.new_collection me, description, ( error, result ) =>
    return handler error if error?
    log TRM.lime "created new collection #{rpr me[ 'collection-name' ]}"
    handler null, result

#-----------------------------------------------------------------------------------------------------------
@safe_new_user_collection = ( db, handler ) ->
  USERDB.remove_collection db, ( error, result ) =>
    if error?
      return handler error unless /IndexMissingException/.test error[ 'message' ]
      info "(no collection #{rpr db[ 'collection-name' ]} found)"
    else
      info "(collection #{rpr db[ 'collection-name' ]} removed)"
    @new_user_collection db, handler

#-----------------------------------------------------------------------------------------------------------
@add_sample_users = ( me ) ->
  entries = [
    '~isa':       'user'
    'name':       'demo'
    'uid':        '236472'
    'password':   'demo'
    'email':      'demo@example.com'
  ,
    '~isa':       'user'
    'name':       'Just A. User'
    'uid':        '888'
    'password':   'secret'
    'email':      'jauser@example.com'
  ,
    '~isa':       'user'
    'name':       'Alice'
    'uid':        '889'
    'password':   'nonce'
    'email':      'alice@hotmail.com'
  ,
    '~isa':       'user'
    'name':       'Bob'
    'uid':        '777'
    'password':   'youwontguess'
    'email':      'bobby@acme.corp'
  ,
    '~isa':       'user'
    'name':       'Clark'
    'uid':        '123'
    'password':   '*?!'
    'email':      'clark@leageofjustice.org'
  ,
  ]
  for entry in entries
    do ( entry ) ->
      USERDB.create_user me, entry, ( error, result ) ->
        throw error if error?
        log TRM.rainbow 'created user:', entry

#-----------------------------------------------------------------------------------------------------------
@populate = ->
  @safe_new_user_collection db, ( error ) =>
    throw error if error?
    @add_sample_users db, ( error ) =>
      throw error if error?
      log TRM.lime "added sample users"

#-----------------------------------------------------------------------------------------------------------
@search_something = ->
  query =
      query:
        filtered:
          query:
            match_all: {}
          filter:
            term:
              _type: 'user'
  #.........................................................................................................
  USERDB.search db, query, ( error, results ) ->
    throw error if error?
    whisper results
    for entry in entries
      log TRM.rainbow entry[ '_source' ]

#-----------------------------------------------------------------------------------------------------------
@analyze = ->
  options =
    index:
      _index:   'movies'
  data =
    # '~isa':       'user'
    # 'name':       'Just A. User'
    # 'uid':        '888'
    'password':   'secret'
    # 'email':      'jauser@example.com'

  db['%self'].indices.analyze options, data, ( error, response ) ->
    throw error if error?
    info response


# USERDB.search db, query, ( error, results ) ->
#   throw error if error?
#   log TRM.rainbow results

# USERDB.search_entries db, query, ( error, entries ) ->
#   throw error if error?
#   log TRM.rainbow entries

# USERDB.get db, 'uid', '889', null, ( error, entry ) ->
#   throw error if error?
#   log TRM.rainbow entry

# USERDB.get_user db, '888', null, ( error, entry ) ->
#   throw error if error?
#   log TRM.rainbow entry

# USERDB.user_exists db, '888', ( error, exists ) ->
#   throw error if error?
#   log TRM.truth exists


# username = 'joe'
# password = '1234'
# # hash = bcrypt.hashSync password, 10
# USERDB.encrypt_password db, password, ( error, password_encrypted ) ->
#   throw error if error?
#   info '©33q', password_encrypted
#   USERDB.test_password db,  '123', password_encrypted, ( error, matches ) ->
#     info '123', TRM.truth matches
#   USERDB.test_password db,  '1234', password_encrypted, ( error, matches ) ->
#     info '1234', TRM.truth matches

#-----------------------------------------------------------------------------------------------------------
@show_password_strengths = ( db ) ->
  passwords = [
    '123'
    '111111111111'
    'secret'
    'skxawng'
    '$2a$10$P3WCFTtFt1/ubanXUGZ9cerQsld4YMtKQXeslq4UWaQjAfml5b5UK' ]

  for password in passwords
    log TRM.rainbow password, USERDB.report_password_strength db, password

#-----------------------------------------------------------------------------------------------------------
@test_password = ( db ) ->
  password = '*?!'
  USERDB.encrypt_password db, password, ( error, password_encrypted ) ->
    info password_encrypted
    USERDB.test_password db, password, password_encrypted, ( error, matches ) ->
      info password, TRM.truth matches

#-----------------------------------------------------------------------------------------------------------
@get_user_by_hints = ( db ) ->
  #.........................................................................................................
  ok_uid_hints = [
    '888'
    [ 'uid', '888', ]
    [ 'email', 'jauser@example.com', ]
  ,
    '~isa':       'user'
    'name':       'Just A. User'
    'uid':        '888'
    'password':   'secret'
    'email':      'jauser@example.com'
    '%cache':     42
  ,
    'name':       'Just A. User'

    ]
  #.........................................................................................................
  not_ok_uid_hints = [

    [ 'email', ]
    [ 'email', 'foo', 'bar', ]
  ,
    '~isa':       'XXXXXXXXXX'
    'name':       'Just A. User'
    'uid':        '888'
  ,
    'name':       'Just A. User'
    'uid':        '888'
    ]
  #.........................................................................................................
  for uid_hint in ok_uid_hints
    log()
    log TRM.cyan rpr uid_hint
    log TRM.yellow USERDB._id_facet_from_hint db, uid_hint
  #.........................................................................................................
  try
    USERDB._id_facet_from_hint db, not_ok_uid_hints[ 0 ]
    throw new Error "should not have passed"
  catch error
    throw error unless error[ 'message' ] is "expected a list with two elements, got one with 1 elements"
  #.........................................................................................................
  try
    USERDB._id_facet_from_hint db, not_ok_uid_hints[ 1 ]
    throw new Error "should not have passed"
  catch error
    throw error unless error[ 'message' ] is "expected a list with two elements, got one with 3 elements"
  #.........................................................................................................
  try
    USERDB._id_facet_from_hint db, not_ok_uid_hints[ 2 ]
    throw new Error "should not have passed"
  catch error
    throw error unless error[ 'message' ] is "unable to get ID facet from value of type XXXXXXXXXX"
  #.........................................................................................................
  try
    USERDB._id_facet_from_hint db, not_ok_uid_hints[ 3 ]
    throw new Error "should not have passed"
  catch error
    throw error unless error[ 'message' ] is "expected a POD with a single facet, got one with 2 facets"

#-----------------------------------------------------------------------------------------------------------
@authenticate_users = ( db ) ->
  uid_hints_and_passwords = [
    [   'nosuchuser',                   'not tested',     false,  false,   ]
    [   'name': 'demo',                 'demo',           true,   true,   ]
    [   '888',                          'secret',         true,   true,   ]
    [   '888',                          'secretX',        true,   false,  ]
    [   '777',                          'youwontguess',   true,   true,   ]
    [   '777',                          'wrong',          true,   false,  ]
    [ [ 'email', 'bobby@acme.corp'   ], '&%/%$%$%$',      true,   false,  ]
    [ [ 'email', 'bobby@acme.corp'   ], 'youwontguess',   true,   true,  ]
    [ [ 'email', 'alice@hotmail.com' ], 'secretX',        true,   false,  ]
    [ [ 'email', 'alice@hotmail.com' ], 'nonce',          true,   true,   ]
    ]
  #.........................................................................................................
  for [ uid_hint, password, probe_user, probe_password ] in uid_hints_and_passwords
    do ( uid_hint, password, probe_user, probe_password ) =>
      USERDB.authenticate_user db, uid_hint, password, ( error, user_known, password_matches ) =>
        # debug arguments
        log ( TRM.gold TEXT.flush_left uid_hint, 35 ),
          TEXT.flush_left ( TRM.truth probe_user                         ), 12
          TEXT.flush_left ( TRM.truth user_known                         ), 12
          TEXT.flush_left ( TRM.truth user_known is probe_user           ), 12
          TEXT.flush_left ( TRM.blue password ), 30
          TEXT.flush_left ( TRM.truth probe_password                     ), 12
          TEXT.flush_left ( TRM.truth password_matches                   ), 12
          TEXT.flush_left ( TRM.truth password_matches is probe_password ), 12


############################################################################################################
db = USERDB.new_db()

# query =
#   query:
#     match_all: {}

# @populate db
# @get_user_by_hints db
@authenticate_users db





# echo name for name of USERDB

