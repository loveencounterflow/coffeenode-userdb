
############################################################################################################
njs_util                  = require 'util'
# njs_path                  = require 'path'
njs_fs                    = require 'fs'
#...........................................................................................................
BAP                       = require 'coffeenode-bitsnpieces'
TEXT                      = require 'coffeenode-text'
TYPES                     = require 'coffeenode-types'
TRM                       = require 'coffeenode-trm'
rpr                       = TRM.rpr.bind TRM
badge                     = 'test-redis'
log                       = TRM.get_logger 'plain',     badge
info                      = TRM.get_logger 'info',      badge
whisper                   = TRM.get_logger 'whisper',   badge
alert                     = TRM.get_logger 'alert',     badge
debug                     = TRM.get_logger 'debug',     badge
warn                      = TRM.get_logger 'warn',      badge
help                      = TRM.get_logger 'help',      badge
echo                      = TRM.echo.bind TRM
rainbow                   = TRM.rainbow.bind TRM
suspend                   = require 'coffeenode-suspend'
step                      = suspend.step
after                     = suspend.after
eventually                = suspend.eventually
immediately               = suspend.immediately
every                     = suspend.every
USERDB                    = require '..'
#...........................................................................................................
### https://github.com/mranney/node_redis ###
redis                     = require 'redis'
#...........................................................................................................
### https://github.com/caolan/async ###
async                     = require 'async'


#-----------------------------------------------------------------------------------------------------------
### TAINT should be using UID hint ###
@get = ( me, uid, handler ) ->
  ### TAINT should we demand type and ID? would work for entries of all types ###
  type      = 'user'
  pk_name   = 'uid'
  pk_value  = uid
  id        = "#{type}/#{pk_name}:#{pk_value}"
  me[ '%self' ].hgetall id, ( error, entry ) =>
    return handler error if error?
    whisper '©42a', entry
    handler null, @_cast_from_db me, entry


############################################################################################################

# #-----------------------------------------------------------------------------------------------------------
# @f = ( me ) ->
#   for entry in entries
#     do ( entry ) ->
#       USERDB.create_user me, entry, ( error, result ) ->
#         throw error if error?
#         log TRM.rainbow 'created user:', entry


#-----------------------------------------------------------------------------------------------------------
@get_sample_users = ( me ) ->
  return [
    'name':       'demo'
    'password':   'demo'
    'email':      'demo@example.com'
  ,
    'name':       'Just A. User'
    'password':   'secret'
    'email':      'jauser@example.com'
  ,
    'name':       'Bob'
    'password':   'youwontguess'
    'email':      'bobby@acme.corp'
  ,
    'name':       'Alice'
    'password':   'nonce'
    'email':      'alice@hotmail.com'
  ,
    'name':       'Clark'
    'password':   '*?!'
    'email':      'clark@leageofjustice.org'
  ,
  ]

#-----------------------------------------------------------------------------------------------------------
@populate = ( db, handler ) ->
  ### removes all users, puts in example users ###
  #.........................................................................................................
  USERDB.remove db, 'user/*', ( error, count ) =>
    return handler error if error?
    info "removed #{count} records from DB"
    tasks = []
    #.......................................................................................................
    for entry in @get_sample_users db
      do ( entry ) =>
        tasks.push ( done ) =>
          USERDB.create_user db, entry, done
    #.......................................................................................................
    async.parallel tasks, ( error, db_entries ) =>
      warn error if error?
      info "added #{db_entries.length} sample users to the DB"
      handler null, db_entries
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@test_get_user = ( test ) ->
  db = USERDB.new_db()
  probe = 'user/uid:17c07627d35e'
  probe = '17c07627d35e'
  probe = [ 'uid', '17c07627d35e', ]
  # probe = [ 'name', 'Alice', ]
  USERDB.dump db, '*', 'short', ( error ) =>
    throw error if error?
    USERDB.get_user db, probe, ( error, user ) =>
      throw error if error?
      debug probe, user
      USERDB.close db
      test.done()

#-----------------------------------------------------------------------------------------------------------
@test_user_integrity = ( db, handler ) ->
  uid = '281fe6cd2daf'
  USERDB.test_user_integrity db, uid, ( error, report ) =>
    return handler error if error?
    info uid, report
    USERDB.close db

