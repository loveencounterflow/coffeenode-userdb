(function() {
  var TEXT, TRM, TYPES, USERDB, alert, badge, db, debug, echo, help, info, log, njs_fs, njs_path, njs_url, njs_util, rpr, warn, whisper;

  njs_util = require('util');

  njs_path = require('path');

  njs_fs = require('fs');

  njs_url = require('url');

  TYPES = require('coffeenode-types');

  TEXT = require('coffeenode-text');

  TRM = require('coffeenode-trm');

  rpr = TRM.rpr.bind(TRM);

  badge = 'USERDB/examples';

  log = TRM.get_logger('plain', badge);

  info = TRM.get_logger('info', badge);

  whisper = TRM.get_logger('whisper', badge);

  alert = TRM.get_logger('alert', badge);

  debug = TRM.get_logger('debug', badge);

  warn = TRM.get_logger('warn', badge);

  help = TRM.get_logger('help', badge);

  echo = TRM.echo.bind(TRM);

  USERDB = require('./main');

  this.new_user_collection = function(me, handler) {
    var description;
    description = me['description'];
    return USERDB.new_collection(me, description, (function(_this) {
      return function(error, result) {
        if (error != null) {
          return handler(error);
        }
        log(TRM.lime("created new collection " + (rpr(me['collection-name']))));
        return handler(null, result);
      };
    })(this));
  };

  this.safe_new_user_collection = function(db, handler) {
    return USERDB.remove_collection(db, (function(_this) {
      return function(error, result) {
        if (error != null) {
          if (!/IndexMissingException/.test(error['message'])) {
            return handler(error);
          }
          info("(no collection " + (rpr(db['collection-name'])) + " found)");
        } else {
          info("(collection " + (rpr(db['collection-name'])) + " removed)");
        }
        return _this.new_user_collection(db, handler);
      };
    })(this));
  };

  this.add_sample_users = function(me) {
    var entries, entry, _i, _len, _results;
    entries = [
      {
        'name': 'demo',
        'uid': '236472',
        'password': 'demo',
        'email': 'demo@example.com'
      }, {
        'name': 'Just A. User',
        'uid': '888',
        'password': 'secret',
        'email': 'jauser@example.com'
      }, {
        'name': 'Alice',
        'uid': '889',
        'password': 'nonce',
        'email': 'alice@hotmail.com'
      }, {
        'name': 'Bob',
        'uid': '777',
        'password': 'youwontguess',
        'email': 'bobby@acme.corp'
      }, {
        'name': 'Clark',
        'uid': '123',
        'password': '*?!',
        'email': 'clark@leageofjustice.org'
      }
    ];
    _results = [];
    for (_i = 0, _len = entries.length; _i < _len; _i++) {
      entry = entries[_i];
      _results.push((function(entry) {
        return USERDB.create_user(me, entry, function(error, result) {
          if (error != null) {
            throw error;
          }
          return log(TRM.rainbow('created user:', entry));
        });
      })(entry));
    }
    return _results;
  };

  this.populate = function() {
    return this.safe_new_user_collection(db, (function(_this) {
      return function(error) {
        if (error != null) {
          throw error;
        }
        return _this.add_sample_users(db, function(error) {
          if (error != null) {
            throw error;
          }
          return log(TRM.lime("added sample users"));
        });
      };
    })(this));
  };

  this.search_something = function() {
    var query;
    query = {
      query: {
        filtered: {
          query: {
            match_all: {}
          },
          filter: {
            term: {
              _type: 'user'
            }
          }
        }
      }
    };
    return USERDB.search(db, query, function(error, results) {
      var entry, _i, _len, _results;
      if (error != null) {
        throw error;
      }
      whisper(results);
      _results = [];
      for (_i = 0, _len = entries.length; _i < _len; _i++) {
        entry = entries[_i];
        _results.push(log(TRM.rainbow(entry['_source'])));
      }
      return _results;
    });
  };

  this.analyze = function() {
    var data, options;
    options = {
      index: {
        _index: 'movies'
      }
    };
    data = {
      'password': 'secret'
    };
    return db['%self'].indices.analyze(options, data, function(error, response) {
      if (error != null) {
        throw error;
      }
      return info(response);
    });
  };

  this.show_password_strengths = function(db) {
    var password, passwords, _i, _len, _results;
    passwords = ['123', '111111111111', 'secret', 'skxawng', '$2a$10$P3WCFTtFt1/ubanXUGZ9cerQsld4YMtKQXeslq4UWaQjAfml5b5UK'];
    _results = [];
    for (_i = 0, _len = passwords.length; _i < _len; _i++) {
      password = passwords[_i];
      _results.push(log(TRM.rainbow(password, USERDB.report_password_strength(db, password))));
    }
    return _results;
  };

  this.test_password = function(db) {
    var password;
    password = '*?!';
    return USERDB.encrypt_password(db, password, function(error, password_encrypted) {
      info(password_encrypted);
      return USERDB.test_password(db, password, password_encrypted, function(error, matches) {
        return info(password, TRM.truth(matches));
      });
    });
  };

  this.get_user_by_hints = function(db) {
    var error, not_ok_uid_hints, ok_uid_hints, uid_hint, _i, _len;
    ok_uid_hints = [
      '888', ['uid', '888'], ['email', 'jauser@example.com'], {
        '~isa': 'user',
        'name': 'Just A. User',
        'uid': '888',
        'password': 'secret',
        'email': 'jauser@example.com',
        '%cache': 42
      }, {
        'name': 'Just A. User'
      }
    ];
    not_ok_uid_hints = [
      ['email'], ['email', 'foo', 'bar'], {
        '~isa': 'XXXXXXXXXX',
        'name': 'Just A. User',
        'uid': '888'
      }, {
        'name': 'Just A. User',
        'uid': '888'
      }
    ];
    for (_i = 0, _len = ok_uid_hints.length; _i < _len; _i++) {
      uid_hint = ok_uid_hints[_i];
      log();
      log(TRM.cyan(rpr(uid_hint)));
      log(TRM.yellow(USERDB._id_triplet_from_hint(db, uid_hint)));
    }
    try {
      USERDB._id_triplet_from_hint(db, not_ok_uid_hints[0]);
      throw new Error("should not have passed");
    } catch (_error) {
      error = _error;
      if (error['message'] !== "expected a list with two elements, got one with 1 elements") {
        throw error;
      }
    }
    try {
      USERDB._id_triplet_from_hint(db, not_ok_uid_hints[1]);
      throw new Error("should not have passed");
    } catch (_error) {
      error = _error;
      if (error['message'] !== "expected a list with two elements, got one with 3 elements") {
        throw error;
      }
    }
    try {
      USERDB._id_triplet_from_hint(db, not_ok_uid_hints[2]);
      throw new Error("should not have passed");
    } catch (_error) {
      error = _error;
      if (error['message'] !== "unable to get ID facet from value of type XXXXXXXXXX") {
        throw error;
      }
    }
    try {
      USERDB._id_triplet_from_hint(db, not_ok_uid_hints[3]);
      throw new Error("should not have passed");
    } catch (_error) {
      error = _error;
      if (error['message'] !== "expected a POD with a single facet, got one with 2 facets") {
        throw error;
      }
    }
  };

  this.authenticate_users = function(db) {
    var password, probe_password, probe_user, uid_hint, uid_hints_and_passwords, _i, _len, _ref, _results;
    uid_hints_and_passwords = [
      ['nosuchuser', 'not tested', false, false], [
        {
          'name': 'demo'
        }, 'demo', true, true
      ], ['888', 'secret', true, true], ['888', 'secretX', true, false], ['777', 'youwontguess', true, true], ['777', 'wrong', true, false], [['email', 'bobby@acme.corp'], '&%/%$%$%$', true, false], [['email', 'bobby@acme.corp'], 'youwontguess', true, true], [['email', 'alice@hotmail.com'], 'secretX', true, false], [['email', 'alice@hotmail.com'], 'nonce', true, true]
    ];
    _results = [];
    for (_i = 0, _len = uid_hints_and_passwords.length; _i < _len; _i++) {
      _ref = uid_hints_and_passwords[_i], uid_hint = _ref[0], password = _ref[1], probe_user = _ref[2], probe_password = _ref[3];
      _results.push((function(_this) {
        return function(uid_hint, password, probe_user, probe_password) {
          return USERDB.authenticate_user(db, uid_hint, password, function(error, user_known, password_matches) {
            return log(TRM.gold(TEXT.flush_left(uid_hint, 35)), TEXT.flush_left(TRM.truth(probe_user), 12), TEXT.flush_left(TRM.truth(user_known), 12), TEXT.flush_left(TRM.truth(user_known === probe_user), 12), TEXT.flush_left(TRM.blue(password), 30), TEXT.flush_left(TRM.truth(probe_password), 12), TEXT.flush_left(TRM.truth(password_matches), 12), TEXT.flush_left(TRM.truth(password_matches === probe_password), 12));
          });
        };
      })(this)(uid_hint, password, probe_user, probe_password));
    }
    return _results;
  };

  db = USERDB.new_db();

  this.populate(db);

}).call(this);
/****generated by https://github.com/loveencounterflow/larq****/