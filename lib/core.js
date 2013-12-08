(function() {
  var TRM, TYPES, alert, async, badge, crumb, debug, default_options, echo, help, info, log, njs_fs, njs_path, njs_url, njs_util, redis, rpr, warn, whisper, _identity, _read_json, _write_json,
    __slice = [].slice;

  njs_util = require('util');

  njs_path = require('path');

  njs_fs = require('fs');

  njs_url = require('url');

  TYPES = require('coffeenode-types');

  TRM = require('coffeenode-trm');

  rpr = TRM.rpr.bind(TRM);

  badge = 'USERDB/core';

  log = TRM.get_logger('plain', badge);

  info = TRM.get_logger('info', badge);

  whisper = TRM.get_logger('whisper', badge);

  alert = TRM.get_logger('alert', badge);

  debug = TRM.get_logger('debug', badge);

  warn = TRM.get_logger('warn', badge);

  help = TRM.get_logger('help', badge);

  echo = TRM.echo.bind(TRM);


  /* https://github.com/mranney/node_redis */

  redis = require('redis');


  /* https://github.com/caolan/async */

  async = require('async');

  default_options = require('../options');

  this.new_db = function() {
    var R, collection_idx, name, substrate, value, _ref;
    R = {
      '~isa': 'USERDB/db'
    };
    for (name in default_options) {
      value = default_options[name];
      R[name] = value;
    }
    collection_idx = (_ref = R['collection-idx']) != null ? _ref : 0;
    R['%self'] = substrate = redis.createClient(R['port'], R['host']);

    /* TAINT may not this result in collection not already selected when function returns?
    It did seem to work in the tests, though.
     */
    substrate.select(collection_idx, (function(_this) {
      return function(error, response) {
        if (error != null) {
          throw error;
        }
      };
    })(this));
    return R;
  };

  this.close = function(me) {
    return me['%self'].quit();
  };

  _identity = function(x) {
    return x;
  };

  _read_json = function(text) {
    return JSON.parse(text);
  };

  _write_json = function(value) {
    return JSON.stringify(value);
  };

  this.codecs = {

    /* In this iteration of the UserDB / Redis interface, we do not support clientside type descriptions—only
    the types described here are legal values in entry type schemas.
     */
    date: {
      read: function(text) {
        return new Date(text);
      },
      write: function(value) {
        return value.toISOString();
      }
    },
    number: {
      read: function(text) {
        return parseFloat(text, 10);
      },
      write: function(value) {
        return value.toString();
      }
    },
    json: {
      read: _read_json,
      write: _write_json
    },
    boolean: {
      read: _read_json,
      write: _write_json
    },
    "null": {
      read: _read_json,
      write: _write_json
    },
    text: {
      read: _identity,
      write: _identity
    },
    identity: {
      read: _identity,
      write: _identity
    }
  };

  this._schema_from_entry = function(me, entry) {
    var R, schemas, type;
    schemas = me['schema'];
    type = entry['~isa'];
    if (schemas == null) {
      throw new Error("unable to find schema in db:\n" + (rpr(me)));
    }
    if (type == null) {
      throw new Error("entry has no `~isa` member:\n" + (rpr(entry)));
    }
    R = schemas[type];
    if (R == null) {
      throw new Error("unable to find schema for type " + (rpr(type)));
    }
    return R;
  };

  this._build_indexes = function(me, entry, pkn_and_skns, handler) {

    /* This method performs the lowlevel gruntwork necessary to represent an entry in the Redis DB. In
    particular, it issues a HMSET user/uid:$uid k0 v0 k1 v1 ...` command to save the entry as a Redis
    hash; then, it issues commands like `SET user/email:$email/uid $uid` and others (as configured in the data
    type description) to make the entry retrievable using secondary unique keys (such as email address).
     */
    var add, pkn, prk, record, skns, srks, type, _ref;
    pkn = pkn_and_skns[0], skns = pkn_and_skns[1];
    _ref = this._get_primary_and_secondary_record_keys(me, entry, pkn_and_skns), prk = _ref[0], srks = _ref[1];
    entry['~prk'] = prk;
    record = this._cast_to_db(me, prk, entry);
    type = record['~isa'];
    add = function(srk_and_prk, done) {
      var srk;
      srk = srk_and_prk[0], prk = srk_and_prk[1];
      return me['%self'].set(srk, prk, done);
    };
    me['%self'].hmset(prk, record, (function(_this) {
      return function(error, response) {
        var srk, srks_and_prks;
        if (error != null) {
          return handler(error);
        }
        if (!(srks.length > 0)) {
          return handler(null, record);
        }
        srks_and_prks = (function() {
          var _i, _len, _results;
          _results = [];
          for (_i = 0, _len = srks.length; _i < _len; _i++) {
            srk = srks[_i];
            if (srk != null) {
              _results.push([srk, prk]);
            }
          }
          return _results;
        })();
        return async.each(srks_and_prks, add, function(error) {
          if (error != null) {
            return handler(error);
          }
          return handler(null, record);
        });
      };
    })(this));
    return null;
  };

  this.remove = function(me, pattern, handler) {

    /* Remove all records whose key matches `pattern` (whose semantics are the same as in `get_keys`). */

    /* TAINT should use `multi` to prevent race conditions */

    /* TAINT consider to batch keys for less requests */
    var Z, remove;
    Z = 0;
    remove = (function(_this) {
      return function(key, done) {
        return me['%self'].del(key, function(error, count) {
          if (error != null) {
            return done(error);
          }
          Z += count;
          return done(null, Z);
        });
      };
    })(this);
    this.get_keys(me, pattern, (function(_this) {
      return function(error, keys) {
        if (error != null) {
          return handler(error);
        }
        return async.each(keys, remove, function(error, results) {
          if (error != null) {
            return handler(error);
          }
          return handler(null, Z);
        });
      };
    })(this));
    return null;
  };

  this.walk_keys = function(me, pattern, handler) {

    /* Like `get_keys`, but calling `handler` once for each key found, and once with `null` after the last
    key.
     */

    /* TAINT we're using the Redis < 2.8 `keys` command here, as the better Redis >= 2.8 `scan` command
    family is not yet available. Be aware that a Redis instance with lots of keys may become temporarily
    unavailable for other clients whenever `USERDB.walk_keys` or `get_keys` are used in their present
    implementation.
     */
    return me['%self'].keys(pattern, (function(_this) {
      return function(error, response) {
        var key, _i, _len;
        if (error != null) {
          return handler(error);
        }
        for (_i = 0, _len = response.length; _i < _len; _i++) {
          key = response[_i];
          handler(null, key);
        }
        return handler(null, null);
      };
    })(this));
  };

  this.get_keys = function(me, pattern, handler) {

    /* Given a `pattern`, yield the matching keys in the DB. Glob-style patterns are supported; as per the
    Redis documentation:
    
    *  `h?llo` matches `hello`, `hallo` and `hxllo`
    *  `h*llo` matches `hllo` and `heeeello`
    *  `h[ae]llo` matches `hello` and `hallo`, but not `hillo`
    *  Use `\` to escape special characters if you want to match them verbatim.
     */

    /* TAINT we're using the Redis < 2.8 `keys` command here, as the better Redis >= 2.8 `scan` command
    family is not yet available. Be aware that a Redis instance with lots of keys may become temporarily
    unavailable for other clients whenever `USERDB.walk_keys` or `get_keys` are used in their present
    implementation.
     */
    return me['%self'].keys(pattern, handler);
  };

  this.entry_from_record_key = function(me, prk, fallback, handler) {

    /* TAINT implement type casting for all Redis types */
    var _ref;
    if (handler == null) {
      _ref = [void 0, fallback], fallback = _ref[0], handler = _ref[1];
    }
    this.record_from_prk(me, prk, (function(_this) {
      return function(error, value) {
        if (error != null) {
          if (fallback === void 0) {
            return handler(error);
          }
          if (/^nothing found for primary record key /.test(error['message'])) {
            return handler(null, fallback);
          }
          return handler(error);
        }
        if (TYPES.isa_pod(value)) {
          try {
            return handler(null, _this._cast_from_db(me, value['~prk'], value));
          } catch (_error) {
            error = _error;
            return handler(error);
          }
        }
        return handler(null, value);
      };
    })(this));
    return null;
  };

  this.record_from_prk = function(me, prk, fallback, handler) {
    var _ref;
    if (handler == null) {
      _ref = [void 0, fallback], fallback = _ref[0], handler = _ref[1];
    }
    me['%self'].type(prk, (function(_this) {
      return function(error, type) {
        if (error != null) {
          return handler(error);
        }
        switch (type) {
          case 'none':
            if (fallback !== void 0) {
              return handler(null, fallback);
            }
            return handler(new Error("nothing found for primary record key " + (rpr(prk))));
          case 'string':
            return me['%self'].get(prk, function(error, text) {
              if (error != null) {
                throw error;
              }
              return handler(null, text);
            });
          case 'hash':
            return me['%self'].hgetall(prk, function(error, hash) {
              return handler(null, hash);
            });
          case 'list':
            return me['%self'].llen(prk, function(error, length) {
              if (error != null) {
                throw error;
              }
              return me['%self'].lrange(prk, 0, length - 1, function(error, values) {
                return handler(null, values);
              });
            });
          case 'set':
            return handler(new Error("type " + (rpr(type)) + " not implemented"));
          case 'zset':
            return handler(new Error("type " + (rpr(type)) + " not implemented"));
          default:
            return handler(new Error("type " + (rpr(type)) + " not implemented"));
        }
      };
    })(this));
    return null;
  };

  this._primary_record_key_from_hint = function(me, id_hint) {
    return this._primary_record_key_from_id_triplet(me, this.resolve_entry_hint(me, id_hint));
  };

  this.primary_record_key_from_id_triplet = function() {
    var P, arity, me;
    me = arguments[0], P = 2 <= arguments.length ? __slice.call(arguments, 1) : [];

    /* TAINT shares code with `_secondary_record_key_from_id_triplet` */
    switch (arity = P.length + 1) {
      case 2:
        P = P[0];
        break;
      case 4:
        null;
        break;
      default:
        throw new Error("expected two or four arguments, got " + arity);
    }
    if (P.length !== 3) {
      throw new Error("expected list with three elements, got one with " + P.length);
    }
    return this._primary_record_key_from_id_triplet.apply(this, [me].concat(__slice.call(P)));
  };

  this.secondary_record_key_from_id_triplet = function() {
    var P, arity, me;
    me = arguments[0], P = 2 <= arguments.length ? __slice.call(arguments, 1) : [];

    /* TAINT shares code with `_primary_record_key_from_id_triplet` */
    switch (arity = P.length + 1) {
      case 2:
        P = P[0];
        break;
      case 4:
        null;
        break;
      default:
        throw new Error("expected two or four arguments, got " + arity);
    }
    if (P.length !== 3) {
      throw new Error("expected list with three elements, got one with " + P.length);
    }
    return this._secondary_record_key_from_id_triplet.apply(this, [me].concat(__slice.call(P)));
  };

  this._primary_record_key_from_id_triplet = function(me, type, pkn, pkv) {
    var pkvx;
    pkvx = this.escape_key_value_crumb(me, pkv);
    return "" + type + "/" + pkn + ":" + pkvx;
  };

  this._secondary_record_key_from_id_triplet = function(me, type, skn, skv) {
    var skvx;
    skvx = this.escape_key_value_crumb(me, skv);
    return "" + type + "/" + skn + ":" + skvx + "/~prk";
  };

  this._key_names_from_type = function(me, type) {
    var index_description, pkn, skns, _ref;
    index_description = this._index_description_from_type(me, type);
    pkn = index_description['primary-key'];
    if (pkn == null) {
      throw new Error("no primary key in index description for type " + (rpr(type)));
    }
    skns = (_ref = index_description['secondary-keys']) != null ? _ref : [];
    return [pkn, skns];
  };

  this._secondary_key_names_from_type = function(me, type) {
    var R, _ref;
    R = (_ref = (this._index_description_from_type(me, type))['secondary-keys']) != null ? _ref : [];
    return R;
  };

  this._primary_key_name_from_type = function(me, type) {
    var R;
    R = (this._index_description_from_type(me, type))['primary-key'];
    if (R == null) {
      throw new Error("type " + (rpr(type)) + " has no primary key in index description");
    }
    return R;
  };

  this._index_description_from_type = function(me, type) {
    var R, indexes;
    indexes = me['indexes'];
    if (indexes == null) {
      throw new Error("unable to find indexes in db:\n" + (rpr(db)));
    }
    R = indexes[type];
    if (R == null) {
      throw new Error("type " + (rpr(type)) + " has no index description in\n" + (rpr(indexes)));
    }
    return R;
  };

  this._get_primary_and_secondary_record_keys = function(me, entry, pkn_and_skns) {
    var R, pkn, pkv, prk, skn, skns, skv, srk, srks, type, _i, _len;
    pkn = pkn_and_skns[0], skns = pkn_and_skns[1];
    srks = [];
    type = entry['~isa'];
    pkv = entry[pkn];
    if (pkv == null) {
      throw new Error("unable to find a primary key (" + (rpr(pk_name)) + ") in entry " + (rpr(entry)));
    }
    prk = this._primary_record_key_from_id_triplet(me, type, pkn, pkv);
    R = [prk, srks];
    for (_i = 0, _len = skns.length; _i < _len; _i++) {
      skn = skns[_i];
      if ((skv = entry[skn]) != null) {
        srk = this._secondary_record_key_from_id_triplet(me, type, skn, skv);
        srks.push(srk);
      } else {
        srks.push(void 0);
      }
    }
    return R;
  };

  this.resolve_entry_hint = function(me, entry_hint) {

    /* Given a valid 'hint' for an entry (a piece of data suitable to identify a certain record or entry in
      the DB), return a quintuplet with the following values:
    
          [ hint-type, psrk, type, pskn, pskv, ]
    
      where `hint-type` is either `'prk'` (indicating the hint led to a Primary Key) or `'srk'` (indicating
      the hint led to a Secondary Key), `psrk` is either the Primary or a Secondary Record Key, `type` is the
      entry type, and `pskn` / `pskv` are the primary or secondary field's name and value, as the case may be.
    
      For example, giving `'user/uid:17c07627d35e'` will return
    
          [ 'prk', 'user/uid:17c07627d35e', 'user', 'uid', '17c07627d35e', ]
    
      which indicates that what we have is a Primary Record Key whose value is repeated in the second element;
      the last three elements (the 'ID triplet') we can glean that we should look for an entry of type 'user'
      whose field 'uid' has value `17c07627d35e` to locate the entry hinted at. Similarly, passing
      `[ 'user', 'email', 'alice@hotmail.com', ]` will result in
    
          [ 'srk', 'user/email:alice@hotmail.com/~prk', 'user', 'email',   'alice@hotmail.com',  ]
    
      which shows that we have to look for a secondary key `user/email:alice@hotmail.com/~prk` to retrieve
      the PRK of a user whose `email` field is set to `alice@hotmail.com`.
    
      Both primary and secondary entry hints may be given as strings or lists; the idea of the method is to
      fill in the missing pieces of the equation so that the result covers everything the caller has to know
      in order to start a meaningful request for a single entry against the DB.
    
      Hints are accepted in a number of formats:
    
      * **using an existing (partial) entry**: **NOT YET IMPLEMENTED** you may pass in a full, valid object
        representing an entry; in this case, you will get back a quintuplet whose first element is `'prk'`.
        It is also possible to pass in a *partial* entry, provided that both its `~isa` field is set to the
        desired type and either the Primary Record field or one of the Secondary Record fields are set; the
        return value will then preferrably indicate a PRK, or, if that does not work, one of the SRKs.
    
      * **using the PRK or an SRK**:
    
        * `'user/uid:17c07627d35e'`
        * `'user/email:alice@hotmail.com/~prk'`
        * `'user/name:Alice/~prk'`
    
        Values given must be syntactically valid (i.e. they must parse when passed into one of the
        `split_*_record_key` methods).
    
      * **using triplets spelling out type, field name, and field value**:
    
        * `[ 'user', 'uid',   '17c07627d35e',      ]`
        * `[ 'user', 'email', 'alice@hotmail.com', ]`
        * `[ 'user', 'name',  'Alice',             ]`
    
        Triplets must start with the entry type and continue with the name of a Primary or Secondary Key
        field and value.
    
      * **using a type / PKV pair**:
    
        * `[ 'user', '17c07627d35e', ]`
     */
    var R, length, pkn, pkv, prk, pskn, pskv, skns, srk, type, type_of_hint, _ref, _ref1;
    switch (type_of_hint = TYPES.type_of(entry_hint)) {
      case 'list':
        switch ((length = entry_hint.length)) {
          case 2:
            type = entry_hint[0], pkv = entry_hint[1];
            _ref = this._key_names_from_type(me, type), pkn = _ref[0], skns = _ref[1];
            prk = this._primary_record_key_from_id_triplet(me, type, pkn, pkv);
            return ['prk', prk, type, pkn, pkv];
          case 3:
            type = entry_hint[0], pskn = entry_hint[1], pskv = entry_hint[2];
            _ref1 = this._key_names_from_type(me, type), pkn = _ref1[0], skns = _ref1[1];
            if (pskn === pkn) {
              prk = this._primary_record_key_from_id_triplet(me, type, pskn, pskv);
              return ['prk', prk, type, pskn, pskv];
            } else if (skns.indexOf(pskn > -1)) {
              srk = this._secondary_record_key_from_id_triplet(me, type, pskn, pskv);
              return ['srk', srk, type, pskn, pskv];
            }
            throw new Error("hint has PKN or SKN " + (rpr(pskn)) + ", but schema has " + type + ": " + [pkn, skns]);
        }
        throw new Error("expected a list with two or three elements, got one with " + length + " elements");
        break;
      case 'text':

        /* When the hint is a text, it is understood as a Primary or Secondary Record Key: */
        if ((R = this.analyze_record_key(me, entry_hint, null)) != null) {
          return R;
        }
        throw new Error("unable to resolve hint " + (rpr(entry_hint)));
    }
    throw new Error("unable to resolve hint of type " + type_of_hint);
  };

  crumb = '([^/:\\s]+)';

  this._prk_matcher = RegExp("^" + crumb + "/" + crumb + ":" + crumb + "$");

  this._srk_matcher = RegExp("^" + crumb + "/" + crumb + ":" + crumb + "/~prk$");

  this.split_record_key = function(me, rk, fallback) {
    var R;
    if ((R = this.split_primary_record_key(me, rk, null)) != null) {
      return R;
    }
    if ((R = this.split_secondary_record_key(me, rk, null)) != null) {
      return R;
    }
    if (fallback !== void 0) {
      return fallback;
    }
    throw new Error("illegal PRK / SRK: " + (rpr(rk)));
  };

  this.split_primary_record_key = function(me, prk, fallback) {
    var match;
    match = prk.match(this._prk_matcher);
    if (match == null) {
      if (fallback !== void 0) {
        return fallback;
      }
      throw new Error("illegal PRK: " + (rpr(prk)));
    }
    return match.slice(1, 4);
  };

  this.split_secondary_record_key = function(me, srk, fallback) {
    var match;
    match = srk.match(this._srk_matcher);
    if (match == null) {
      if (fallback !== void 0) {
        return fallback;
      }
      throw new Error("illegal SRK: " + (rpr(srk)));
    }
    return match.slice(1, 4);
  };

  this.analyze_record_key = function(me, rk, fallback) {
    var R;
    if ((R = this.analyze_primary_record_key(me, rk, null)) != null) {
      return R;
    }
    if ((R = this.analyze_secondary_record_key(me, rk, null)) != null) {
      return R;
    }
    if (fallback !== void 0) {
      return fallback;
    }
    throw new Error("illegal PRK / SRK: " + (rpr(rk)));
  };

  this.analyze_primary_record_key = function(me, prk, fallback) {
    var R;
    R = this.split_primary_record_key(me, prk, null);
    if (R == null) {
      if (fallback !== void 0) {
        return fallback;
      }
      throw new Error("illegal PRK: " + (rpr(prk)));
    }
    return ['prk', prk].concat(__slice.call(R));
  };

  this.analyze_secondary_record_key = function(me, srk, fallback) {
    var R;
    R = this.split_secondary_record_key(me, srk, null);
    if (R == null) {
      if (fallback !== void 0) {
        return fallback;
      }
      throw new Error("illegal SRK: " + (rpr(srk)));
    }
    return ['srk', srk].concat(__slice.call(R));
  };

  this.escape_key_value_crumb = function(me, text) {

    /* Given a text that is intended to be used inside a Redis structured (URL-like) key, return it escaped
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
     */
    var R;
    R = text;
    R = R.replace(/\+/g, '++');
    R = R.replace(/\x20/g, '+_');
    R = R.replace(/\//g, '+,');
    R = R.replace(/\:/g, '+.');
    return R;
  };

  this.unescape_key_value_crumb = function(me, text) {

    /* Reverse the effect of applying `escape_key_value_crumb`. */
    var R;
    R = text;
    R = R.replace(/\+_/g, ' ');
    R = R.replace(/\+,/g, '/');
    R = R.replace(/\+\./g, ':');
    R = R.replace(/\+\+/g, '+');
    return R;
  };

  this._cast_to_db = function(me, prk, entry) {

    /* Given an entry, return a new POD with all values cast to DB strings as specified in that type's
    description.
     */

    /* TAINT implement casting for other entry types; needs prk for that */
    var R, field_name, schema, value, _ref, _ref1;
    R = {};
    schema = this._schema_from_entry(me, entry);
    for (field_name in entry) {
      value = entry[field_name];
      R[field_name] = ((_ref = this.codecs[(_ref1 = schema[field_name]) != null ? _ref1 : 'identity']) != null ? _ref['write'] : void 0)(value);
    }
    return R;
  };

  this._cast_from_db = function(me, prk, record) {

    /* Given an record coming from the DB with all values as strings, apply the decoders as specified in that
    types's description and return the entry.
     */

    /* TAINT implement casting for other entry types; needs prk for that */
    var field_name, schema, text, _ref, _ref1;
    schema = this._schema_from_entry(me, record);
    for (field_name in record) {
      text = record[field_name];
      record[field_name] = ((_ref = this.codecs[(_ref1 = schema[field_name]) != null ? _ref1 : 'identity']) != null ? _ref['read'] : void 0)(text);
    }
    return record;
  };

}).call(this);
/****generated by https://github.com/loveencounterflow/larq****/