async = require 'async'

neo4j = require 'neo4j'
db    = new neo4j.GraphDatabase process.env.NEO4J_URL || 'http://localhost:7474'


exports = module.exports = (app) ->

  app.get '/neo4j/setup', (req, res) ->
    app.models.User.find {}, (err, users) ->
      async.map users, (user, next) ->
        data =
          name: user.name
          firstName: user.firstName
          lastName: user.lastName
        user.updateNeo4jNodeData data, do(data) -> (err, node) ->
          next err, {data:node.data, p:node.self}
      , (err, users) ->
        res.json err||users||'ok'