#-----------------------------------------------------------------------------------------------------------
@test_user_exists = ( db, handler ) ->
  hints = [
    [ '281fe6cd2daf',                       true,   ]
    [ { 'email': 'alice@hotmail.com', },    true,   ]
    [ '281fe6cd2dafXXXXXX',                 false,  ]
    ]
  for [ hint, expectation, ] in hints
    do ( hint, expectation ) =>
      USERDB.user_exists db, hint, ( error, exists ) =>
        return handler error if error?
        info "User with hint #{rpr hint} exists:",
          TRM.truth expectation
          TRM.truth exists
          TRM.truth exists is expectation

#-----------------------------------------------------------------------------------------------------------
@test_record_and_entry_from_prk = ( db, handler ) ->
  prk = 'user/uid:281fe6cd2daf'
  USERDB.record_from_prk db, prk, ( error, record ) =>
    return handler error if error?
    debug record
    USERDB.entry_from_prk db, prk, ( error, entry ) =>
      return handler error if error?
      log TRM.gold entry
      USERDB.close db

#-----------------------------------------------------------------------------------------------------------
@test_resolve_entry_hint = ->
  log TRM.blue 'test_resolve_entry_hint'
  db = USERDB.new_db()
  good_probes = [
    #.......................................................................................................
    [ 'user/uid:17c07627d35e',                      [ 'prk', 'user/uid:17c07627d35e', 'user', 'uid',     '17c07627d35e'        ], ]
    [ [ 'user', 'uid',   '17c07627d35e',      ],    [ 'prk', 'user/uid:17c07627d35e', 'user', 'uid',     '17c07627d35e',       ], ]
    [ [ 'user', '17c07627d35e', ],                  [ 'prk', 'user/uid:17c07627d35e', 'user', 'uid',     '17c07627d35e',       ], ]
    [ [ 'user', 'some-uid' ],                       [ 'prk', 'user/uid:some-uid',     'user', 'uid',     'some-uid'            ], ]
    [ 'user/uid:2db2e22a4db5',                      [ 'prk', 'user/uid:2db2e22a4db5', 'user', 'uid',     '2db2e22a4db5'        ], ]
    #.......................................................................................................
    [ 'user/email:alice@hotmail.com/~prk',          [ 'srk', 'user/email:alice@hotmail.com/~prk', 'user', 'email',   'alice@hotmail.com'   ], ]
    [ [ 'user', 'email', 'alice@hotmail.com', ],    [ 'srk', 'user/email:alice@hotmail.com/~prk', 'user', 'email',   'alice@hotmail.com',  ], ]
    [ 'user/name:Alice/~prk',                       [ 'srk', 'user/name:Alice/~prk',              'user', 'name',    'Alice'               ], ]
    [ [ 'user', 'name',  'Alice',             ],    [ 'srk', 'user/name:Alice/~prk',              'user', 'name',    'Alice',              ], ]
    ]
  #.........................................................................................................
  bad_probes = [
    [ 'XXXXXX:Alice/~prk',  "unable to resolve hint 'XXXXXX:Alice/~prk'", ]
    [ 'some-random-text',   "unable to resolve hint \'some-random-text'"   ]
    [ 'foo/bar',            "unable to resolve hint \'foo/bar'"   ]
    ]
  #.........................................................................................................
  for [ probe, expectation, ] in good_probes
    result = USERDB.resolve_entry_hint db, probe
    info probe, expectation, result, TRM.truth BAP.equals result, expectation
  #.........................................................................................................
  for [ probe, expectation, ] in bad_probes
    try
      result = USERDB.resolve_entry_hint db, probe
    catch error
      if TYPES.isa_jsregex expectation
        info probe, expectation, ( rpr error[ 'message' ] ), TRM.truth expectation.test error[ 'message' ]
      else
        info probe, expectation, ( rpr error[ 'message' ] ), TRM.truth expectation == error[ 'message' ]
      continue
    throw new Error "#{rpr probe} should have caused an error, but gave #{rpr result}"
  #.........................................................................................................
  USERDB.close db
  test.done()

