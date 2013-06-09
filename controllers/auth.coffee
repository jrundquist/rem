nest = require 'unofficial-nest-api'

exports = module.exports = (app) ->
  # Home
  app.get '/login', (req, res) ->
    # Redirect to the everyauth google login
    res.redirect '/auth/google'


  app.get '/post-login-check', app.gate.requireLogin, (req, res) ->
    # Here we could do some checks but for now just redirect
    res.redirect '/'
