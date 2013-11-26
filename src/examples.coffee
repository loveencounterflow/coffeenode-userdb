



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
badge                     = 'USERDB/test'
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
    # USERDB.upsert me, entry, ( error, result ) ->
    #   throw error if error?
    #   log TRM.rainbow result
    do ( entry ) ->
      USERDB.user_exists me, entry[ 'uid' ], ( error, exists ) ->
        throw error if error?
        info entry[ 'uid' ], TRM.truth exists
        USERDB.add_user me, entry, ( error, result ) ->
          throw error if error?
          # log TRM.rainbow result
          USERDB.user_exists me, entry[ 'uid' ], ( error, exists ) ->
            throw error if error?
            info entry[ 'uid' ], TRM.truth exists

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

############################################################################################################
db = USERDB.new_db()

query =
  query:
    match_all: {}

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

# @populate db

bcrypt                    = require 'bcryptjs'

TRM.dir bcrypt

username = 'joe'
password = '1234'
hash = bcrypt.hashSync password, 10

info hash
log TRM.truth bcrypt.compareSync '123', hash
log TRM.truth bcrypt.compareSync '1234', hash

# info USERDB.validate_password_strength '123'

# zxcvbn = require 'zxcvbn/zxcvbn/compiled.js'
# log zxcvbn.zxcvbn '123'
# log zxcvbn.zxcvbn '$2a$10$P3WCFTtFt1/ubanXUGZ9cerQsld4YMtKQXeslq4UWaQjAfml5b5UK'

passwords = [
  '123'
  '111111111111'
  'secret'
  'skxawng'
  '$2a$10$P3WCFTtFt1/ubanXUGZ9cerQsld4YMtKQXeslq4UWaQjAfml5b5UK' ]

for password in passwords
  log TRM.rainbow password, USERDB.report_password_strength db, password



