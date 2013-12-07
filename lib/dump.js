(function() {
  var TEXT, TRM, alert, async, badge, debug, echo, help, info, log, rpr, warn, whisper, _shorten;

  TEXT = require('coffeenode-text');

  TRM = require('coffeenode-trm');

  rpr = TRM.rpr.bind(TRM);

  badge = 'test-redis';

  log = TRM.get_logger('plain', badge);

  info = TRM.get_logger('info', badge);

  whisper = TRM.get_logger('whisper', badge);

  alert = TRM.get_logger('alert', badge);

  debug = TRM.get_logger('debug', badge);

  warn = TRM.get_logger('warn', badge);

  help = TRM.get_logger('help', badge);

  echo = TRM.echo.bind(TRM);


  /* https://github.com/caolan/async */

  async = require('async');

  _shorten = function(text) {
    if (text.length <= 50) {
      return text;
    }
    return text.slice(0, 50).concat('…');
  };

  this.dump_keys = function(me, pattern) {
    if (pattern == null) {
      pattern = '*';
    }
    return this.get_keys(me, pattern, (function(_this) {
      return function(error, keys) {
        var key, _i, _len, _ref, _results;
        if (error != null) {
          throw error;
        }
        _ref = keys.sort();
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          key = _ref[_i];
          _results.push(info(key));
        }
        return _results;
      };
    })(this));
  };

  this.dump = function(me, pattern, format, handler) {
    var dump;
    if (pattern == null) {
      pattern = '*';
    }
    if (format == null) {
      format = 'long';
    }

    /* Simple-minded DB dump utility to quickly check DB structure. Output is meant for human readability.
    You may supply a pattern (which defaults to `*`) to control which key / value pairs will be listed. Be
    careful when using `dump` with a general pattern against a DB with many records—it could a long time
    before all entries are listed, and your Redis instance may become unresponsive to other clients for a
    certain time.
     */

    /* TAINT add `options` */

    /* TAINT add `handler` so we know when it's safe to call `USERDB.close db` */
    switch (format) {
      case 'long':
      case 'short':
        null;
        break;
      case 'keys':
        return this.dump_keys(me, pattern);
      default:
        throw new Error("unknown format name " + (rpr(format)));
    }
    dump = (function(_this) {
      return function(key, done) {
        return _this._dump(me, key, format, done);
      };
    })(this);
    this.get_keys(me, pattern, (function(_this) {
      return function(error, keys) {
        if (error != null) {
          throw error;
        }
        return async.each(keys.sort(), dump, function(error) {
          if (handler != null) {
            if (error != null) {
              return handler(error);
            }
            return handler(null);
          }
          if (error != null) {
            throw error;
          }
        });
      };
    })(this));
    return null;
  };

  this._dump = function(me, key, format, handler) {

    /* TAINT should use `record_from_prk` */
    me['%self'].type(key, (function(_this) {
      return function(error, type) {
        if (error != null) {
          return handler(error);
        }
        switch (type) {
          case 'string':
            return me['%self'].get(key, function(error, text) {
              if (format === 'short') {
                text = _shorten(text);
              }
              if (error != null) {
                throw error;
              }
              info("" + (TEXT.flush_left(key + ':', 50)) + (rpr(text)));
              return handler(null);
            });
          case 'hash':
            return me['%self'].hgetall(key, function(error, hash) {
              var name, value;
              if (error != null) {
                throw error;
              }
              if (format === 'short') {
                info("" + (TEXT.flush_left(key + ':', 50)) + (_shorten(JSON.stringify(hash))));
              } else {
                info();
                info("" + key + ":");
                for (name in hash) {
                  value = hash[name];
                  info("  " + (TEXT.flush_left(name + ':', 20)) + (rpr(value)));
                }
              }
              return handler(null);
            });
          case 'list':

            /* TAINT collect all values, then print */
            return me['%self'].llen(key, function(error, length) {
              if (error != null) {
                throw error;
              }
              return me['%self'].lrange(key, 0, length - 1, function(error, values) {
                var idx, value, _i, _len;
                if (error != null) {
                  throw error;
                }
                info();
                info("" + key + ":");
                for (idx = _i = 0, _len = values.length; _i < _len; idx = ++_i) {
                  value = values[idx];
                  info("  " + (TEXT.flush_left(idx.toString().concat(':'), 10)) + (rpr(value)));
                }
                return handler(null);
              });
            });
          case 'set':
            warn("type " + (rpr(type)) + " not implemented");
            return handler(null);
          case 'zset':
            warn("type " + (rpr(type)) + " not implemented");
            return handler(null);
          default:
            warn("type " + (rpr(type)) + " not implemented");
            return handler(null);
        }
      };
    })(this));
    return null;
  };

}).call(this);
/****generated by https://github.com/loveencounterflow/larq****/