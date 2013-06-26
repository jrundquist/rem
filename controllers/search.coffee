mongoose  = require 'mongoose'
async     = require 'async'
neo4j     = require 'neo4j'
db        = new neo4j.GraphDatabase process.env.NEO4J_URL || 'http://localhost:7474'
natural   = require 'natural'
tokenize = (new natural.TreebankWordTokenizer()).tokenize
metaphone = natural.Metaphone
soundEx   = natural.SoundEx
distance  = natural.LevenshteinDistance
_         = require 'underscore'


exports = module.exports = (app) ->

  app.get '/search', app.gate.requireLogin, (req, res) ->
    res.render 'search'



  app.post '/search', app.gate.requireLogin, (req, res) ->

    queryTokens = tokenize req.body.search

    queryTokensSoundEx = queryTokens.map (token) -> soundEx.process token

    async.map queryTokensSoundEx, (soundex, _next) ->
      query = "START me=node:users(id='#{req.user.id}')\n\
                MATCH me-[relation]-friend\n\
                WHERE friend.soundex =~ '(.*\\\\.)?#{soundex}(\\\\..*)?'\n\
                RETURN DISTINCT friend.id as id, relation".replace(/\n\s+/g, "\n")
      next = _.once(_next)
      db.query query, {}, (err, queryResult=[]) ->
        queryResult = queryResult.map (result) -> id: result.id, how: result.relation._data.type
        colatedResults = {}
        for resObj in queryResult
          colatedResults[resObj.id] = colatedResults[resObj.id]||{id:resObj.id, how:{}}
          colatedResults[resObj.id].how[resObj.how] = (colatedResults[resObj.id].how[resObj.how]||0)+1
        next err, colatedResults

      # Callback Function time!
    , (err, resultArray) ->
      # make the results objects
      mergedResults = {}
      mergedResultsList = []

      # Merge the results per term into a single result set
      for termResult, i in resultArray
        for id, result of termResult
          mergedResults[id] = mergedResults[id]||{id: id, how: {}}
          for how, count of result.how
            mergedResults[id].how[how] = (mergedResults[id].how[how]||0)+count
            mergedResults[id].score = (mergedResults[id].score||0)+count

      # create an array of the user objects
      for id, result of mergedResults
        mergedResultsList.push result

      # Sort the results based on score
      mergedResultsList = mergedResultsList.sort (a, b) -> b.score - a.score

      async.map mergedResultsList, (graphResult, next) ->
        app.models.User.findOne _id: graphResult.id, (err, user) ->
          graphResult.user = user
          next null, graphResult
      , (err, results) ->
        res.json err: err, result: results


