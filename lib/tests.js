(function() {
  var BAP, TEXT, TRM, TYPES, USERDB, after, alert, async, badge, debug, echo, eventually, every, help, immediately, info, log, njs_fs, njs_util, rainbow, redis, rpr, step, suspend, warn, whisper;

  njs_util = require('util');

  njs_fs = require('fs');

  BAP = require('coffeenode-bitsnpieces');

  TEXT = require('coffeenode-text');

  TYPES = require('coffeenode-types');

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

  rainbow = TRM.rainbow.bind(TRM);

  suspend = require('coffeenode-suspend');

  step = suspend.step;

  after = suspend.after;

  eventually = suspend.eventually;

  immediately = suspend.immediately;

  every = suspend.every;

  USERDB = require('coffeenode-userdb');


  /* https://github.com/mranney/node_redis */

  redis = require('redis');


  /* https://github.com/caolan/async */

  async = require('async');


  /* TAINT should be using UID hint */

  this.get = function(me, uid, handler) {

    /* TAINT should we demand type and ID? would work for entries of all types */
    var id, pk_name, pk_value, type;
    type = 'user';
    pk_name = 'uid';
    pk_value = uid;
    id = "" + type + "/" + pk_name + ":" + pk_value;
    return me['%self'].hgetall(id, (function(_this) {
      return function(error, entry) {
        if (error != null) {
          return handler(error);
        }
        whisper('©42a', entry);
        return handler(null, _this._cast_from_db(me, entry));
      };
    })(this));
  };

  this.get_sample_users = function(me) {
    return [
      {
        'name': 'demo',
        'password': 'demo',
        'email': 'demo@example.com'
      }, {
        'name': 'Just A. User',
        'password': 'secret',
        'email': 'jauser@example.com'
      }, {
        'name': 'Bob',
        'password': 'youwontguess',
        'email': 'bobby@acme.corp'
      }, {
        'name': 'Alice',
        'password': 'nonce',
        'email': 'alice@hotmail.com'
      }, {
        'name': 'Clark',
        'password': '*?!',
        'email': 'clark@leageofjustice.org'
      }
    ];
  };

  this.populate = function(db, handler) {

    /* removes all users, puts in example users */
    USERDB.remove(db, 'user/*', (function(_this) {
      return function(error, count) {
        var entry, tasks, _fn, _i, _len, _ref;
        if (error != null) {
          return handler(error);
        }
        info("removed " + count + " records from DB");
        tasks = [];
        _ref = _this.get_sample_users(db);
        _fn = function(entry) {
          return tasks.push(function(done) {
            return USERDB.create_user(db, entry, done);
          });
        };
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          entry = _ref[_i];
          _fn(entry);
        }
        return async.parallel(tasks, function(error, db_entries) {
          if (error != null) {
            warn(error);
          }
          info("added " + db_entries.length + " sample users to the DB");
          return handler(null, db_entries);
        });
      };
    })(this));
    return null;
  };

  this.test_get_user = function(db, handler) {
    var uid;
    uid = '281fe6cd2daf';
    return USERDB.get_user(db, uid, (function(_this) {
      return function(error, user) {
        if (error != null) {
          return handler(error);
        }
        return debug(uid, user);
      };
    })(this));
  };

  this.test_user_integrity = function(db, handler) {
    var uid;
    uid = '281fe6cd2daf';
    return USERDB.test_user_integrity(db, uid, (function(_this) {
      return function(error, report) {
        if (error != null) {
          return handler(error);
        }
        info(uid, report);
        return USERDB.close(db);
      };
    })(this));
  };

  this.test_user_exists = function(db, handler) {
    var expectation, hint, hints, _i, _len, _ref, _results;
    hints = [
      ['281fe6cd2daf', true], [
        {
          'email': 'alice@hotmail.com'
        }, true
      ], ['281fe6cd2dafXXXXXX', false]
    ];
    _results = [];
    for (_i = 0, _len = hints.length; _i < _len; _i++) {
      _ref = hints[_i], hint = _ref[0], expectation = _ref[1];
      _results.push((function(_this) {
        return function(hint, expectation) {
          return USERDB.user_exists(db, hint, function(error, exists) {
            if (error != null) {
              return handler(error);
            }
            return info("User with hint " + (rpr(hint)) + " exists:", TRM.truth(expectation), TRM.truth(exists), TRM.truth(exists === expectation));
          });
        };
      })(this)(hint, expectation));
    }
    return _results;
  };

  this.test_record_and_entry_from_prk = function(db, handler) {
    var prk;
    prk = 'user/uid:281fe6cd2daf';
    return USERDB.record_from_prk(db, prk, (function(_this) {
      return function(error, record) {
        if (error != null) {
          return handler(error);
        }
        debug(record);
        return USERDB.entry_from_prk(db, prk, function(error, entry) {
          if (error != null) {
            return handler(error);
          }
          log(TRM.gold(entry));
          return USERDB.close(db);
        });
      };
    })(this));
  };

  this.test_id_triplet_from_hint = function() {
    var bad_probes, db, error, expectation, good_probes, probe, result, _i, _j, _len, _len1, _ref, _ref1;
    log(TRM.blue('test_id_triplet_from_hint'));
    db = USERDB.new_db();
    good_probes = [['user/uid:17c07627d35e', ['user', 'uid', '17c07627d35e']], ['user/email:alice@hotmail.com/~prk', ['user', 'email', 'alice@hotmail.com']], ['user/name:Alice/~prk', ['user', 'name', 'Alice']], [['user', 'email', 'alice@hotmail.com'], ['user', 'email', 'alice@hotmail.com']], [['user', 'name', 'Alice'], ['user', 'name', 'Alice']], [['user', 'uid', '17c07627d35e'], ['user', 'uid', '17c07627d35e']], [['user', '17c07627d35e'], ['user', 'uid', '17c07627d35e']], [['user', 'some-uid'], ['user', 'uid', 'some-uid']], ['user/uid:2db2e22a4db5', ['user', 'uid', '2db2e22a4db5']]];
    bad_probes = [['XXXXXX:Alice/~prk', "unable to get ID facet from 'XXXXXX:Alice/~prk'"], ['some-random-text', "unable to get ID facet from \'some-random-text'"], ['foo/bar', "unable to get ID facet from \'foo/bar'"]];
    for (_i = 0, _len = good_probes.length; _i < _len; _i++) {
      _ref = good_probes[_i], probe = _ref[0], expectation = _ref[1];
      result = USERDB._id_triplet_from_hint(db, probe);
      info(probe, expectation, result, TRM.truth(BAP.equals(result, expectation)));
    }
    for (_j = 0, _len1 = bad_probes.length; _j < _len1; _j++) {
      _ref1 = bad_probes[_j], probe = _ref1[0], expectation = _ref1[1];
      try {
        result = USERDB._id_triplet_from_hint(db, probe);
      } catch (_error) {
        error = _error;
        if (TYPES.isa_jsregex(expectation)) {
          info(probe, expectation, rpr(error['message']), TRM.truth(expectation.test(error['message'])));
        } else {
          info(probe, expectation, rpr(error['message']), TRM.truth(expectation === error['message']));
        }
        continue;
      }
      throw new Error("" + (rpr(probe)) + " should have caused an error, but gave " + (rpr(result)));
    }
    return USERDB.close(db);
  };

  this.test_split_primary_record_key = function() {
    var db, expectation, probe, probes, result, _i, _len, _ref;
    db = USERDB.new_db();
    probes = [['user/uid:2db2e22a4db5', ['user', 'uid', '2db2e22a4db5']]];
    for (_i = 0, _len = probes.length; _i < _len; _i++) {
      _ref = probes[_i], probe = _ref[0], expectation = _ref[1];
      result = USERDB.split_primary_record_key(db, probe);
      info(probe, expectation, result, TRM.truth(BAP.equals(result, expectation)));
    }
    return USERDB.close(db);
  };

  this.test_id_triplet_from_hint();

}).call(this);
/****generated by https://github.com/loveencounterflow/larq****/