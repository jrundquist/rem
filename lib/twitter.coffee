async = require 'async'
Twit  = require 'twit'

exports = module.exports = (app) ->

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

    setupUser: (user, skipAPIcallsToTwitter, callback) =>

      getRelations = (next) =>
        async.parallel {
            following: (next) => @_getIdsFromAPI 'friends/ids', next
            followers: (next) => @_getIdsFromAPI 'followers/ids', next
          }, (err, results) =>
            @.following = results.following
            @.followers = results.followers
            @.relatedPeople = (@.following.concat @.followers).unique()
            next err, following: @.following, followers: @.followers, relatedPeople: @.relatedPeople

      populateWithTwitterInfo = (next) =>
        @_getUsersFromAPI @.relatedPeople, (err, users) =>
          for user in users
            @.users[user.id] = user
          next err, users

      syncWithUsers = (next) =>
        # Makes an array of the user object
        twitterUserObjectsArray = []
        for user, val of @.users
          twitterUserObjectsArray.push val if @.users.hasOwnProperty user

        # Turn this nice array into one of actuall User Objects
        async.map twitterUserObjectsArray, app.models.User.findOrCreateByTwitterInfo, (err, users) =>
          for twitterId, twitterInfo of @.users
            do (twitterId, twitterInfo) =>
              @.users[twitterId] = (users.filter (u) -> u.twitter.id is twitterId)[0]
          next err, users.map (u) -> u.id

      createGraphMappings = do(user) => (next) =>
        async.parallel {
          linkFollowers: (next) =>
            async.each @.followers, (twitterId, next) =>
              @.users[twitterId].createRelationshipTo user, 'following', {}, next
            , (err) =>
              next err, @.followers.length
          linkFollowing: (next) =>
            async.each @.following, (twitterId, next) =>
              user.createRelationshipTo @.users[twitterId], 'following', {}, next
            , (err) =>
              next err, @.following.length
          }, next


      steps = [
        getRelations
        populateWithTwitterInfo
        syncWithUsers
        createGraphMappings
      ]

      ## TODO: remove
      if skipAPIcallsToTwitter
        steps = [
          (next) =>
            data = require('../twitter.json')
            r = data.result[0]
            @.followers = r.followers
            @.following = r.following
            @.relatedPeople = r.relatedPeople.unique()
            users = data.result[1]
            for user in users
              @.users[user.id] = user
            next null, "loaded #{@.relatedPeople.length} users over #{@.followers.length+@.following.length} relationships"
          syncWithUsers
          createGraphMappings
        ]

      async.series steps, (err, results) =>
        callback err, results


    # API HELPERS
    _getUsersFromAPI: (ids=[], next ) ->
      chunks = ids.chunk 100
      if chunks.length is 1
        options=
          user_id: ids.join ','
        @api.post 'users/lookup', options, (err, reply, res) ->
          return next(err) if err or reply.length is 0
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


  # Return the object
  TwitterHelper
