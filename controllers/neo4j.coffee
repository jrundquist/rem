async = require 'async'
neo4j = require 'neo4j'
db    = new neo4j.GraphDatabase process.env.NEO4J_URL || 'http://localhost:7474'
natural   = require 'natural'
tokenize  = (new natural.TreebankWordTokenizer()).tokenize
metaphone = natural.Metaphone
soundEx   = natural.SoundEx
distance  = natural.LevenshteinDistance


exports = module.exports = (app) ->

  app.get '/neo4j/setup', (req, res) ->
    app.models.User.find {}, (err, users) ->
      async.map users, (user, next) ->
        data =
          name: user.name
          firstName: user.firstName
          lastName: user.lastName
          soundex: tokenize(user.name).map((token)->soundEx.process token).join('.')
        user.updateNeo4jNodeData data, do(data) -> (err, node) ->
          next err, {data:node.data, p:node.self}
      , (err, users) ->
        res.json err||users||'ok'
