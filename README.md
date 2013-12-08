

- [CoffeeNode UserDB](#coffeenode-userdb)
	- [What is it?](#what-is-it)
	- [Why Redis (and not ElasticSearch)?](#why-redis-and-not-elasticsearch)
	- [Configuration](#configuration)
- [Terminology](#terminology)
		- [Entry Hints (Record Hints)](#entry-hints-record-hints)
	- [Restrictions on Secondary Field Values](#restrictions-on-secondary-field-values)

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


### Entry Hints (Record Hints)

Primary record:

* `user/uid:17c07627d35e: {"name":"Alice","password":"$2a$10$T8RGrZdn6gYd4WV…`

Secondary records:

* `user/email:alice@hotmail.com/~prk: 'user/uid:17c07627d35e'`
* `user/name:Alice/~prk:              'user/uid:17c07627d35e'`

Entry hints may have one of the following formats:

* using an existing entry

* using the PRK or an SRK:

  * `'user/email:alice@hotmail.com/~prk'`
  * `'user/name:Alice/~prk'`
  * `'user/uid:17c07627d35e'`

* using triplets spelling out type, field name, and field value:

  * `[ 'user', 'email', 'alice@hotmail.com', ]`
  * `[ 'user', 'name',  'Alice',             ]`
  * `[ 'user', 'uid',   '17c07627d35e',      ]`

* using a type / PKV pair:

  * `[ 'user', '17c07627d35e', ]`

Since 'user-specific' methods such as `get_user` already assume type 'user', those methods accept, in
addition to the above, the follwoing formats as entry hints:

* using the UID:

  * `'17c07627d35e'`

* field name / field value pairs:

  * `[ 'email', 'alice@hotmail.com', ]`
  * `[ 'name',  'Alice',             ]`
  * `[ 'uid',   '17c07627d35e',      ]`

You can *not* use type / PKV pair with the user-specific methods, as those would clash with field name /
field value pairs.

It is possible to use `*` as field name; this will be understood as referring to any one of the secondary
record fields:

* `[ '*', 'alice@hotmail.com', ]`
* `[ '*', 'Alice', ]`


## Restrictions on Secondary Field Values

The values of secondary keys must obey to the following constraints:

* they must be **string** values;
* they must be **non-empty**;
* they must be **unique** over all existing secondary key values *for the given type*.

The last constraint can also be expressed as follows: a given secondary key value `skv` is a valid choice
for a new entry of type `t` only if at that moment in time no SRK exists in the DB that would match
`$t/*:$skv/~prk`—meaning that Bob cannot opt for user name `alice@example.org` if Alice happened to have
registered that value for her email (or her user name, or any other secondary field) earlier.

At this point it may be worthwhile to shortly discuss what the reasons for the above constraints are and
where the strong and weak points of the schema lie. And, or course, what we can do to spare Alice the
embarrassing moment she realizes her legitmate, world-wide unique email has already (seemingly) be grabbed
by some Bob, otherwise unrelated to her.

The first constraint is of immediate practical utility: all values in Redis are strings, and although we can
always come up with arbitrary byte sequences to represent values of any type, it would be somewhat awkward
to do that with record keys, and of little use.

The second point grows out of a formalistic vantage point: if you have a collection data type `t` that
accommodates a variable number of elements, then it holds true that all instances of `t` with zero elements
are pairwaise equal–in other words, there is just a single empty list, a single empty dictionary, a single
empty string in the world. Now, primary and secondary keys are intended to be used as unique identifiers of
Db entities, and it is again the awkwardness of using a 'nothingness' of data for that job. Beyond that,
empty strings are special in that the 'have no letters' to write them down. Imagine your phone number had
zero digits—how would anyone ever call you? So we rule out this case. That said, it is of course sound to
restrict a user-generated secondary key, say, the user name, to a certain minimal and maximal length.

The third and last point grew out of the observation that more and more webapplications have become to
accept any one single uniqely identifying piece of data in a general, one-for-all field: for example, you
might use your customer number, your registered email address, or maybe even one of your past invoice
numbers (and a password) to log into some online shop system, without having to specify what you specified.
Such a feature is of high utility to content providers and web users alike—companies enjoy a higher ratio
of returning customers (who log in because they can, instead of hunting for an elusive customer ID buried in
a pile of paper), and web users can concentrate on remembering that damn password (a feat that is provably
too hard for those who have to remember more than a few, so let's try to make it not even harder).

So 'type-global uniqueness of all secondary ID values'—which is what the third constraint boils down to—is
born out of a pragmatic view. We have limited abilities to search data in Redis, and using patterns against
keys is one of the very precious, very few advanced techniques (short of iterating over all values, or
selecting ranges in a list or sorted set). In fact, i've looked into many a NoSQL / Key-Value Store /
GraphDB system over the past few years, and a great lot of systems has a much too limited way to search or
filter data for my taste. Redis seems to strike an interesting balance.

The third constraint allows us to fully leverage the power of Natural Keys ('Sprechende Schlüssel' in
German, that's 'eloquent keys'—a very eloquent name!). You have an ID you know we know, you want to log in
with us and don't know slash don't *care* whether it's your email? your nickname? your customer or invoice
number? your Social Security ID maybe? Well if it's all `#*!$` to you, then let it be
`user/*:YOURDATAHERE/~prk` to us. No problem!

In closing, let us have a look at how to avoid any possible embarrassed Alices: it is conceptually simple,
and the word is 'orthogonality of key values'. By this i mean that basically you should be able to tell what
secondary key field any given legal secondary key value belongs to: an email contains a `@`; a web URL
matches (at least) `/^https?://.+`; your invoice system may produce IDs with seven random digits, matching
`/^[0-9]{7}$/`. Barring unusal (or illegal?—not sure) email addresses starting with `http://`, any string
that complies with one these fields cannot comply with any other. All that remains is to implement a
constraint on the other fields (like user name) so they can't be mistaken: Say, a user name cannot contain
an `@` sign, cannot start with `http(s)://`, cannot just contain digits—and you're done: no more
overlapping key values, no more embarrassed Alices.











