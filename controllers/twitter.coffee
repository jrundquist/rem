exports = module.exports = (app) ->
  twitterHelper = (require '../lib/twitter')(app)

  app.get '/twitter/init', app.gate.requireLogin, (req, res) ->
    user = req.user
    twitter = new twitterHelper(user.twitter.username, user.twitterAuth)
    twitter.setupUser user, true, (err, result) ->
      console.log arguments
      res.json({err:err, result:result})
