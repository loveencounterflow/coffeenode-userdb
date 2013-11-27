

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
bcrypt                    = require 'bcryptjs'
### https://github.com/lowe/zxcvbn ###
### https://github.com/mintplant/node-zxcvbn ###
zxcvbn                    = require 'coffeenode-zxcvbn'
#...........................................................................................................
level_by_ttc =
  'instant':      0
  'minutes':      1
  'hours':        2
  'days':         3
  'months':       4
  'years':        5
  'centuries':    6


#-----------------------------------------------------------------------------------------------------------
@report_password_strength = ( me, password ) ->
  ### Given a password, returns a POD with an estimate on the password's strength, derived using the
  `zxcvbn` library. Example for two extreme return values:

  with password `111111111111`:

      { '~isa':           'USERDB/password-strength-report',
        'ttc.level':      0,
        'ttc':            'instant',
        'ttc.seconds':    0.006,
        'score':          0,
        'entropy':        6.907 }

  with password `$2a$10$P3WCFTtFt1/ubanXUGZ9cerQsld4YMtKQXeslq4UWaQjAfml5b5UK`:

      { '~isa':           'USERDB/password-strength-report',
        'ttc.level':      6,
        'ttc':            'centuries',
        'ttc.seconds':    2.2598125047737865e+90,
        'score':          4,
        'entropy':        314.437 }

  The easiest property to use is probably `ttc.level` (TTC: time to crack, also given in words and in
  seconds), which ranges from `0` for the insecurest (TTC: 'instant') and `6` for the securest (TTC:
  centuries) passwords. Depending on your needs, you may want to require passwords to reach at least level
  `4` (TTC: 'months') (under the assumption that the estimate is realistic).

  ###
  report  = zxcvbn password
  #.........................................................................................................
  R       =
    '~isa':         'USERDB/password-strength-report'
    'ttc.level':    level_by_ttc[ report[ 'crack_time_display' ].replace /^[^a-zA-Z]*/, '' ]
    'ttc':          report[ 'crack_time_display' ]
    'ttc.seconds':  report[ 'crack_time' ]
    'score':        report[ 'score' ]
    'entropy':      report[ 'entropy' ]
  #.........................................................................................................
  return R

#-----------------------------------------------------------------------------------------------------------
@encrypt_password = ( me, password, handler ) ->
  bcrypt.hash password, me[ 'bcrypt' ][ 'rounds' ], handler
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@test_password = ( me, password_clear, password_encrypted, handler ) ->
  bcrypt.compare password_clear, password_encrypted, handler
  #.........................................................................................................
  return null




