async = require 'async'
Twit  = require 'twit'


class TwitterHelper

  users: {}

  constructor: (screen_name, auth) ->
    @screen_name = screen_name
    @api = new Twit(
                consumer_key:         process.env.TWITTER_CONSUMER_KEY
                consumer_secret:      process.env.TWITTER_CONSUMER_SECRET
                access_token:         auth.accessToken
                access_token_secret:  auth.accessTokenSecret
              )

  setupUser: (user, skipAPIcallsToTwitter, next) ->

    steps = [
      @.getRelations
      @.populateWithTwitterInfo
      @.syncWithUsers
      @.createGraphMappings
    ]

    if skipAPIcallsToTwitter
      steps = [
        (next)=>
          data = require('../twitter.json')
          r = data.result[0]
          @.followers = r.followers
          @.following = r.following
          @.relatedPeople = r.relatedPeople
          @.users = data.result[1]
          next null, 'loaded'
        @.syncWithUsers
        @.createGraphMappings
      ]

    async.series steps, (err, results) ->
        next err, results



  getRelations: (next) =>
    async.parallel {
        following: (next) => @_getIdsFromAPI 'friends/ids', next
        followers: (next) => @_getIdsFromAPI 'followers/ids', next
      }, (err, results) =>
        console.log '  callback!'
        @.following = results.following
        @.followers = results.followers
        @.relatedPeople = @.following.concat @.followers
        next err, following: @.following, followers: @.followers, relatedPeople: @.relatedPeople


  populateWithTwitterInfo: (next) =>
    @_getUsersFromAPI @.relatedPeople, (err, users) =>
      for user in users
        @.users[user.id] = user
      next err, users



  syncWithUsers: (next) =>
    next null, []

  createGraphMappings: (next) =>
    next null, []



  # API HELPERS
  _getUsersFromAPI: (ids=[], next ) ->
    chunks = ids.chunk 100
    if chunks.length is 1
      options=
        user_id: ids.join ','
      @api.post 'users/lookup', options, (err, reply, res) ->
        return next(err, collection) if err or reply.length is 0
        userFiltered = reply.map (user) ->
          id: user.id_str
          name: user.name
          username: user.screen_name
          location: user.location
          description: user.description
          image: user.profile_image_url_https
        next null, userFiltered
    else
      tracker = new (require('events')).EventEmitter()
      tracker.count = chunks.length
      tracker.error = null
      tracker.collection = []
      tracker.on 'oneDone', (err, collection) ->
        tracker.count--;
        if collection.length
          tracker.collection = tracker.collection.concat collection
        tracker.error = err if err
        if tracker.count is 0
          next tracker.error, tracker.collection

      _next = (err, collection) ->
        tracker.emit 'oneDone', err, collection

      for chunk in chunks
        do (chunk) =>
          @_getUsersFromAPI chunk, _next

  _getIdsFromAPI: (accessPoint, next, collection=[], cursor ) =>
    options=
      screen_name: @.screen_name
      stringify_ids: true
    if cursor
      options.cursor = cursor
    @api.get accessPoint, options, (err, reply, res) ->
      return next(err, collection) if err or reply.ids.length is 0
      collection = collection.concat reply.ids
      if reply.next_cursor and reply.next_cursor isnt 0
        getIdsFromAPI accessPoint, next, collection, reply.next_cursor
      else
        next null, collection


exports = module.exports = TwitterHelper