#-----------------------------------------------------------------------------------------------------------
@test_resolve_user_entry_hint = ( test ) ->
  log TRM.blue 'test_resolve_user_entry_hint'
  db = USERDB.new_db()
  good_probes = [
    #.......................................................................................................
    [ '17c07627d35e',                               [ 'prk', 'user/uid:17c07627d35e', 'user', 'uid',     '17c07627d35e'        ], ]
    [ 'some-random-text',                           [ 'prk', 'user/uid:some-random-text', 'user', 'uid',     'some-random-text'        ] ]
    [ [ 'uid',   '17c07627d35e',              ],    [ 'prk', 'user/uid:17c07627d35e', 'user', 'uid',     '17c07627d35e',       ], ]
    [ 'user/uid:2db2e22a4db5',                      [ 'prk', 'user/uid:2db2e22a4db5', 'user', 'uid',     '2db2e22a4db5'        ], ]
    #.......................................................................................................
    [ 'user/email:alice@hotmail.com/~prk',          [ 'srk', 'user/email:alice@hotmail.com/~prk', 'user', 'email',   'alice@hotmail.com'   ], ]
    [ 'user/name:Alice/~prk',                       [ 'srk', 'user/name:Alice/~prk',              'user', 'name',    'Alice'               ], ]
    [ [ 'email', 'alice@hotmail.com',         ],    [ 'srk', 'user/email:alice@hotmail.com/~prk', 'user', 'email',   'alice@hotmail.com',  ], ]
    [ [ 'name',  'Alice',                     ],    [ 'srk', 'user/name:Alice/~prk',              'user', 'name',    'Alice',              ], ]
    ]
  #.........................................................................................................
  bad_probes = [
    [ [ '17c07627d35e',                       ],    'expected a list with two elements, got one with 1 elements', ]
    ]
  #.........................................................................................................
  for [ probe, expectation, ] in good_probes
    result = USERDB.resolve_user_entry_hint db, probe
    info probe, expectation, result, TRM.truth BAP.equals result, expectation
  #.........................................................................................................
  for [ probe, expectation, ] in bad_probes
    try
      result = USERDB.resolve_user_entry_hint db, probe
    catch error
      if TYPES.isa_jsregex expectation
        info probe, expectation, ( rpr error[ 'message' ] ), TRM.truth expectation.test error[ 'message' ]
      else
        info probe, expectation, ( rpr error[ 'message' ] ), TRM.truth expectation == error[ 'message' ]
      continue
    throw new Error "#{rpr probe} should have caused an error, but gave #{rpr result}"
  #.........................................................................................................
  USERDB.close db
  test.done()

#-----------------------------------------------------------------------------------------------------------
@test_split_primary_record_key = ->
  db = USERDB.new_db()
  probes = [
    [ 'user/uid:2db2e22a4db5', [ 'user', 'uid', '2db2e22a4db5' ] ]
    ]
  #.........................................................................................................
  for [ probe, expectation, ] in probes
    result = USERDB.split_primary_record_key db, probe
    info probe, expectation, result, TRM.truth BAP.equals result, expectation
  #.........................................................................................................
  USERDB.close db


############################################################################################################
# debug USERDB._primary_and_secondary_keys_from_entry db, '~isa': 'user'
# db = USERDB.new_db()
# @populate db, ( error, results ) =>
#   throw error if error?
#   USERDB.dump db, '*', 'short', ( error ) =>
#     throw error if error?
#     log 'ok'
#     USERDB.close db

# db = USERDB.new_db()
# USERDB.dump db, '*', 'short', ( error ) =>
#   throw error if error?
#   log 'ok'
#   @test_user_exists db, ( error ) =>
#     throw error if error?
#     USERDB.close db


# USERDB.dump db, '*', 'short', ( error ) =>
#   throw error if error?
#   log 'ok'
#   @test_user_integrity db, ( error ) =>
#     throw error if error?
#     USERDB.close db

# USERDB.remove db, 'user/*', ( error, count ) ->
#   USERDB.dump db, '*'


# @test_resolve_entry_hint()
# @test_split_primary_record_key()


test = done: ->
# @test_resolve_user_entry_hint test
@test_get_user test






# Since 'user-specific' methods such as `get_user` already assume type 'user', those methods accept, in
# addition to the above, the follwoing formats as entry hints:

# * using the UID:

#   * `'17c07627d35e'`

#   * `[ 'email', 'alice@hotmail.com', ]`
#   * `[ 'name',  'Alice',             ]`
#   * `[ 'uid',   '17c07627d35e',      ]`
# * `[ '*', 'alice@hotmail.com', ]`
# * `[ '*', 'Alice', ]`

