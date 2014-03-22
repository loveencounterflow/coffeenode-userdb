

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
### https://github.com/caolan/async ###
async                     = require 'async'


#===========================================================================================================
# ENTRY INTEGRITY TESTING
#-----------------------------------------------------------------------------------------------------------
@test_integrity = ( me, id_hint, handler ) ->
  ###
  * primary record not available
  * primary record type mismatch
  * secondary records not available
  * secondary records with wrong value

  ###
  misfit  = [ 'misfit' ]
  #.........................................................................................................
  try
    [ assumed_type
      pkn
      pkv           ] = @_id_triplet_from_hint me, id_hint
    prk     = @_primary_record_key_from_id_triplet me, assumed_type, pkn, pkv
  catch error
    alert '©3e2d', error
    throw error
  #.........................................................................................................
  problems =
    'secondary-fields-missing':       []
  #.........................................................................................................
  errors =
    'primary-record-missing':         no
    'primary-record-type-mismatch':   no
    'actual-schema-missing':          no
    'secondary-records-missing':      []
    'secondary-records-wrong':        []
  #.........................................................................................................
  Z =
    '~isa':                           'USERDB/entry-integrity-report'
    'id-hint':                        id_hint
    'assumed-type':                   assumed_type
    'actual-type':                    null
    'prk':                            prk
    'error-count':                    0
    'problem-count':                  0
    'messages':                       []
    'errors':                         errors
    'problems':                       problems
    'primary-entry':                  null
    'secondary-entries':              []
  #.........................................................................................................
  @entry_from_primary_record_key me, prk, misfit, ( error, entry ) =>
    if error?
      if /^unable to find schema for type /.test error[ 'message' ]
        Z[ 'error-count' ] += 2
        Z[ 'messages' ].push error[ 'message' ]
        Z[ 'messages' ].push "unable to build PRK from unknown type"
        errors[ 'actual-schema-missing'  ] = yes
        errors[ 'primary-record-missing' ] = yes
        return handler null, Z
      return handler error
    #.......................................................................................................
    Z[ 'primary-entry' ]  = entry
    Z[ 'actual-type' ]    = actual_type = TYPES.type_of entry
    #.......................................................................................................
    if entry is misfit
      Z[ 'error-count' ] += 1
      Z[ 'messages' ].push "no entry with prk #{rpr prk}"
      errors[ 'primary-record-missing' ] = yes
    #.......................................................................................................
    else if actual_type isnt assumed_type
      Z[ 'error-count' ] += 1
      Z[ 'messages' ].push "assumed type was #{rpr assumed_type}, actual type is #{rpr actual_type}"
      errors[ 'primary-record-type-mismatch' ] = yes
    #.......................................................................................................
    ### should we check for extraneous matches ??? — would have to search all keys matching `* /~prk` ###
    ### should check for secondary entries matching actual type as well ###
    [ pkn, skns, ]  = pkn_and_skns = @_key_names_from_type me, assumed_type
    [ prk, srks, ]  = @_get_primary_and_secondary_record_keys me, entry, pkn_and_skns
    skns_and_srks   = ( [ skns[ idx ], srks[ idx ], ] for idx in [ 0 ... skns.length ] )
    #.......................................................................................................
    test = ( skn_and_srk, done ) =>
      [ skn, srk, ] = skn_and_srk
      #.....................................................................................................
      unless srk?
        Z[ 'problem-count' ] += 1
        Z[ 'messages' ].push "secondary field #{rpr skn} is missing"
        problems[ 'secondary-fields-missing' ].push skn
        return done null
      #.....................................................................................................
      else
        ### TAINT should also check for records that correspond to missing secondary fields ###
        @entry_from_primary_record_key me, srk, misfit, ( error, secondary ) =>
          return done error if error?
          #.................................................................................................
          if secondary is misfit
            Z[ 'error-count' ] += 1
            Z[ 'messages' ].push "secondary record with SRK #{rpr srk} is missing"
            errors[ 'secondary-records-missing' ].push skn
            return done null
          #.................................................................................................
          else if secondary isnt prk
            Z[ 'error-count' ] += 1
            Z[ 'messages' ].push "secondary record with SRK #{rpr srk} should be PRK #{rpr prk}, is #{rpr secondary}"
            errors[ 'secondary-records-wrong' ].push skn
          #.................................................................................................
          Z[ 'secondary-entries' ].push skn: skn, srk: srk, value: secondary
          return done null
    #.......................................................................................................
    async.each skns_and_srks, test, ( error ) =>
      return handler error if error?
      handler null, Z
  #.........................................................................................................
  return null










