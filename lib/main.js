(function() {
  var TRM, TYPES, alert, badge, debug, default_options, echo, help, info, log, mik_request, njs_fs, njs_path, njs_url, njs_util, rpr, warn, whisper;

  njs_util = require('util');

  njs_path = require('path');

  njs_fs = require('fs');

  njs_url = require('url');

  TYPES = require('coffeenode-types');

  TRM = require('coffeenode-trm');

  rpr = TRM.rpr.bind(TRM);

  badge = 'USERDB/main';

  log = TRM.get_logger('plain', badge);

  info = TRM.get_logger('info', badge);

  whisper = TRM.get_logger('whisper', badge);

  alert = TRM.get_logger('alert', badge);

  debug = TRM.get_logger('debug', badge);

  warn = TRM.get_logger('warn', badge);

  help = TRM.get_logger('help', badge);

  echo = TRM.echo.bind(TRM);

  mik_request = require('request');

  default_options = require('../options');

  this._esverb_by_verb = {
    'search': '_search',
    'define': '_mapping',
    'new-collection': '',
    'upsert': '',
    'remove': ''
  };

  this._http_method_by_verb = {
    'search': 'post',
    'define': 'post',
    'new-collection': 'put',
    'upsert': 'put',
    'remove': 'delete'
  };

  this.new_db = function() {
    var R, collection_name, name, value;
    R = {
      '~isa': 'USERDB/db'
    };
    for (name in default_options) {
      value = default_options[name];
      R[name] = value;
    }
    collection_name = R['collection-name'];
    R['base-route'] = R['base-route'].replace(/^\/*(.*?)\/*$/g, '$1');
    return R;
  };


  /* TAINT code duplication */

  this.new_collection = function(me, description, handler) {
    var http_method, request_options, url, _ref;
    _ref = this._get_url_and_method(me, null, 'new-collection'), url = _ref[0], http_method = _ref[1];
    request_options = {
      method: http_method,
      url: url,
      json: true,
      body: description
    };
    mik_request(request_options, (function(_this) {
      return function(error, response) {
        var result;
        if (error != null) {
          return handler(error);
        }
        result = response['body'];
        warn(result);
        if ((TYPES.type_of(result)) === 'text') {
          return handler(new Error(result));
        }
        if (!result['ok']) {
          return handler(new Error(rpr(result)));
        }
        return handler(null, result);
      };
    })(this));
    return null;
  };

  this.remove_collection = function(me, handler) {
    var http_method, request_options, url, _ref;
    _ref = this._get_url_and_method(me, null, 'remove'), url = _ref[0], http_method = _ref[1];
    request_options = {
      method: http_method,
      url: url,
      json: true,
      body: ''
    };
    mik_request(request_options, (function(_this) {
      return function(error, response) {
        var result;
        if (error != null) {
          return handler(error);
        }
        result = response['body'];
        warn(result);
        if ((TYPES.type_of(result)) === 'text') {
          return handler(new Error(result));
        }
        if (!result['ok']) {
          return handler(new Error(rpr(result)));
        }
        return handler(null, result);
      };
    })(this));
    return null;
  };

  this.upsert = function(me, entry, handler) {
    var entry_type, http_method, id, request_options, url, _ref;
    if ((entry_type = entry['~isa']) == null) {
      throw new Error("unable to update / insert entry without `~isa` attribute");
    }
    if ((id = entry['id']) == null) {
      throw new Error("unable to update / insert entry without `id` attribute");
    }
    _ref = this._get_url_and_method(me, entry_type, 'upsert', id), url = _ref[0], http_method = _ref[1];
    request_options = {
      method: http_method,
      url: url,
      json: true,
      body: entry
    };
    mik_request(request_options, (function(_this) {
      return function(error, response) {
        var result;
        if (error != null) {
          return handler(error);
        }
        result = response['body'];
        if ((TYPES.type_of(result)) === 'text') {
          return handler(new Error(result));
        }
        if (!result['ok']) {
          return handler(new Error(rpr(result)));
        }
        return handler(null, result);
      };
    })(this));
    return null;
  };

  this.search = function(me, entry_type, elastic_query, handler) {
    var arity, _ref;
    if ((arity = arguments.length) === 3) {
      _ref = [null, entry_type, elastic_query], entry_type = _ref[0], elastic_query = _ref[1], handler = _ref[2];
    } else if (!((3 <= arity && arity <= 4))) {
      throw new Error("expected three or four arguments, got " + arity);
    }
    return this._search(me, entry_type, elastic_query, handler);
  };

  this.search_entries = function(me, entry_type, elastic_query, handler) {

    /* Works exactly like `USERDB.search`, except that only the entries themselves are returned. */
    var arity, _ref;
    if ((arity = arguments.length) === 3) {
      _ref = [null, entry_type, elastic_query], entry_type = _ref[0], elastic_query = _ref[1], handler = _ref[2];
    } else if (!((3 <= arity && arity <= 4))) {
      throw new Error("expected three or four arguments, got " + arity);
    }
    this._search(me, entry_type, elastic_query, function(error, results) {
      if (error != null) {
        return handler(error);
      }
      return handler(null, results['entries']);
    });
    return null;
  };

  this._search = function(me, entry_type, elastic_query, handler) {
    var http_method, request_options, url, _ref;
    _ref = this._get_url_and_method(me, null, 'search'), url = _ref[0], http_method = _ref[1];
    request_options = {
      method: http_method,
      url: url,
      json: true,
      body: elastic_query
    };
    mik_request(request_options, (function(_this) {
      return function(error, response) {
        var results;
        if (error != null) {
          return handler(error);
        }
        results = _this._results_from_response(me, response);
        if (results['error'] != null) {
          return handler(results['error']);
        }
        return handler(null, results);
      };
    })(this));
    return null;
  };

  this.get = function(me, id_name, id_value, fallback, handler) {

    /* Given a name and a value for a (hopefully) field with unique values, find the one record matching
    those criteria. In case no entry was found, either call back with an error, or, if `fallback` was defined,
    call back with that value. Criteria that happen to match more than one entry will cause a callback with
    an error.
     */
    var arity, query, _ref;
    switch (arity = arguments.length) {
      case 4:
        _ref = [fallback, void 0], handler = _ref[0], fallback = _ref[1];
        break;
      case 5:
        null;
        break;
      default:
        return new Error("expected four or five arguments, got " + arity);
    }
    query = this.filter_query_from_id_facet(me, id_name, id_value);
    this.search(me, query, (function(_this) {
      return function(error, results) {
        var entries;
        if (error != null) {
          return handler(error);
        }
        entries = results['entries'];
        if (entries.length > 1) {
          return handler(new Error("search on non-unique field " + (rpr(id_name))));
        }
        if (entries.length === 0) {
          if (fallback !== void 0) {
            return handler(null, fallback);
          }
          return handler(new Error("unable to find user with " + id_name + ": " + (rpr(id_value))));
        }
        return handler(null, entries[0]);
      };
    })(this));
    return null;
  };

  this.filter_query_from_id_facet = function(me, id_name, id_value) {
    var R, filter;
    filter = {};
    filter[id_name] = id_value;
    R = {
      query: {
        filtered: {
          query: {
            match_all: {}
          },
          filter: {
            term: filter
          }
        }
      }
    };
    return R;
  };

  this._get_url_and_method = function(me, entry_type, verb, id) {

    /* Given a DB instance, an optional entry type, and one of the verbs specified as value in
    `USERDB._esverb_by_verb`, return a URL and a HTTP method name to run a request against. Examples:
    
        USERDB._get_url db, 'user', 'search'
        USERDB._get_url db, null, 'search'
        USERDB._get_url db, '', 'search'
    
    will result in, respectively,
    
        [ 'post', http://localhost:9200/users/user/_search ]
        [ 'post', http://localhost:9200/users/_search      ]
        [ 'post', http://localhost:9200/users/_search      ]
     */
    var esverb, http_method, pathname, url;
    if (entry_type == null) {
      entry_type = '';
    }
    if (id == null) {
      id = '';
    }
    esverb = this._esverb_by_verb[verb];
    if (esverb == null) {
      throw new Error("unknown verb " + (rpr(verb)));
    }
    pathname = njs_path.join(me['base-route'], me['collection-name'], entry_type, esverb, id);
    url = njs_url.format({
      protocol: me['protocol'],
      hostname: me['hostname'],
      port: me['port'],
      pathname: pathname
    });
    http_method = this._http_method_by_verb[verb];
    if (http_method == null) {
      throw new Error("unknown verb " + (rpr(verb)));
    }
    return [url, http_method];
  };

  this._results_from_response = function(me, response) {
    var R, body, count, dt, entries, error, headers, hit, hits, ids, request, request_url, scores, status, _i, _len, _ref, _ref1;
    request = response['request'];
    body = response['body'];
    request_url = request['href'];
    error = (_ref = body['error']) != null ? _ref : null;
    headers = response['headers'];
    status = body['status'];
    dt = body['took'];
    scores = [];
    entries = [];
    ids = [];
    count = 0;
    if ((hits = (_ref1 = body['hits']) != null ? _ref1['hits'] : void 0) != null) {
      count = body['hits']['total'];
      for (_i = 0, _len = hits.length; _i < _len; _i++) {
        hit = hits[_i];
        scores.push(hit['_score']);
        entries.push(hit['_source']);
        ids.push(hit['_id']);
      }
    }
    R = {
      '~isa': 'USERDB/response',
      'url': request_url,
      'status': status,
      'error': error,
      'scores': scores,
      'ids': ids,
      'entries': entries,
      'count': count,
      'first-idx': 0,
      'dt': dt
    };
    return R;
  };

}).call(this);
/****generated by https://github.com/loveencounterflow/larq****/