(function() {
  var BAP, TRM, TYPES, alert, badge, create_rnd_id, debug, echo, eventually, help, info, log, njs_fs, njs_path, njs_url, njs_util, rpr, warn, whisper;

  njs_util = require('util');

  njs_path = require('path');

  njs_fs = require('fs');

  njs_url = require('url');

  BAP = require('coffeenode-bitsnpieces');

  TYPES = require('coffeenode-types');

  TRM = require('coffeenode-trm');

  rpr = TRM.rpr.bind(TRM);

  badge = 'USERDB/users';

  log = TRM.get_logger('plain', badge);

  info = TRM.get_logger('info', badge);

  whisper = TRM.get_logger('whisper', badge);

  alert = TRM.get_logger('alert', badge);

  debug = TRM.get_logger('debug', badge);

  warn = TRM.get_logger('warn', badge);

  help = TRM.get_logger('help', badge);

  echo = TRM.echo.bind(TRM);

  eventually = process.nextTick;


  /* TAINT these random seeds should probably not be hardcoded. Consider to replace them by something like
  `new Date() / somenumber` in production.
   */

  create_rnd_id = BAP.get_create_rnd_id(8327, 32);

  this.create_user = function(me, entry, handler) {

    /* Given a 'scaffold' of a user entry with fields as outlined in the `options.json` (and possibly more),
    add a user in the DB, using an encrypted version of the value in the `entry[ 'password' ]` field. The
    original scaffold entry will be modified and possibly amended with missing properties; its `~isa` field
    will unconditionally be set to `user`. When `handler` gets called, either an error has occurred, or the
    user has been saved using `USERDB.add_user`; it will not be possible to create more than a single user
    with a given unique identifier.
    
    Note: We assume here that communications with the server are made using a trusted connection, be it over,
    say, HTTP in the local, or HTTPS in the public network. It makes little sense to do cryptography in the
    client's browser using some program code that has arrived over an untrusted connection; likewise, when
    and if communication security has been established by, say, having initiated an HTTPS conversation, it
    does not make too much sense to perform encryption on the client side (apart from the fact that user
    passwords will exist in server RAM for a limited amount of time). Therefore, we assume that
    `entry[ 'password' ]` holds an unencrypted password, which we want to get rid of as soon as possible, so
    we unconditionally encrypt it. Currently, the only (recommended) way to keep a clear password is to copy
    it from `entry` before calling `USERDB.create_user`, and the only (recommended) way to *not* encrypt a
    password (or keep it from being encrypted twice) is to copy the original value and update the user entry
    in the DB when `create_user` has finished.
     */
    var password, pkn, pkn_and_skns, skns, type, _ref;
    entry['~isa'] = type = 'user';
    _ref = pkn_and_skns = this._key_names_from_type(me, type), pkn = _ref[0], skns = _ref[1];

    /* TAINT should allow client to configure ID length */

    /* TAINT using the default setup, IDs are replayable (but still depending on user inputs) */
    entry[pkn] = create_rnd_id([entry['email'], entry['name']], 12);

    /* TAINT we use constant field names here—not very abstract... */
    entry['added'] = new Date();
    password = entry['password'];
    if (password == null) {
      return handler(new Error("expected a user entry with password, found none"));
    }
    this.encrypt_password(me, password, (function(_this) {
      return function(error, password_encrypted) {
        if (error != null) {
          return handler(error);
        }
        entry['password'] = password_encrypted;
        return _this._add_user(me, entry, pkn_and_skns, handler);
      };
    })(this));
    return null;
  };

  this.add_user = function(me, entry, handler) {
    var pkn_and_skns, type;
    type = TYPES.type_of(entry);
    if (type !== 'user') {
      throw new Error("expected entry to be of type user, got a " + type);
    }
    pkn_and_skns = this._key_names_from_type(me, type);
    this._add_user(me, entry, pkn_and_skns, (function(_this) {
      return function(error, entry) {
        if (error != null) {
          return handler(error);
        }
        return handler(null, entry);
      };
    })(this));
    return null;
  };

  this._add_user = function(me, entry, pkn_and_skns, handler) {

    /* Add a user as specified by `entry` to the DB. This method does not modify `entry`, The password is
    not going to be touched—you could use this method to store an unencrypted password, so don't do that.
    Instead, use `create_user`, which is the canonical user to populate the DB with user records.
     */

    /* TAINT reduce to a single request */

    /* TAINT introduce transactions */
    return this._build_indexes(me, entry, pkn_and_skns, handler);
    return null;
  };

  this.user_exists = function(me, uid_hint, handler) {
    this.get_user(me, uid_hint, null, (function(_this) {
      return function(error, entry) {
        if (error != null) {
          return handler(error);
        }
        if (entry === null) {
          return handler(null, false);
        }
        return handler(null, true);
      };
    })(this));
    return null;
  };

  this.test_user_integrity = function(me, uid_hint, handler) {

    /* TAINT we're wrongly assuming that `uid_hint` is a UID, which is wrong, as it could also be a secondary
    key
     */
    return this.test_integrity(me, ['user', uid_hint], handler);
  };

  this.get_user = function(me, uid_hint, fallback, handler) {
    var prk, _ref;
    if (handler == null) {
      _ref = [fallback, void 0], handler = _ref[0], fallback = _ref[1];
    }

    /* TAINT we're wrongly assuming that `uid_hint` is a UID, which is wrong, as it could also be a secondary
    key
     */
    prk = this._primary_record_key_from_hint(me, ['user', uid_hint]);
    if (fallback === void 0) {
      return this.entry_from_record_key(me, prk, handler);
    }
    return this.entry_from_record_key(me, prk, fallback, handler);
  };

  this.authenticate_user = function(me, uid_hint, password, handler) {

    /* Given a user ID hint (for which see `USERDB._id_triplet_from_hint`) and a (clear) password, call
    `handler` with the result of comparing the given and the stored password for the user in question.
     */
    this.get_user(me, uid_hint, null, (function(_this) {
      return function(error, entry) {
        var password_encrypted;
        if (error != null) {
          return handler(error);
        }
        if (entry == null) {
          return handler(null, false, false);
        }
        password_encrypted = entry['password'];
        return _this.test_password(me, password, password_encrypted, function(error, password_matches) {
          if (error != null) {
            return handler(error);
          }
          return handler(null, true, password_matches);
        });
      };
    })(this));
    return null;
  };

}).call(this);
/****generated by https://github.com/loveencounterflow/larq****/