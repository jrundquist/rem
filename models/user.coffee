crypto    = require('crypto')
algorithm = "aes256"
key       = process.env.ENCRYPTION_KEY
mongoose  = require 'mongoose'
Schema    = mongoose.Schema
google    = require 'googleapis'

neo4j     = require 'neo4j'
db        = new neo4j.GraphDatabase process.env.NEO4J_URL || 'http://localhost:7474'


USER_INDEX_NAME = 'users'
USER_INDEX_KEY  = 'userId'


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


UserSchema.post 'save', (next) ->
  if not @._node
    node = db.createNode id: @.id, name: @.name, firstName: @.firstName, lastName: @.lastName
    node.save (err) =>
      node.index USER_INDEX_NAME, USER_INDEX_KEY, @.id
      @._node = node.id
      @.save()
  else
    db.getNodeById @._node, (err, node) =>
      node.data.firstName = @.firstName
      node.data.lastName = @.lastName
      node.data.name = @.name
      node.save()




#######
# Neo4j stuff
#######



UserSchema.method 'getNeo4jNode', (callback=(()->)) =>
  db.getNodeById @._node, callback




UserSchema.method 'createRelationshipTo', (otherUser, relation, data, callback=()->) ->
  return callback(new Error('User does not have node in graph')) if not @._node
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


