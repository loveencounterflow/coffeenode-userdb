

- [CoffeeNode UserDB](#coffeenode-userdb)
  - [What is it?](#what-is-it)
  - [Why ElasticSearch?](#why-elasticsearch)

> **Table of Contents**  *generated with [DocToc](http://doctoc.herokuapp.com/)*


# CoffeeNode UserDB

## What is it?

A simplistic CRUD API to work with persistent user data.


## Why Redis (and not ElasticSearch)?

<!--
[ElasticSearch](http://http://www.elasticsearch.org/) has a reputation for being a free, fast database
with advanced search capabilities that is built on top of [Apache Lucene](http://lucene.apache.org/),
thereby inheriting Lucene's performance and advanced full-text capabilities while shielding users from
the fantastic complexities in Lucene's design (think huge XML files and
`no.API.calls.with.less.than.six.dots`).

Granted, ElasticSearch may look like overkill when the requirement is just to store user data such as, say,
usernames, encrypted passwords and an email addresses. That said, it is quite typical for an application to
only ever use a fraction of the capabilities of *any* modern DB, and a 'tiny' solution like SQLite, while
certainly appropriate for quite a number of use cases, stops scaling quite early: no HTTP interface, no
access from multiple processes, and no replication.
 -->

## Configuration



    {
      "protocol":         "http",
      "hostname":         "localhost",
      "port":             9200,
      "base-route":       "/",
      "collection-name":  "users",
      "description": {
        "mappings": {
          "user": {
            "properties": {
              "_id": {
                "type": "string",
                "path": "uid"
              },
              "~isa": {
                "type": "string",
                "index": "not_analyzed"
              },
              "name": {
                "type": "string",
                "index": "not_analyzed"
              },
              "uid": {
                "type": "string",
                "index": "not_analyzed"
              },
              "password": {
                "type": "string",
                "index": "not_analyzed"
              },
              "email": {
                "type": "string",
                "index": "not_analyzed"
              }
            }
          }
        }
      }
    }



# Terminology

**Record**: any key / value pair entered into the DB, in its raw format—meaning that all values are strings.

**Record Key**: a key that is used to store a record; distinguish this from a facet which also has a key—but
not one that is used to store a record.

**Entry**: In the general sense, a record whose values has been cast; in the narrow sense, a Redis hash
value.

**(User) Entry**: a record whose value is a Redis hash that represents an 'entity' (e.g. a user). A record
must have exactly one primary key and may have zero or more secondary key.

**Field**, or **Facet**: a key / value pair stored in an entry (or other Redis hash), such as, say,
`email: 'john@example.com'`.

**Primary Key**: a name / value pair that uniquely identifies an entry.

**Primary Record Key (PRK)**: a key that is built from (1) an entry's type, (2) an entry's primary key name,
(3) an entry's primary key value, and (4) intermitted punctuation. For example, a given user entry may be
keyed as `user/uid:9a4c88dbc084`, from which we learn that the key (a) has an entry (a Redis hash) as value
(otherwise, it would have at least one more slash); (b) the entry is of type `user` (i.e. it has a facet
`~isa: 'user'`); (c) the primary key name of all entries of type 'user' is `uid` (because that is what we
find right after the first slash and before the first colon); (d) the entry's primary key value is
`9a4c88dbc084`(because that is what we find right after the colon that comes after the primary key name);
and (e) the entry thus keyed has a facet `uid: '9a4c88dbc084'`, and a facet `` (because all data that may be gleaned from
inspecting other keys is repeated inside an entry).

**Secondary Key**: Like a primary key, a name / value pair (Secondary Key Name (SKN), Secondary Key Value
(SKV)) that uniquely identifies an entry. The idea is that apart from primary keys (which, as shown in our
examples, may be ideal for a machine to uniquely identify an entry, but also less than ideal for a human to
remember, care for, or enter when asked), an entry may have other facets that should uniquely identify
it—like an associated email address or a user nickname.

**Secondary Record Key (SRK)**: Like a primary key, but built from a secondary key and the primary key name
of an entry, like `user/name:Jonny/~prk` or `user/email:john@example.com/~prk`. The `/~prk` suffix is found
on all secondary record keys; it symbolizes that the associated value is reflected in the entry's `~prk`
field (which is special like the `~isa` field, hence the `~` (wavy) sigil).

**Secondary Record Value (SRV)**: The value associated with a secondary record key; it is always an entry's
primary record key (PRK).

**Tertiary Key**: Looks like a primary key, except that it has one more field, like a secondary key; looks
like a secondary key, except that its does not end in `/~prk`, but a regular field name. It can be used it to
store values in one of Redis data types. For example, a user may be associated with tags indicating topics
of interest; those tags could then be stored as, say, `user/uid:9a4c88dbc084/tags: { 'javascript', 'python',
'c++' }`.


**Entry Type**: the value of an entry's `~isa` field.

```coffeescript
# Primary Record

user/uid:9a4c88dbc084:
  ~isa:   'user'
  ~prk:    'user/uid:9a4c88dbc084'
  uid:    '9a4c88dbc084'
  name:   'Jonny'
  email:  'john@example.com'
  job:    'Programmer, cooking hobbyist'
  tags:   XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Secondary Records

user/email:john@example.com/~prk:
  user/uid:9a4c88dbc084

user/name:Jonny/~prk:
  user/uid:9a4c88dbc084

# Tertiary Records

user/uid:9a4c88dbc084/tags: {
  'javascript'
  'python'
  'c++'         }
```




