crypto    = require('crypto')
algorithm = "aes256"
key       = process.env.ENCRYPTION_KEY
mongoose  = require 'mongoose'
Schema    = mongoose.Schema
google    = require 'googleapis'
request   = require 'request'

neo4j     = require 'neo4j'
db        = new neo4j.GraphDatabase process.env.NEO4J_URL || 'http://localhost:7474'


USER_INDEX_NAME = 'users'

# Schema Setup
UserSchema = new Schema(
  email:
    type: String
    index: true
  firstName: String
  lastName: String

  gid: String

  _token: String
  _token_type: String
  _refresh_token: String

  twitter: {}
  _twitterAuth: String

  _node: {}

)

UserSchema.virtual('password')
  .get( () -> this._password )
  .set( (pass) ->
    @.setPassword(pass)
    @._password = pass
  )



UserSchema.virtual('token')
  .get( ()->
    if @._token
      return JSON.parse(@.decryptSecure @._token)
    undefined
  )
  .set( (obj) ->
    this._token = @.encryptSecure JSON.stringify(obj)
  )

# Dont wrap, b/c known to be one of a set of known values
# deceases security of encryption
UserSchema.virtual('token_type')
  .get( ()->
    @._token_type
  )
  .set( (obj) ->
    this._token_type = obj
  )

UserSchema.virtual('refresh_token')
  .get( ()->
    if @._refresh_token
      return JSON.parse(@.decryptSecure @._refresh_token)
    undefined
  )
  .set( (obj) ->
    this._refresh_token = @.encryptSecure JSON.stringify(obj)
  )

UserSchema.virtual('twitterAuth')
  .get( ()->
    if @._twitterAuth
      return JSON.parse(@.decryptSecure @._twitterAuth)
    undefined
  )
  .set( (obj) ->
    this._twitterAuth = @.encryptSecure JSON.stringify(obj)
  )

UserSchema.method('encryptSecure', (text) ->
  cipher = crypto.createCipher algorithm, key
  cipher.update(text, 'utf8', 'hex') + cipher.final('hex')
)
UserSchema.method('decryptSecure', (encrypted)->
  decipher = crypto.createDecipher algorithm, key
  decipher.update(encrypted, 'hex', 'utf8') + decipher.final('utf8')
)


UserSchema.virtual('id')
  .get( () -> this._id.toHexString() )

UserSchema.virtual('name')
  .get( () -> "#{@.firstName} #{@.lastName}".trim() )
  .set( (fullName) ->
    p = fullName.split ' '
    @.firstName = p[0]
    @.lastName = p[1]
  )

UserSchema.method('credentials', () ->
    oauth2Client = new google.OAuth2Client(
      process.env.GOOGLE_CLIENT_ID,
      process.env.GOOGLE_CLIENT_SECRET,
      process.env.GOOGLE_REDIRECT_URL);
    oauth2Client.credentials =
      token_type: @.token_type
      access_token: @.token,
      refresh_token: @.refresh_token
    oauth2Client
  )


UserSchema.method 'ensureHasNode', (next) ->
  if @.isNew
    return next new Error('New Objects must be saved before nodes can be attached')
  if @._node
    return next null, @._node
  else
    node = db.createNode id: @.id, name: @.name, firstName: @.firstName, lastName: @.lastName
    node.save (err) =>
      node.index USER_INDEX_NAME, 'id', @.id
      node.index USER_INDEX_NAME, 'name', @.name
      @._node = node.id
      @.save (err) ->
        next err, @._node


# UserSchema.post 'save', (doc) ->
#   console.log 'saving ',doc.id
#   doc.ensureHasNode ()=>console.log arguments
  # if typeof @._node is 'undefined'
  #   node = db.createNode id: @.id, name: @.name, firstName: @.firstName, lastName: @.lastName
  #   node.save (err) =>
  #     node.index USER_INDEX_NAME, 'id', @.id
  #     node.index USER_INDEX_NAME, 'name', @.name
  #     @._node = node.id
  #     @.save()
  # else
  #   db.getNodeById @._node, (err, node) =>
  #     node.data.firstName = @.firstName
  #     node.data.lastName = @.lastName
  #     node.data.name = @.name
  #     node.index USER_INDEX_NAME, 'id', @.id
  #     node.index USER_INDEX_NAME, 'name', @.id
  #     node.save()




#######
# Neo4j stuff
#######



UserSchema.method 'getNeo4jNode', (callback=(()->)) ->
  db.getNodeById @._node, (err, node) ->
    return callback err if err
    return callback new Error('Node not in neo4j') if not node
    callback null, node


UserSchema.method 'updateNeo4jNodeData', (dataToSet, callback=(()->)) ->
  @.getNeo4jNode (err, node) ->
    return callback(err) if err

    nodeChanged = false
    for key,val of dataToSet
      if typeof val isnt 'undefined' and val isnt null
        if val isnt node.data[key]
          nodeChanged = true
          node.data[key] = val
      else if typeof node.data[key] isnt 'undefined'
        nodeChanged = true
        delete node.data[key]
        # Request delete not nessisary if we just delete the property of the node, as a put is used on save
        ##request.del uri: "#{node.self}/properties/#{key}", headers: {'Accept': 'application/json'}, json: true

    if nodeChanged
      node.save (err) ->
        callback err, node
    else
      callback null, node


UserSchema.method 'createRelationshipTo', (otherUser, relation, data, callback=()->) ->
  if not @._node
    console.log "no _node\n\tSaving #{@.id}", @
    return callback new Error('no node attached to user '+@)
  db.getNodeById @._node, (err, node) ->
    return callback(err) if err
    return callback(new Error('User does not have node')) if not node
    if not otherUser._node
      otherUser.save (err) ->
        createLink(node)
    else
      createLink(node)

  createLink = (node) ->
    db.getNodeById otherUser._node, (err, other) ->
      return callback(err) if err

      node.getRelationshipNodes type: relation, direction: 'out', (err, adjacentNodes) ->
        if adjacentNodes.filter((n)-> return n.id is other.id).length < 1
          node.createRelationshipTo other, relation, data, callback
        else
          node.getRelationships relation, (err, relationships) ->
            callback null, relationships.filter((n)->return n.end.id is other.id)[0]







# Exports
exports.UserSchema = module.exports.UserSchema = UserSchema

exports.boot = module.exports.boot = (app) ->
  mongoose.model 'User', UserSchema
  app.models.User = mongoose.model 'User'

  app.models.User.findOrCreateByTwitterInfo = (twitterInfo, callback) ->
    if typeof twitterInfo is 'string'
      twitterInfo = id: twitterInfo
    app.models.User.findOne 'twitter.id': twitterInfo.id, (err, user) ->
      return callback(err) if err
      return callback(null, user) if user
      user = new app.models.User
        twitter: twitterInfo
        firstName: twitterInfo.name?.split(' ')[0]||twitterInfo.username
        lastName: twitterInfo.name?.split(' ')[1..]||undefined
      user.save () ->
        user.ensureHasNode do(user) -> (err, nodeId) ->
          callback err, user



