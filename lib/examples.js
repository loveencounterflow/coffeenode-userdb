(function() {
  var TRM, TYPES, USERDB, alert, badge, db, debug, echo, help, info, log, njs_fs, njs_path, njs_url, njs_util, query, rpr, warn, whisper;

  njs_util = require('util');

  njs_path = require('path');

  njs_fs = require('fs');

  njs_url = require('url');

  TYPES = require('coffeenode-types');

  TRM = require('coffeenode-trm');

  rpr = TRM.rpr.bind(TRM);

  badge = 'USERDB/test';

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
    description = {
      'mappings': {
        'user': {
          'properties': {
            '~isa': {
              'type': 'string',
              'index': 'not_analyzed'
            },
            'name': {
              'type': 'string',
              'index': 'not_analyzed'
            },
            'uid': {
              'type': 'string',
              'index': 'not_analyzed'
            },
            'password': {
              'type': 'string',
              'index': 'not_analyzed'
            },
            'email': {
              'type': 'string',
              'index': 'not_analyzed'
            }
          }
        }
      }
    };
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
        '~isa': 'user',
        'name': 'Just A. User',
        'id': '888',
        'uid': '888',
        'password': 'secret',
        'email': 'jauser@example.com'
      }, {
        '~isa': 'user',
        'name': 'Alice',
        'id': '889',
        'uid': '889',
        'password': 'nonce',
        'email': 'alice@hotmail.com'
      }, {
        '~isa': 'user',
        'name': 'Bob',
        'id': '777',
        'uid': '777',
        'password': 'youwontguess',
        'email': 'bobby@acme.corp'
      }, {
        '~isa': 'user',
        'name': 'Clark',
        'id': '123',
        'uid': '123',
        'password': '*?!',
        'email': 'clark@leageofjustice.org'
      }
    ];
    _results = [];
    for (_i = 0, _len = entries.length; _i < _len; _i++) {
      entry = entries[_i];

      /* TAINT this should be accomplished by suitable entry type definition: */
      _results.push(USERDB.upsert(me, entry, function(error, result) {
        if (error != null) {
          throw error;
        }
        return log(TRM.rainbow(result));
      }));
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

  info(db = USERDB.new_db());

  query = {
    query: {
      match_all: {}
    }
  };

  USERDB.get(db, 'email', 'alice@hotmail.com', function(error, entry) {
    if (error != null) {
      throw error;
    }
    return log(TRM.rainbow(entry));
  });

}).call(this);
/****generated by https://github.com/loveencounterflow/larq****/