exports = module.exports = (app) ->

  app.post '/subscription/callback', (req, res) ->

    payload = req.body

    if payload.verifyToken is process.env.GOOGLE_VERIFY_TOKEN
      res.send 200
    else
      return res.send 401

    ## Gret the user from the payload
    app.models.User.findOne( _id: payload.userToken ).exec (err, user) ->
      return if err or not user



