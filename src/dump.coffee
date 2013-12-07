

############################################################################################################
TEXT                      = require 'coffeenode-text'
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
#...........................................................................................................
### https://github.com/caolan/async ###
async                     = require 'async'

#-----------------------------------------------------------------------------------------------------------
_shorten = ( text ) ->
  return text if text.length <= 50
  return text[ ... 50 ].concat '…'

#-----------------------------------------------------------------------------------------------------------
@dump_keys = ( me, pattern = '*' ) ->
  #.........................................................................................................
  @get_keys me, pattern, ( error, keys ) =>
    throw error if error?
    #.......................................................................................................
    for key in keys.sort()
      info key

#-----------------------------------------------------------------------------------------------------------
@dump = ( me, pattern = '*', format = 'long', handler ) ->
  ### Simple-minded DB dump utility to quickly check DB structure. Output is meant for human readability.
  You may supply a pattern (which defaults to `*`) to control which key / value pairs will be listed. Be
  careful when using `dump` with a general pattern against a DB with many records—it could a long time
  before all entries are listed, and your Redis instance may become unresponsive to other clients for a
  certain time. ###
  ### TAINT add `options` ###
  ### TAINT add `handler` so we know when it's safe to call `USERDB.close db` ###
  #.........................................................................................................
  switch format
    when 'long', 'short' then null
    when 'keys' then return @dump_keys me, pattern
    else throw new Error "unknown format name #{rpr format}"
  #.........................................................................................................
  dump = ( key, done ) =>
    @_dump me, key, format, done
  #.........................................................................................................
  @get_keys me, pattern, ( error, keys ) =>
    throw error if error?
    #.......................................................................................................
    async.each keys.sort(), dump, ( error ) =>
      if handler?
        return handler error if error?
        return handler null
      throw error if error?
  #.........................................................................................................
  return null

#-----------------------------------------------------------------------------------------------------------
@_dump = ( me, key, format, handler ) ->
  ### TAINT should use `record_from_prk` ###
  #.........................................................................................................
  me[ '%self' ].type key, ( error, type ) =>
    return handler error if error?
    #.......................................................................................................
    switch type
      #.....................................................................................................
      when 'string'
        me[ '%self' ].get key, ( error, text ) =>
          text = _shorten text if format is 'short'
          throw error if error?
          info "#{TEXT.flush_left key + ':', 50}#{rpr text}"
          return handler null
      #.....................................................................................................
      when 'hash'
        me[ '%self' ].hgetall key, ( error, hash ) =>
          throw error if error?
          if format is 'short'
            info "#{TEXT.flush_left key + ':', 50}#{_shorten JSON.stringify hash}"
          else
            info()
            info "#{key}:"
            for name, value of hash
              info "  #{TEXT.flush_left name + ':', 20}#{rpr value}"
          return handler null
      #.....................................................................................................
      when 'list'
        ### TAINT collect all values, then print ###
        me[ '%self' ].llen key, ( error, length ) =>
          throw error if error?
          me[ '%self' ].lrange key, 0, length - 1, ( error, values ) =>
            throw error if error?
            info()
            info "#{key}:"
            for value, idx in values
              info "  #{TEXT.flush_left ( idx.toString().concat ':' ), 10}#{rpr value}"
            return handler null
      #.....................................................................................................
      when 'set'
        warn "type #{rpr type} not implemented"
        return handler null
      #.....................................................................................................
      when 'zset'
        warn "type #{rpr type} not implemented"
        return handler null
      #.....................................................................................................
      else
        warn "type #{rpr type} not implemented"
        return handler null
  #.........................................................................................................
  return null



