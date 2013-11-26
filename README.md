

- [CoffeeNode UserDB](#coffeenode-userdb)
	- [What is it?](#what-is-it)
	- [Why ElasticSearch?](#why-elasticsearch)

> **Table of Contents**  *generated with [DocToc](http://doctoc.herokuapp.com/)*


# CoffeeNode UserDB

## What is it?

A simplistic CRUD API to work with persistent user data.


## Why ElasticSearch?

[ElasticSearch](http://http://www.elasticsearch.org/) has a reputation for being a free, fast database
with advanced search capabilities that is built on top of [Apache Lucene](http://lucene.apache.org/),
thereby inheriting Lucene's performance and advanced full-text capabilities while shielding users from
the fantastic complexities in Lucene's design (think huge XML files and
`no.API.calls.with.less.than.six.dots`).

Granted, ElasticSearch may look like overkill when the requirement is just to store user data such as, say,
usernames, encrypted passwords and an email addresses. That said, it is quite typical for an application to
only ever use a fraction of the capabilities of *any* modern DB, and a 'tiny' solution like SQLite, while
certainly appropriate for quite a number of use cases, stops scaling quite early: no HTTP interface, no
access from multiple processes, no replication—and, of course, it's still a relational DB.






