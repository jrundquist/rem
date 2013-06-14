exports = module.exports = (app) ->

  app.get '/', (req, res) ->
    if req.user
      res.render 'account'
    else
      res.render 'index'

  app.get '/home', (req, res) ->
    res.render 'index'



  app.get '/about', (req, res) ->
    res.render 'about'




  app.get '/settings', app.gate.requireLogin, (req, res) ->
    res.render 'account/settings'


  app.post '/settings', app.gate.requireLogin, (req, res) ->
    req.user.structure = req.body.structure
    req.user.device = req.body.device
    req.user.celcius = req.body.celcius is 'true'
    req.user.save()
    req.user.updateNestCard app
    res.redirect '/'



